# SP-10 result: in-flight lease store and table

**Result: done.** Migration `20261009230444_inflight_leases` creates `inflight_leases (id uuid, scope text, "expiresAt")` with primary key `(id, scope)` and an index on `(scope, "expiresAt")`; `helix_edge` gets `SELECT, INSERT, DELETE` and `helix_portal`'s blanket DML is revoked. `apps/edge/src/gateway/leaseStore.ts` adds `PgLeaseStore` and `InMemoryLeaseStore`. `acquire` takes per-scope advisory transaction locks in sorted scope order (no deadlock), counts live leases per scope, and inserts all rows or none in one transaction; a lease expires at `expiresAt` so a dead replica leaks a slot only until then; `sweep` removes expired rows. Not wired to handlers until SP-11. ADR-0002 amendment extended.

## Evidence

- `leaseStore.integration.test.ts`: 50-way race admits exactly 5; two pools share one cap of 5; [A,B] against [B,A] does not deadlock; expiry and crash simulation; refused acquire leaves no rows. `leaseStore.test.ts` covers the in-memory store. Both files passed twice in a row (17/17 each time).
- `role-split.integration.test.ts`: portal, egress, dev denied; edge SELECT/INSERT/DELETE allowed, UPDATE denied.
- `prisma migrate status`: "Database schema is up to date!" (47 migrations).
- Gate: all 235 test files passed (`sp10-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`sp10-smoke.txt`); the smoke runner migrates a fresh database, so the migration applies cleanly.

## Notes

- `prisma migrate dev` generated an extra `ALTER TABLE apps ALTER COLUMN "visibilityGroupIds" DROP DEFAULT`, because `schema.prisma` does not declare the default the database has. The agent removed it from the migration (verified: the committed SQL has no such line) and restored the default in the local dev database. The schema drift is pre-existing; any future `migrate dev` will try the same drop until `schema.prisma` declares the default. Carried to the sequence review.
- The agent's first gate run failed once in `usage.rls.integration.test.ts`, the SP-8/SP-9 platform-aggregate test: it asserts an exact delta in a sum across all apps while other test files insert LLM rows concurrently. Carried to the sequence's iterate step as a test-design fix.

## Executor

cursor-agent, `composer-2.5`, 55 tool calls.
