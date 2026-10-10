# Iterate batch IT-5: test quality and cleanups

Fixes review findings S-7, S-9, S-10 and three suggestions.

- **S-7.** `apps/egress/src/proxy.test.ts` "never dials the vendor when the client aborts during secret resolution" now aborts while resolution is parked, releases it, and asserts `helix.egress.upstream_aborts` increments, which only happens when the post-resolution dispatch takes SP-2's abort path. Without the `signal` the request runs to completion and the counter does not move.
- **S-9.** Platform-sum tests in `usage.rls.integration.test.ts` assert the delta is at least the inserted amount (with an upper sanity bound) and compare paired deltas for the env filter, so concurrent writers in other files no longer make them flaky; each still fails if the function returns zero or ignores the seeds.
- **S-10.** "single-flights concurrent reads" spies on `Pool.prototype.query`, holds the first platform query until both reads are in flight, and asserts exactly one query. The KP-2 end-to-end test starts its eight hung-up streams concurrently.
- **Suggestions.** The egress pooling test reuses the abandoned call's origin. `apps/portal/prisma/schema.prisma` declares `visibilityGroupIds String[] @default([])`; `prisma migrate diff --from-config-datasource --to-schema` reports "No difference detected", so future `migrate dev` runs stop generating a destructive `DROP DEFAULT`. ADR-0011's sentence moved so it reads correctly.

## Evidence

- Gate: 237 of 237 test files (`it5-gate.txt`). The three changed test files passed 103 of 103 twice in a row. Smoke: 31 passed, 0 failed, 1 skipped (`it5-smoke.txt`).

## Executor

cursor-agent, `composer-2.5`, 77 tool calls.
