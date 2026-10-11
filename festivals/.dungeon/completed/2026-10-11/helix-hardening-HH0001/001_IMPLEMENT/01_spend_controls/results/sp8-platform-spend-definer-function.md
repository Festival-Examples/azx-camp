# SP-8 result: platform LLM spend definer function

**Result: done.** Migration `20261009223800_platform_llm_spend_definer` adds `platform_llm_spend_micro_usd(p_env)` (a `SECURITY DEFINER` aggregate returning today's and the last hour's LLM spend across all apps for one env), the owner `SELECT` policy it needs under `FORCE ROW LEVEL SECURITY`, and `EXECUTE` for `helix_edge` only. `apps/edge/src/gateway/platformSpendDefinerCheck.ts` holds the catalog SQL SP-9's startup self-check will use. ADR-0002 amended (2026-10-09). The edge does not call the function until SP-9.

## Evidence

- Owner role confirmed: `sp8-owner-role.md`.
- Integration tests (`usage.rls.integration.test.ts`, `role-split.integration.test.ts`): cross-app sum through the function, only `today` and `hour` columns, `llm` and env filtering, catalog check, owner-policy probe (non-zero with the policy, zero without: `sp8-owner-policy-probe-without-policy.txt`), grant matrix, and `helix_edge` still denied `UPDATE` and `DELETE`. Passed in the agent's two consecutive runs and in the coordinator's gate run.
- Query plan: `sp8-explain.txt`.
- Gate: all 232 test files passed (`sp8-gate.txt`; the agent's own run in `sp8-agent-gate.log`).
- Smoke: 31 passed, 0 failed, 1 skipped (`sp8-smoke.txt`); the smoke runner migrates a fresh database, so the migration applies cleanly.
- Dedicated review: `sp8-review.md`.

## Unverified in Azure

That `helixadmin` on Azure Database for PostgreSQL (a member of `azure_pg_admin`, not a superuser) is subject to `FORCE` RLS and that the owner policy and definer ownership behave as they do in the dev container.

## Housekeeping

The agent wrote its results into a `results/` directory at the repository root; they were moved here before commit.

## Executor

cursor-agent, `composer-2.5`, 48 tool calls.
