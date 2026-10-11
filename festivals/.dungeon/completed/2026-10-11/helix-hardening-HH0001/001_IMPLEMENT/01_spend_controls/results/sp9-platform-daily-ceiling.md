# SP-9 result: platform-wide daily LLM ceiling

**Result: done.** When `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY` is positive, the edge refuses new LLM calls with 503 and a `retry-after` until local midnight once the day's LLM spend across all apps reaches it. The spend comes from SP-8's `platform_llm_spend_micro_usd`, cached briefly with single-flight reads (`apps/edge/src/gateway/usage.ts`). A failed read refuses the call (503, `retry-after: 5`): the ceiling fails closed. An app over its own budget still gets 429 before the platform check. Refusals reuse SP-7's counter and throttle with the new reason `platform_ceiling`; cut calls (SP-5) count toward the sum. A gauge `helix.gateway.platform_spend_ratio` (dimension `helix.env`) reports spend against the ceiling, and `infra/azure/modules/alerts.bicep` adds an alert rule on it.

**Startup check.** With the ceiling on, the edge checks the function at boot (`checkPlatformSpendFunction`): it inspects the catalog (definer, pinned `search_path`, owner policy) and calls the function. A missing function, a non-definer, a bad owner policy, or a missing `EXECUTE` grant (Postgres 42501) is "misconfigured" and the edge refuses to start. An unreachable database at boot logs a warning, and per-call reads fail closed. This closes the SP-8 review's medium follow-up (a silently skipped grant).

**Defaults.** Bicep `llmPlatformDollarsPerDay` defaults to -1, which derives one tenth of `platformMonthlyUsdCap` ($100 a day on the $1,000 default, and $100 when the watch line is 0); 0 switches it off. The edge's own default is 0 (off), so an install deployed without the template must set it; the design called for "enabled by default in Bicep", which this matches.

## Evidence

- Tests: `llm.test.ts` (503 at the ceiling with `retry-after`, below the ceiling served, 0 off, app 429 before platform 503, throttled rows, read error 503, cut calls counted, `secondsUntilNextLocalMidnight`), `usage.platformSpendCheck.test.ts` (classifier cases), `usage.rls.integration.test.ts` (cross-app sum, cache TTL, single-flight, self-test ok), `telemetry.test.ts`, `spanRedaction.test.ts`, `config.test.ts`.
- Gate: all 233 test files passed (`sp9-gate.txt`). `just infra build` passed (`sp9-infra-build.txt`).
- Smoke: 31 passed, 0 failed, 1 skipped with the ceiling off (`sp9-smoke.txt`) and with `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100` (`sp9-smoke-ceiling-on.txt`), which shows the startup check passes against a freshly migrated database. The smoke runner does not call the LLM; refusal behavior is covered by the tests above.

## Unverified

- In Azure: the Bicep parameter reaching the edge, the alert's KQL, and the production owner role under `FORCE` RLS (from SP-8).
- `retry-after` is computed to the edge's local midnight while the database's day boundary follows the database's time zone; they agree only if both run in the same zone. No daylight-saving transition test.

## Executor

cursor-agent, `composer-2.5`, 145 tool calls.
