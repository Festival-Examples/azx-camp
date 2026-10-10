# PR #2 review fixes (obey-agent, changes requested)

Two bugs were reported on pull request #2 (LLM spend controls). Both were confirmed against the code before fixing.

## Finding 1: the call deadline never won against the hop timeouts; a silent call that timed out was charged $0

**Confirmed.** `EDGE_LLM_MAX_CALL_MS` defaults to 600000, but the edge-to-egress hop used `EDGE_FETCH_TIMEOUT_MS` (120000) and egress-to-vendor used `EGRESS_TIMEOUT_MS` (120000). A hop timeout with no event seen left `cut` false, so the row was `costMicroUsd: 0`.

**Fix.**
- `packages/shared/src/llmTimeouts.ts`: the two margins and the derived bounds. For an LLM call, the edge-to-egress hop timeout is the deadline plus 60 s. Egress's LLM bound is the deadline plus 120 s, so egress still has a ceiling if the edge dies.
- Edge: `EgressProvider` takes a per-request `hopTimeoutMs`. The LLM provider passes the derived value; non-LLM fetches keep `EDGE_FETCH_TIMEOUT_MS`.
- Egress: a separate dispatcher for `llm` instructions, bounded by `EGRESS_LLM_TIMEOUT_MS` (default derived from the deadline). Proxied fetches keep `EGRESS_TIMEOUT_MS`. An upstream idle timeout is reported to the edge as 502 `upstream_timeout`.
- `llm.ts`: `llmErrorCharge` decides the charge on both paths. A hop idle timeout (`UND_ERR_HEADERS_TIMEOUT`, `UND_ERR_BODY_TIMEOUT`) or egress's `upstream_timeout` is a cut with `errorDetail` `upstream_timeout`. A vendor 400, 429 or 500 before any byte stays $0.
- `infra/azure/main.bicep`: `EGRESS_LLM_TIMEOUT_MS` is `llmMaxCallMs + 120000`, so the two settings cannot drift.
- Docs: ADR-0051, `docs/features/llm-gateway.md`, `configuration.md` and the spend section of `updates.md`.

## Finding 2: the cut-call output estimate was clamped below what the vendor request allows for reasoning models

**Confirmed.** `outputTokenCapForEstimate` returned `min(maxTokens, maxOutputTokens)` when `maxTokens` was set, while the request builder sends `max_completion_tokens = max(maxTokens ?? floor, floor)`.

**Fix.** For reasoning models the cap is `min(max(maxTokens ?? floor, floor), maxOutputTokens)`. The floor constant (`REASONING_MIN_COMPLETION_TOKENS_DEFAULT`) now lives in `pricing.ts` and is shared with `provider.ts`, which removes the duplicate recorded as a sequence 01 follow-up.

## Coordinator corrections to the executor's work

- **Reverted: billing the full reasoning floor when nothing was relayed.** The executor changed `estimateCutUsage` so that a reasoning call cut with zero relayed bytes is charged the whole output floor (25,000 tokens), on every cut path. Neither finding asked for this. It would let an instant client hang-up record a full completion budget per call, counted toward the shared platform ceiling. That is the amplification sequence 01's review (R-2) fixed by bounding cut charges. `usageEstimate.ts` is unchanged from the reviewed commit. A cut with nothing relayed is charged its input estimate; the output estimate follows relayed bytes, up to the corrected cap.
- **Connect timeouts are not charged.** The executor counted `UND_ERR_CONNECT_TIMEOUT` as a chargeable timeout on both hops. A connect timeout means the request never left, so it is removed from both sets, and a test pins the $0.
- **The LLM dispatcher's connect budget stays at the normal bound.** The executor passed the 12-minute LLM bound to the validating connector as its connect timeout. It now uses `EGRESS_TIMEOUT_MS`; only the wait after the request is sent gets the longer bound.

## Residual, stated plainly

A reasoning call that stays silent until the deadline or a hop timeout is charged its input estimate only. The vendor may also bill reasoning tokens generated before the abort; with no bytes and no usage block, there is nothing to measure them from. Charging a floor for deadline and timeout cuts only (not client hang-ups) is a possible follow-up and would be an owner decision.

## Evidence (coordinator)

- Focused suites (`usageEstimate`, `pricing`, `llmTimeouts`, gateway `llm`, egress `proxy`): 133 of 133.
- Revert checks: without the cap fix 3 tests fail, including the gateway test of a cut reasoning call with `maxTokens: 1`; without the timeout charge 3 tests fail. Both files were restored.
- `./check-and-lint.sh`: 238 of 238 test files, 3332 tests. `just infra build` passes.
- Real-browser smoke: 34 of 34. Connections lane: 10 of 10 (`pr2-review-fixes-gate.txt`).

## Unverified in Azure

That Container Apps passes `EGRESS_LLM_TIMEOUT_MS` through, and real vendor behavior on a 10-minute silent call.

## Executor

cursor-agent, `composer-2.5`. Coordinator corrections as listed.
