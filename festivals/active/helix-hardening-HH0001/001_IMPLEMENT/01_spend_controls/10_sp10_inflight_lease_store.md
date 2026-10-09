---
fest_type: task
fest_id: 10_sp10_inflight_lease_store.md
fest_name: sp10 inflight lease store
fest_parent: 01_spend_controls
fest_order: 10
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.33664-06:00
fest_updated: 2026-10-09T17:03:40.32374-06:00
fest_tracking: true
---


# Task: sp10 inflight lease store

## Objective

Add a Postgres-backed lease store with a TTL, and its `inflight_leases` table and grants, so a later change can cap in-flight calls per app and per user across all edge replicas. Implements SP-10 from 01-spend-controls.md.

This change widens what the edge database role can do (a new table it can insert into and delete from). It extends the ADR-0002 amendment that the platform-spend change began, and `role-split.integration.test.ts`.

## Requirements

- [ ] No prerequisite from an earlier task in this sequence. It touches the same ADR-0002 amendment as `08_sp8_platform_spend_definer_function.md`, so land after it or merge its text. `11_sp11_llm_concurrency_caps_and_deadline.md` and `12_sp12_fetch_lease_caps.md` depend on this task.
- [ ] New table `inflight_leases(id uuid, scope text, "expiresAt" timestamp(3))`, primary key `(id, scope)`, index on `(scope, "expiresAt")`. One lease id spans one row per scope it holds.
- [ ] Grants: `helix_edge` has `SELECT, INSERT, DELETE` and nothing else (no `UPDATE`). `helix_portal` has no access at all (revoke what the blanket grant gives it). `helix_egress` and `helix_dev` have none. No row-level security: the scope string embeds the app id, as `rate_counters` keys do.
- [ ] `LeaseStore` interface and two implementations in `apps/edge/src/gateway/leaseStore.ts`: `PgLeaseStore` and `InMemoryLeaseStore` (tests and the dev gateway).
- [ ] `acquire` takes a list of `{ scope, cap }` and a TTL. It takes `pg_advisory_xact_lock(hashtextextended(scope, 0))` for each distinct scope **in sorted order**, counts unexpired leases per scope, and inserts one row per scope only if every count is under its cap; otherwise it inserts nothing and reports which scope was full. The advisory lock makes check-then-insert atomic; a bare `count(*)` then `INSERT` is not under READ COMMITTED.
- [ ] Never exceeds a cap under concurrency: with cap 5 and many parallel acquires, exactly 5 succeed, including across two stores on separate pools (two replicas).
- [ ] An expired lease never counts, even before it is swept (`"expiresAt" > now()` in the count).
- [ ] `release(leaseId)` deletes every row of the lease; releasing an unknown id is a no-op. `sweep()` deletes expired rows.
- [ ] A cap of `0` or less for a scope means "no cap on that scope": the scope is skipped and takes no row. This is the per-scope off value.
- [ ] Failure paths. Acquire fails (database down, lock wait past the statement timeout): the call rejects, and the caller (the next task) fails closed. A failed acquire leaves no rows behind (the transaction rolls back). Acquiring `[A,B]` in one call and `[B,A]` in another cannot deadlock, because both sort. A release that fails or a replica that dies leaks its leases only until `expiresAt`.
- [ ] The pool fails fast: waiters for a free connection time out rather than queue forever.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-10-inflight-lease-store`.

2. The Prisma model. Without it, `prisma migrate dev` will report drift. In `apps/portal/prisma/schema.prisma`, next to `InstructionJti` (it ends at line 395), add, in the style of `RateCounter` (lines 347-356):

```prisma
/// In-flight call leases behind the edge's per-app and per-user concurrency caps. **Edge-written
/// data**: the edge inserts one row per scope per admitted call (apps/edge/src/gateway/leaseStore.ts)
/// and deletes them when the call ends. A row also expires at `expiresAt`, so a replica that dies
/// leaks a slot only until then. No RLS: `scope` embeds the app id, the way rate_counters keys
/// do. `helix_edge` has SELECT+INSERT+DELETE; every other role is carved out.
model InflightLease {
  id        String   @db.Uuid
  scope     String
  expiresAt DateTime

  @@id([id, scope])
  @@index([scope, expiresAt])
  @@map("inflight_leases")
}
```

3. The migration. Generate the table SQL, then append the grants:
   - `pnpm --filter @azx-pbc/portal db:migrate --name inflight_leases` in the dev container (this runs `prisma migrate dev`, which creates `apps/portal/prisma/migrations/<timestamp>_inflight_leases/migration.sql`). The timestamp must sort after the platform-spend migration from the previous task.
   - Append the grants, copying the guarded idiom and the comment style from `apps/portal/prisma/migrations/20260721215912_shared_rate_counters_and_jti_burn/migration.sql`:

```sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'helix_edge') THEN
    GRANT SELECT, INSERT, DELETE ON inflight_leases TO helix_edge;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'helix_portal') THEN
    -- The blanket grant in db-init/01-roles.sql (and infra/azure/sql/01-roles.sql) gives the
    -- control plane full DML on every owner-created table. It never touches this one.
    REVOKE ALL ON inflight_leases FROM helix_portal;
  END IF;
END $$;
```

     `helix_egress` and `helix_dev` get no grant (the runtime roles other than the portal have no default privileges). Run `pnpm --filter @azx-pbc/portal exec prisma migrate status` and confirm there is no drift, then `pnpm --filter @azx-pbc/portal db:generate`. The generated client directory (`apps/portal/src/db/generated/`) is gitignored; do not commit it.

4. Create `apps/edge/src/gateway/leaseStore.ts`. Follow the shape of `apps/edge/src/gateway/counterStore.ts` (an interface, a Postgres class built on `createEdgePool`, an in-memory class with an injectable clock). `pool.connect()` is banned by lint outside `withPooledClient` (`apps/edge/src/db/pool.ts:121`): check a client out through it, as `withPartition` does (`apps/edge/src/db/partition.ts`).

```ts
import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import { createEdgePool, withPooledClient, type EdgePoolOpts } from "../db/pool.js";

export interface LeaseRequest {
  /** `llm:app:<appId>`, `llm:user:<appId>:<userOid>`, `fetch:app:<appId>`. */
  scope: string;
  /** Maximum unexpired leases on this scope. 0 or less means no cap: the scope takes no row. */
  cap: number;
}

export type AcquireResult = { ok: true; leaseId: string } | { ok: false; scope: string };

export interface LeaseStore {
  /** All scopes or none. `ttlMs` bounds how long a leaked lease can hold a slot. */
  acquire(requests: readonly LeaseRequest[], ttlMs: number): Promise<AcquireResult>;
  release(leaseId: string): Promise<void>;
  /** GC expired rows. Correctness never depends on it: expired leases are not counted. */
  sweep(): Promise<void>;
  close(): Promise<void>;
}
```

   `PgLeaseStore`:
   - constructor `(databaseUrl, opts: EdgePoolOpts = {})`: `createEdgePool(databaseUrl, { ...opts, max: opts.max ?? 10, connectionTimeoutMs: opts.connectionTimeoutMs ?? 5_000, label: opts.label ?? "leases" })`. Spread the opts, do not re-list them (see the note in `apps/edge/src/auth/sessions.ts` that `usage.ts` cites). The connection timeout makes a saturated pool fail closed instead of queueing; lock waiters hold a connection, so size the pool with the statement timeout in mind (a blocked acquire is cancelled by the edge's `statement_timeout`).
   - `acquire`: drop requests with `cap <= 0`; if none are left, return `{ ok: true, leaseId }` without touching the database; de-duplicate by scope (keep the smallest cap); sort scopes; then:

```ts
    return withPooledClient(this.#pool, async (client) => {
      await client.query("BEGIN");
      try {
        for (const { scope } of sorted) {
          await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [scope]);
        }
        for (const { scope, cap } of sorted) {
          const res = await client.query<{ n: number }>(
            `SELECT count(*)::int AS n FROM inflight_leases WHERE scope = $1 AND "expiresAt" > now()`,
            [scope],
          );
          if ((res.rows[0]?.n ?? 0) >= cap) {
            await client.query("ROLLBACK");
            return { ok: false as const, scope };
          }
        }
        await client.query(
          `INSERT INTO inflight_leases (id, scope, "expiresAt")
             SELECT $1::uuid, s, now() + ($3::text || ' milliseconds')::interval
             FROM unnest($2::text[]) AS s`,
          [leaseId, sorted.map((r) => r.scope), ttlMs],
        );
        await client.query("COMMIT");
        return { ok: true as const, leaseId };
      } catch (err) {
        await client.query("ROLLBACK").catch(() => {});
        throw err;
      }
    });
```

   - `release`: `DELETE FROM inflight_leases WHERE id = $1`. `sweep`: `DELETE FROM inflight_leases WHERE "expiresAt" < now()`. `close`: `this.#pool.end()`.
   - Docblock: the lock keys are hashes of the scope, so two scopes can collide and serialize needlessly; that costs a little latency and is never incorrect. The comparison `"expiresAt" > now()` mixes `timestamp(3)` with `now()`; this is the same pattern `PgCounterStore` uses for `"resetAt"` (`counterStore.ts`). Lease rows live seconds to minutes, so a timezone mismatch would show up at once in the integration test's expiry case.

   `InMemoryLeaseStore`: a `Map<string, Map<string, number>>` of scope to leaseId to expiry, an injectable `now: () => number = Date.now`, the same all-or-none semantics, and expiry checked on read. Document that it is single-process: unit tests and the dev gateway only.

5. Tests.
   - `apps/edge/src/gateway/leaseStore.test.ts` (in-memory, deterministic clock): acquire up to the cap then refuse and name the full scope; two scopes where the second is full leaves the first untouched (acquire a third caller on the first scope afterward and it still has its full capacity); release frees a slot; an expired lease frees its slot with no sweep; `sweep` removes expired entries only; `cap <= 0` skips the scope; duplicate scopes in one call; releasing an unknown id is a no-op; a call with only uncapped scopes returns a lease id and holds nothing.
   - `apps/edge/src/gateway/leaseStore.integration.test.ts` (`PgLeaseStore` as `helix_edge`, following `counterStore.integration.test.ts`: `edgeUrl()`, an availability check that skips when the role is missing, unique scope strings per test such as `test:${randomUUID()}`, cleanup as the owner with `DELETE FROM inflight_leases WHERE scope LIKE 'test:%'`):
     - basic acquire, refuse at cap, release;
     - **concurrency**: 50 parallel acquires on one scope with cap 5: exactly 5 succeed (the race a bare count would lose);
     - **two replicas**: two stores built on separate pools, 25 parallel acquires each, cap 5: exactly 5 succeed in total;
     - **no deadlock**: 40 parallel acquires with scopes `[A, B]` and 40 with `[B, A]`, each cap 100: all 80 succeed and none rejects with a deadlock error (`40P01`);
     - **expiry without a sweep**: acquire with a negative TTL (an already-expired lease, as `counterStore.integration.test.ts` uses negative windows) on a cap-1 scope; the next acquire succeeds;
     - **crash simulation**: acquire with a 200 ms TTL, never release, sleep past it, and acquire again on a cap-1 scope;
     - `sweep()` removes expired rows (count them through the owner pool before and after);
     - **atomicity**: a refused acquire leaves no row for any of its scopes.
   - `apps/edge/src/registry/role-split.integration.test.ts`: a new `describe` modeled on the `app_visits` block (line 835): `helix_edge` can `SELECT`, `INSERT` and `DELETE` on `inflight_leases`; `UPDATE` is `permission denied`; `helix_portal` (use `portalUrl()` and `portalRoleAvailable()`, lines 251 and 258), `helix_egress` (`egressUrl()`, `egressRoleAvailable()`) and `helix_dev` (`devUrl()`, `devRoleAvailable()`) get `permission denied` on `SELECT`. Put the denials first, as the `app_visits` test does, and clean up the rows you insert.

6. ADR-0002. Open the amendment the platform-spend task added to `docs/adr/0002-postgres-role-split-rls.md` and extend it (do not add a second amendment): the `inflight_leases` table, its grants (`helix_edge` `SELECT, INSERT, DELETE`; the portal revoked; the others none), why there is no RLS (the scope embeds the app id; the table holds no app data), and that an edge compromise can already exhaust its own caps by inserting rows, which is within what the edge could already do to its own rate counters. Leave the ADR-0011 pointer and ADR-0051 to `13_sp13_adr_and_docs.md`.

7. No telemetry in this task: the store is not wired to a handler yet, so there is no decision point to instrument. The denial counter and the acquire-failure signal ship with the wiring in `11_sp11_llm_concurrency_caps_and_deadline.md`.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The concurrency, two-replica and no-deadlock integration tests pass, and pass when run twice in a row.
- [ ] `prisma migrate status` shows no drift; the migration applies on a fresh database (`just db reset` or the smoke runner's own database).
- [ ] `./check-and-lint.sh` passes in the dev container (Postgres and Azurite running). Output saved under `results/`.
- [ ] `just dev smoke` passes (the runner migrates a fresh database, so it proves the migration applies). Output saved under `results/`.
- [ ] ADR-0002 amendment extended. Committed with `fest commit -m "SP-10: add the in-flight lease store and table"`.
- [ ] Nothing Azure-specific in this task beyond the migration running under the production owner role (`helixadmin`), which is the same mechanism as every earlier migration. The grants are checked only against the dev cluster's roles.