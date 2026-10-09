# SP-3 result: cut-stream usage estimate

**Result: done.** `packages/shared/src/usageEstimate.ts` adds `estimateCutUsage({ measured, requestBytes, relayedBytes })` and `BYTES_PER_TOKEN = 3`. Input tokens are the measured count when the provider sent one, otherwise the request bytes divided by `BYTES_PER_TOKEN`. Output tokens are the larger of the measured count and the relayed bytes divided by `BYTES_PER_TOKEN`. The result carries a basis, `measured`, `estimated`, or `mixed`, from the new `CUT_CHARGE_BASES` in `packages/shared/src/telemetry.ts`. This follows decision D4. Nothing calls it until SP-5.

## Evidence

- `usageEstimate.test.ts` covers zero bytes, measured vs estimated input and output, the `mixed` basis, multibyte UTF-8, `MAX_SAFE_INTEGER` and `MAX_VALUE` clamping, non-finite and negative inputs, fractional bytes, and that every basis is in `CUT_CHARGE_BASES`. `telemetry.test.ts` pins the basis tuple.
- Gate (`sp3-gate.txt`): typecheck, lint, refs, format, and docs pass, so the browser-consumed barrel still builds for the SPA. Tests: 231 of 232 files passed. The one failure, `apps/portal/src/routes/approvals.test.ts` > "concurrent decisions on one approval request", is a concurrency test in code this change does not touch; rerun alone it passed twice (38/38). Recorded as a load flake, like the SP-2 ones.
- The agent's own final gate run passed all 232 files.
- Smoke not required: no running service changes.

## Unverified

`BYTES_PER_TOKEN = 3` against real vendor traffic; it is a guess until an install shows its traffic.

## Executor

cursor-agent, `composer-2.5`, 26 tool calls.
