---
fest_type: task
fest_id: 08_sp8_platform_spend_definer_function.md
fest_name: sp8 platform spend definer function
fest_parent: 01_spend_controls
fest_order: 8
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.335931-06:00
fest_updated: 2026-10-09T16:38:00.001947-06:00
fest_tracking: true
---


# Task: sp8 platform spend definer function

## Objective

Add a `SECURITY DEFINER` Postgres function that returns the platform-wide LLM spend for the day and the last hour (two numbers, no per-app breakdown) to `helix_edge`, together with the owner-readable policy it needs on `gateway_calls`, and record the change in ADR-0002. Implements SP-8 from 01-spend-controls.md.

This change widens what the edge database role can do. It gets the same dedicated review pass the auth code gets (FESTIVAL_RULES; `AGENTS.md`).

## Requirements

- [ ] No prerequisite from an earlier task in this sequence (the design orders it after `07_sp7_admission_denial_throttle.md` only for review order). `09_sp9_platform_daily_ceiling.md` depends on it.
- [ ] First, confirm the production migration owner role name and write it in the PR text and in `results/sp8-owner-role.md`. The design leaves this open (design, Open questions item 1). The evidence already read for this plan: `infra/azure/sql/01-roles.sql:68-70` says `FOR ROLE helixadmin` "must name the object owner that runs `db:deploy`", the Bicep param `postgresAdminLogin` defaults to `helixadmin` (`infra/azure/main.bicep:83`), and `apps/portal/scripts/migrate-deploy.ts` is documented as running Prisma migrations as the schema owner `helixadmin`. The dev and test owner is `helix` (`.devcontainer/db-init/01-roles.sql:4`). Re-read all three yourself and confirm. If the owner an install uses cannot be named by the migration at apply time, stop and ask: the fallback (a dedicated NOLOGIN role) needs `CREATEROLE`, which is unconfirmed for the Azure migration identity.
- [ ] `platform_llm_spend_micro_usd(p_env text)` is `SECURITY DEFINER`, has a pinned `search_path = pg_catalog, public`, schema-qualifies `public.gateway_calls`, returns only `today bigint` and `hour bigint`, has `EXECUTE` revoked from `PUBLIC`, and granted to `helix_edge` only.
- [ ] An owner `SELECT` policy exists on `gateway_calls` (`FOR SELECT TO <migration owner> USING (true)`), bound to whichever role runs the migration (`format('%I', current_user)` in a `DO` block). Reason: `gateway_calls` is `FORCE ROW LEVEL SECURITY`, and under `FORCE` the table owner is subject to RLS, so a definer function run by the owner matches no existing policy (they are all role-scoped) and sees zero rows.
- [ ] A direct `SELECT` as `helix_edge` with no partition GUC still returns zero rows. `helix_edge` still has no `UPDATE` or `DELETE` on `gateway_calls`. `helix_portal` and `helix_egress` cannot execute the function. `helix_dev` has no grant.
- [ ] Failure path. A missing owner policy makes the function return zeros silently, which would disable the platform ceiling without any error. Two tests pin this: a catalog check that the policy exists for the function's owner, and a test that runs the exact migration SQL under a non-superuser, RLS-subject owner and gets a non-zero sum (step 5). The dev and test owner `helix` is a superuser and bypasses RLS, so an ordinary integration test with rows present cannot catch a missing policy locally; do not rely on one.
- [ ] Failure path. The function is not a broad read primitive: it takes the environment only, and returns aggregates. A test asserts no per-app breakdown is exposed.
- [ ] ADR-0002 is amended: the new function, the owner policy, and why they add no reach.
- [ ] Failure path for rollout: the migration is additive and can stay if the edge image is rolled back. State in the PR that the migration must be applied before the edge image that uses it (operator rollout note, written in `13_sp13_adr_and_docs.md`).

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-8-platform-spend-definer`.

2. Read the precedent end to end before writing SQL: `apps/portal/prisma/migrations/20260721035543_rls_sessions_definer_lookup/migration.sql` (the `session_lookup` and `session_sweep` functions: `SECURITY DEFINER`, `SET search_path = pg_catalog, public`, schema-qualified table, `REVOKE ... FROM PUBLIC`, a guarded `GRANT ... TO helix_edge`). Note its stated reason for `ENABLE` rather than `FORCE` on `sessions`: under `FORCE` an owner-run function matches no role-scoped policy. `gateway_calls` is `FORCE` (`apps/portal/prisma/migrations/20260721033820_rls_gateway_calls_collection_items/migration.sql`), which is why this change needs the owner policy instead. Also read the current `gateway_calls` policies: `20260722192440_dev_env_partition/migration.sql` replaced the edge policy with an env-literal one (`"env" = 'prod' AND "appId" = current_setting('app.app_id', true)::uuid`) and added `gateway_calls_dev_only`.

3. Create the migration directory `apps/portal/prisma/migrations/<UTC timestamp>_platform_llm_spend_definer/` with a `migration.sql`. The timestamp must sort after `20261002120000_app_visits`, the newest today (use the real creation time, format `YYYYMMDDHHMMSS`). Prisma does not model functions or policies, so `apps/portal/prisma/schema.prisma` does not change (the sessions definer migration is the precedent). Write the file by hand; do not generate it with `migrate dev`.

```sql
-- ADR-0002 amendment: the platform-wide LLM spend aggregate behind the daily ceiling.
--
-- The edge reads spend through withPartition, and the gateway_calls RLS policy scopes every
-- read to one app, so a cross-app sum cannot be a plain query. This function returns two
-- aggregates (today, last hour) for one env and nothing else. It adds no reach: helix_edge
-- can already read every app's rows one at a time by setting app.app_id itself. The real
-- boundary (no grant on app_secrets or registry writes) is unchanged.
--
-- gateway_calls is FORCE ROW LEVEL SECURITY, so the table owner is subject to RLS too. Every
-- existing policy is role-scoped, so an owner-run definer function would match none and see
-- zero rows (silently disabling the ceiling). The policy below admits the migration owner.

DO $$
BEGIN
  -- Bound at migration time to whichever role runs the migration: helixadmin in production
  -- (postgresAdminLogin), helix in the dev container.
  EXECUTE format(
    'CREATE POLICY gateway_calls_owner_read ON gateway_calls FOR SELECT TO %I USING (true)',
    current_user
  );
END $$;

CREATE FUNCTION platform_llm_spend_micro_usd(p_env text)
  RETURNS TABLE (today bigint, hour bigint)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = pg_catalog, public
AS $$
  SELECT
    COALESCE(SUM("costMicroUsd") FILTER (WHERE "createdAt" >= date_trunc('day', now())), 0)::bigint,
    COALESCE(SUM("costMicroUsd") FILTER (WHERE "createdAt" >= now() - interval '1 hour'), 0)::bigint
  FROM public.gateway_calls
  WHERE env = p_env AND capability = 'llm'
    AND "createdAt" >= date_trunc('day', now()) - interval '1 hour'
$$;

REVOKE EXECUTE ON FUNCTION platform_llm_spend_micro_usd(text) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'helix_edge') THEN
    GRANT EXECUTE ON FUNCTION platform_llm_spend_micro_usd(text) TO helix_edge;
  END IF;
END $$;
```

   The two windows copy `PgUsageStore.llmSpendMicroUsd` (`apps/edge/src/gateway/usage.ts:294-317`), including the day boundary (`date_trunc('day', now())`, server-local midnight) and the extra hour on the outer filter so the rolling hour stays correct across midnight. The ceiling and the per-app check must use the same day boundary. `helix_dev` gets no grant: the dev gateway runs without the ceiling. `CREATE POLICY` has no `IF NOT EXISTS`; migrations run once, so that is fine.

   Check the scan is index-assisted: `gateway_calls_createdAt_idx` (`apps/portal/prisma/migrations/20260615214956_gateway_calls_created_at_index/migration.sql`) still exists; the dev-env migration dropped only the `appId` index (`20260722192440_dev_env_partition/migration.sql`). Run `EXPLAIN` on the function body in the dev database and put the plan in `results/`. Do not add the partial index `("createdAt") WHERE capability = 'llm'` now: it is not part of this change and Prisma cannot model it. Write in `results/` that it is the follow-up if volume ever makes the day scan slow.

4. Apply and check: `pnpm --filter @azx-pbc/portal db:deploy` (the test database is migrated by the global setup on the next run). Confirm in `psql` that `\df+ platform_llm_spend_micro_usd` shows `security definer` and the pinned `search_path`, and that `\dp` / `\df` show `EXECUTE` for `helix_edge` only.

5. Tests (integration, real Postgres in the dev container; each skips with the same fail-soft pattern as its neighbours when the runtime roles are missing).

   `apps/edge/src/gateway/usage.rls.integration.test.ts` (it runs as `helix_edge`; its `edgeUrl()` and `edgeRoleAvailable()` helpers are at lines 14-31):
   - As `helix_edge`, `SELECT * FROM platform_llm_spend_micro_usd('prod')` returns the cross-app sum. Seed `llm` rows for two apps through the owner pool or the existing store, and assert on the **difference** from a reading taken before seeding: the test database is truncated only at the start of a run, other suites seed rows concurrently, and the column is cumulative. Assert the delta equals the seeded cost exactly.
   - The result has exactly two columns, `today` and `hour`, and no `appId` column. Assert on `fields`/`Object.keys(row)`.
   - Only `capability = 'llm'` rows count (seed a `fetch` row with a cost and assert the delta ignores it), and only the requested env counts (seed a `dev` row; the `prod` reading ignores it).
   - Regression guard, already present at line 98 ("fails closed: a bare read with no partition GUC sees nothing"): it must stay green. The owner policy is `TO <owner>` and must not widen `helix_edge`.
   - `helix_edge` has no `UPDATE`/`DELETE` on `gateway_calls` (assert the `permission denied` errors).

   `apps/edge/src/registry/role-split.integration.test.ts` (new `describe`, modeled on the `app_visits` block at line 835; reuse `edgeUrl()` (line 21), `egressUrl()` (line 164), `devUrl()` (line 244), `portalUrl()` (line 251) and the `edgeRoleAvailable()`, `egressRoleAvailable()` (line 171), `devRoleAvailable()` (line 270) checks from that file):
   - `helix_edge` can execute the function; `helix_portal` and `helix_egress` get `permission denied for function`; `helix_dev` likewise. For the portal, use `portalUrl()` and `portalRoleAvailable()` (line 258).

   Owner-policy catalog check (put it in `usage.rls.integration.test.ts`, run as the owner via `TEST_DATABASE_URL`): query `pg_proc` (`prosecdef` is true, `proconfig` contains a `search_path` entry, the function owner is `pg_get_userbyid(proowner)`) and `pg_policies` (`tablename = 'gateway_calls'`, `policyname = 'gateway_calls_owner_read'`, `cmd = 'SELECT'`, and the function's owner is in `roles`). A mismatch between the function's owner and the policy's role is the misconfiguration this change must catch. The startup self-test in `09_sp9_platform_daily_ceiling.md` runs the same query at boot, so write it as a small exported SQL string you can reuse there.

   Functional test under a non-bypass owner (the one that catches a missing policy): in `usage.rls.integration.test.ts`, as the superuser owner pool, create a scratch database and a login role `ownerpolicy_probe` with `NOSUPERUSER NOBYPASSRLS` (grant it `CREATE` on `public` in the scratch database; since PostgreSQL 15 `public` is no longer writable by default). Connect to the scratch database **as the probe role**, create a minimal `gateway_calls` table with only the columns the function reads (`"appId" uuid`, `env text`, `capability text`, `"costMicroUsd" bigint`, `"createdAt" timestamp(3) default now()`), run `ENABLE` and `FORCE ROW LEVEL SECURITY` on it, then execute the **exact text of the new migration's `migration.sql`** (read it from disk with `readFileSync`). Insert rows, call the function as `helix_edge` (the grant block runs because the role exists cluster-wide) and assert a non-zero sum. `helix_edge` also needs `GRANT CONNECT ON DATABASE <scratch> TO helix_edge` and `GRANT USAGE ON SCHEMA public TO helix_edge` in the scratch database before it can call anything, and `edgeUrl()` builds the `helix_test` DSN, so the test must swap the database name in the URL. Then drop the policy and assert the same call returns zero: that proves the test would catch the failure. Drop the scratch database and role in `afterAll`, after `end()`ing every pool connected to the scratch database (`DROP DATABASE` fails while a connection is open). If the cluster does not allow `CREATE DATABASE` or `CREATE ROLE` for the test user, skip with an explicit reason, and say in `results/` that the owner policy was verified only through the catalog check.

   Run the whole suite twice in a row: the migration has been applied once and the tests must not depend on a clean table.

6. ADR-0002, `docs/adr/0002-postgres-role-split-rls.md`. Append `## Amendment (<date of the commit>): the platform spend aggregate` (the file's existing amendment, dated 2026-09-21 at line 49, is the format). Record: the function and what it returns; the owner policy and why `FORCE` makes it necessary; that it adds no reach, citing the "Framing (2026-07-21)" paragraph (line 35 of that file: an RCE can already set `app.app_id` and read any app, so an aggregate to that role adds nothing; grant-absence on secrets and the registry is the real boundary); the owner role names (production `helixadmin`, dev `helix`); and that `helix_dev` has no grant. End the amendment with a short paragraph the lease task will extend (`10_sp10_inflight_lease_store.md` adds the `inflight_leases` grants to this same amendment).

7. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met, with the owner-role confirmation recorded in `results/sp8-owner-role.md` and the PR text.
- [ ] The integration tests pass twice in a row; the probe-owner test is green with the policy and red (zero sum) without it, and that red run is saved under `results/`.
- [ ] `./check-and-lint.sh` passes in the dev container (Postgres and Azurite running). Output saved under `results/`.
- [ ] `just dev smoke` passes (the smoke runner migrates its own database, so it proves the migration applies on a fresh stack). Output saved under `results/`.
- [ ] A reviewer other than the author has read the function, the policy and the grants (dedicated review pass). Record who and the notes in `results/`.
- [ ] ADR-0002 amended. Committed with `fest commit -m "SP-8: add the platform LLM spend definer function"`.
- [ ] Unverified in Azure: the production Azure SQL role bootstrap is not exercised. Specifically: that `helixadmin` on Azure Database for PostgreSQL (a member of `azure_pg_admin`, not a superuser) is subject to `FORCE` RLS as assumed and that the owner policy then admits it, and that `CREATE POLICY ... TO helixadmin` and `SECURITY DEFINER` ownership behave the same there as in the dev container. Name this in the PR and in the operator rollout notes (migrate before the edge image; confirm the migration identity's role name matches the policy).