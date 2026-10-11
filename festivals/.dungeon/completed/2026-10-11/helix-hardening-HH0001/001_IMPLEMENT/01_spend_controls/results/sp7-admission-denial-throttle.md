# SP-7 result: throttle and count LLM admission denials

**Result: done.** A refused LLM call (app over its daily or rolling-hour budget) now always increments `helix.gateway.admission_denied` (dimensions `helix.app_id`, `helix.capability`, `helix.reason` with values from `ADMISSION_DENIAL_REASONS`) and sets `helix.reason` on the `helix.gateway.llm` span. The `quota_blocked` ledger row is written through the existing `DenialThrottle`, now with an optional scope so LLM and fetch denials use independent buckets; past the per-window cap the ledger row is skipped and a warning logged, while the counter and span still record every refusal. The dev gateway shares one throttle for LLM and fetch.

## Evidence

- `llm.test.ts`: 25 refusals produce exactly 20 `quota_blocked` rows and a counter total of 25; `helix.reason` is `app_budget_day` or `app_budget_burst` on the span.
- `denialThrottle.test.ts`: scoped and unscoped buckets are independent for the same app and env.
- `telemetry.test.ts`: the counter's keys are exactly `helix.app_id`, `helix.capability`, `helix.reason`; reasons bounded; no user oid. Re-run clean with `OTEL_SDK_DISABLED=1` by the agent.
- `spanRedaction.test.ts`: a refused call leaks no prompt, oid, or URL.
- Gate: all 232 test files passed (`sp7-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`sp7-smoke.txt`).

## Notes

The throttle is per edge replica (up to three), so the row cap is per replica, as the throttle's docblock states. Nothing Azure-specific.

## Executor

cursor-agent, `composer-2.5`, 86 tool calls.
