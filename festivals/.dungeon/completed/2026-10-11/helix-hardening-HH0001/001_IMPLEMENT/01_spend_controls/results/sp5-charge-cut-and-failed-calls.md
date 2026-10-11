# SP-5 result: charge cut and failed LLM calls

**Result: done.** A cut or failed LLM call now writes a ledger row with a cost, closing the budget bypass (KP-2). In `apps/edge/src/gateway/llm.ts` the handler tracks request bytes, relayed bytes, and the latest measured usage (from SP-4's `usage` events). When a call ends without a final `done` (client hang-up, or a vendor error after the stream started), `recordOnce` charges `estimateCutUsage` (SP-3): measured input else estimated, output the larger of measured and estimated, per decision D4. The row's `stopReason` is `null` and `errorDetail` ends with `;usage=<basis>`; the text before the marker is truncated so the marker survives the 300-character clamp. A vendor 4xx/5xx before any event arrived stays a $0 row. Block-new quota is unchanged: aborts are not quota cuts.

Telemetry: counter `helix.gateway.cut_charges` (dimensions `helix.app_id`, `helix.usage.basis`) and span attribute `helix.usage.basis` on `helix.gateway.llm`. ADR-0021 amended (2026-10-09), and its stale token-denominated wording corrected to USD. `docs/features/llm-gateway.md` and `docs/features/observability.md` updated.

## Evidence

- **Red on main, green after** (`sp5-red-on-main.txt`): with `main`'s `llm.ts`, 5 of 6 tests in "cut and failed calls are charged" fail, including `charges an input-byte estimate and blocks the next call when the budget is tight` (the exploit). The sixth, `does not estimate a vendor rejection before the stream starts`, is a negative test and passes both ways, as it should.
- **Telemetry and redaction with `OTEL_SDK_DISABLED=1`:** `telemetry.test.ts`, `spanRedaction.test.ts`, and `llm.test.ts` all pass (62 tests).
- **Gate:** all 232 test files passed, all steps green (`sp5-gate.txt`).
- **Smoke:** 31 passed, 0 failed, 1 skipped (`sp5-smoke.txt`). The smoke runner does not call the LLM; it shows the edge and egress still boot and proxy. The real-socket tests in `llm.test.ts` are the evidence for the call paths.

## Not covered

- A hang-up after `done` but before the ledger write; the code charges the measured counts from `done` in that case, but no test drives it.
- How close the estimate is to a real vendor bill, and whether vendors send counts in the assumed cadence. Every estimated row is labeled. Nothing Azure-specific.

## Review note for the sequence review

`llm.ts` imports `truncate` from `../auth/identity.js`; a gateway module reaching into the auth module for a string helper is a small coupling worth moving to a shared util.

## Executor

cursor-agent, `composer-2.5`, 108 tool calls.
