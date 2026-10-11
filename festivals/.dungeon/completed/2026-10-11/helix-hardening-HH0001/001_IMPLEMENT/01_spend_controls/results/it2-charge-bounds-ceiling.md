# Iterate batch IT-2: bounded cut-call charges and a sane ceiling default

Fixes review findings R-2 (a) and (b), the R-2 ADR consequence, and S-15, per the owner's decision in `decisions.md`.

- **R-2 (a).** Every priced model in `packages/shared/src/pricing.ts` now has `contextWindowTokens` and `maxOutputTokens`. `estimateCutUsage` takes the model and the request's `maxTokens`; byte-based estimates are capped at the context window (input) and at `maxTokens`, or the default the provider sends (1024 for Anthropic), bounded by the model's output limit (output). Measured vendor counts are never capped. A 1 MiB hung-up request on a 200,000-token model is now charged at most 200,000 estimated input tokens instead of about 349,000.
- **R-2 (b).** The edge logs `platform_ceiling.below_app_default_multiple` at boot when the ceiling is on and below 3 times `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`. Bicep derives the default ceiling as the larger of a tenth of `platformMonthlyUsdCap` and 3 times `llmDefaultDollarsPerDay` (150 with the defaults); an explicit value and 0 (off) are unchanged. Operator docs updated.
- **R-2 consequence.** ADR-0051 states that any tenant with an LLM grant can pull the shared ceiling as an availability lever, what bounds it now (approval for new grants from IT-3, bounded cut charges, the 3x default), and that per-app fairness was considered and not built.
- **S-15.** `docs/features/llm-gateway.md` and ADR-0051 now state the real overshoot bound (the budget is read before the lease is taken; about one per-app cap's worth of calls) and include the cut-call estimate; the garbled ADR-0051 sentence is fixed.

## Evidence

- `usageEstimate.test.ts` (1 MiB unmeasured input capped at the context window, measured input above the cap kept, huge byte counts capped), `pricing.test.ts` (every priced model has positive limits; fails when a model is added without them).
- Gate: 237 of 237 test files (`it2-gate.txt`). `just infra build` passed. Smoke with `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100`: 31 passed, 0 failed, 1 skipped (`it2-smoke-ceiling-on.txt`).

## Not verified

- The per-model context-window and output limits are taken from the catalog's own comments, not checked against each vendor's current documentation. A limit set lower than the real one only lowers the estimate for a cut call that never received usage; measured counts are unaffected.
- No automated test asserts the boot warning; the condition was reviewed in `apps/edge/src/server.ts:366-376`.
- `ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS` (`pricing.ts`) duplicates `DEFAULT_MAX_TOKENS` in `apps/edge/src/gateway/provider.ts`; both are 1024 today. Follow-up: have the provider import the shared constant.

## Executor

cursor-agent, `composer-2.5`, 82 tool calls.
