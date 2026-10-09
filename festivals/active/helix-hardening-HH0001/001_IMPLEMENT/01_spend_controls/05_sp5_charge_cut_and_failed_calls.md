---
fest_type: task
fest_id: 05_sp5_charge_cut_and_failed_calls.md
fest_name: sp5 charge cut and failed calls
fest_parent: 01_spend_controls
fest_order: 5
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.334848-06:00
fest_updated: 2026-10-09T15:41:12.347902-06:00
fest_tracking: true
---


# Task: sp5 charge cut and failed calls

## Objective

Make a client hang-up, or an error after the upstream answered 200, write a ledger row that charges what the vendor most likely billed, marked as measured, estimated or mixed, so the daily spend gate sees abandoned calls. Implements SP-5 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `03_sp3_cut_stream_usage_estimate.md` (`estimateCutUsage`, `CUT_CHARGE_BASES`, `BYTES_PER_TOKEN`) and `04_sp4_provider_usage_events.md` (the `usage` event, `FakeLlmProvider.earlyUsage` and `errorAfterDeltas`).
- [ ] A client hang-up writes a row with `outcome: "error"`, `errorDetail` ending `;usage=measured`, `;usage=estimated` or `;usage=mixed` (for a hang-up the text before it is `client_disconnected`), `costMicroUsd > 0`, and `stopReason` null (not the false default `end_turn`).
- [ ] An error after an upstream 200 with at least one event received (a `delta` or a `usage`) is charged the same way, with the upstream error text before the marker.
- [ ] An upstream 4xx or 5xx before the stream starts (no event received) is not estimated: cost stays 0 and `errorDetail` carries no `;usage=` marker. This keeps today's behavior for a vendor rejection.
- [ ] Per field: input is the measured count if any usage event or `done` delivered one, else the byte estimate; output is `max(measured, estimate)`. The cost uses the same `costUsd` rate table as today.
- [ ] The marker survives the ledger column cap. `ERROR_DETAIL_MAX` is 300 (`apps/edge/src/gateway/usage.ts:90`) and `clampRecord` (line 214) truncates with an ellipsis, so the text before the marker is cut first. A 1,000-character upstream error still yields a row that ends `;usage=...` and is at most 300 characters.
- [ ] After a charged cut, the daily gate refuses the next request when the estimate crosses the budget (the exploit: open a stream, hang up before any delta, repeat).
- [ ] The non-streaming path behaves the same as the streaming one.
- [ ] A normal completion is unchanged: no marker, real `stopReason`, totals from `done`.
- [ ] The block-new rule is unchanged. The ADR-0021 amendment says that a client hang-up or a wall-clock deadline abort is not a quota cut, so "an in-flight request is never cut by the budget" still holds.
- [ ] Telemetry ships with it: counter `helix.gateway.cut_charges` (`helix.app_id`, `helix.usage.basis`), span attribute `helix.usage.basis` on the `helix.gateway.llm` span. No `userOid`, URL, prompt text or lease/scope string appears in any attribute.
- [ ] Failure paths from the design. If the ledger write fails, `recordOnce` swallows and logs `gateway.usage_record_failed` as today: the row is lost, the estimate makes nothing worse. A mapper throw mid-`usage` leaves earlier counts in place. An edge crash mid-stream writes no row (documented residual). Reasoning tokens that are billed and never streamed are not covered (documented residual).

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-5-charge-cut-and-failed-calls`.

2. Shared telemetry names. In `packages/shared/src/telemetry.ts` add, in the instrument block (after line 40, `INSTR_APP_VISITS`) and the attribute block (after `ATTR_CLIENT_DISCONNECTED`, line 62):

```ts
export const INSTR_GATEWAY_CUT_CHARGES = "helix.gateway.cut_charges";
export const ATTR_USAGE_BASIS = "helix.usage.basis";
```

   `CUT_CHARGE_BASES` already exists from the SP-3 task; do not add it again. Before adding, `grep -n "cut_charges\|usage.basis" -r packages apps docs` to confirm the names are free (the festival rules ask you to check names against earlier tasks). `packages/shared/src/telemetry.test.ts` pins the regexes and uniqueness.

3. Edge instrument. In `apps/edge/src/telemetry.ts`: import `INSTR_GATEWAY_CUT_CHARGES`; add `gatewayCutCharges: Counter;` to `EdgeInstruments` (interface at line 46; document the dimensions: `appId`, `basis` in `CUT_CHARGE_BASES`; operational only, never reconciled with the ledger, ADR-0037 decision 9); create it in `instruments()` after `appVisits` (line 126):

```ts
    gatewayCutCharges: meter.createCounter(INSTR_GATEWAY_CUT_CHARGES, {
      description:
        "LLM calls charged without a final usage block, by how the charge was derived. Operational only; never reconciled with the ledger.",
    }),
```

4. Metering helper. In `apps/edge/src/gateway/usage.ts`: export `ERROR_DETAIL_MAX` (line 90, currently module-private); import `ATTR_USAGE_BASIS`, `type CutChargeBasis` from `@azx-pbc/shared/telemetry`; and add next to `meterGatewayCall` (line 418), following its doc style (beside the ledger write, never inside `record`):

```ts
export function meterCutCharge(call: { appId: string; basis: CutChargeBasis }): void {
  instruments().gatewayCutCharges.add(1, {
    [ATTR_APP_ID]: call.appId,
    [ATTR_USAGE_BASIS]: call.basis,
  });
}
```

5. The handler, `apps/edge/src/gateway/llm.ts`.

   a. Imports: add `estimateCutUsage` to the `@azx-pbc/shared` import (lines 3-9); `ATTR_USAGE_BASIS` to the `@azx-pbc/shared/telemetry` import (lines 20-26); `ERROR_DETAIL_MAX` and `meterCutCharge` to the `./usage.js` import (line 18); and `import { truncate } from "../auth/identity.js";` (`truncate` is defined in `apps/edge/src/auth/identity.ts:38`).

   b. State, declared with `finalUsage` (lines 245-253). `Buffer` is available in the edge:

```ts
    // What a cut call is charged from, when the vendor never sent `done`.
    const requestBytes =
      Buffer.byteLength(chat.system ?? "", "utf8") +
      chat.messages.reduce((n, m) => n + Buffer.byteLength(m.content, "utf8"), 0);
    let relayedBytes = 0;
    let measured: LlmUsage | undefined;
    let eventsSeen = 0;
```

   c. `recordOnce` (lines 254-299). Extend the second parameter to `extra: { errorDetail?: string; cut?: boolean }` and, before the cost line (268), apply the estimate:

```ts
      let stopReason: string | null = finalStopReason;
      let errorDetail = extra.errorDetail ?? null;
      if (extra.cut) {
        const estimate = estimateCutUsage({ measured, requestBytes, relayedBytes });
        Object.assign(finalUsage, estimate.usage);
        // The default "end_turn" is false for a call that never finished.
        stopReason = null;
        // The marker goes LAST and the text before it is cut to fit: clampRecord truncates
        // errorDetail at ERROR_DETAIL_MAX and would otherwise drop the marker.
        const marker = `;usage=${estimate.basis}`;
        errorDetail = truncate(extra.errorDetail ?? "", ERROR_DETAIL_MAX - marker.length - 1) + marker;
        meterCutCharge({ appId: entry.appId, basis: estimate.basis });
        trace.getActiveSpan()?.setAttribute(ATTR_USAGE_BASIS, estimate.basis);
      }
```

   Then use `stopReason` and `errorDetail` in the `usage.record({...})` call in place of `finalStopReason` (line 284) and `extra.errorDetail ?? null` (line 285). `truncate` appends an ellipsis only when it cuts, so the result is at most `ERROR_DETAIL_MAX` characters.

   d. The loops. Replace the SP-4 no-op branch in both loops (streaming, lines 337-345; non-streaming, lines 380-386) so they track the call:

```ts
          if (ev.type === "delta") {
            eventsSeen += 1;
            relayedBytes += Buffer.byteLength(ev.text, "utf8");
            start();
            codec.writeDelta(reply, ctx, ev.text);
          } else if (ev.type === "usage") {
            eventsSeen += 1;
            measured = ev.usage;
          } else {
            measured = ev.usage; // the final counts are measured too
            Object.assign(finalUsage, ev.usage);
            finalStopReason = ev.stopReason;
          }
```

   (Non-streaming: same bookkeeping, `content += ev.text` for the delta.) Setting `measured` on `done` matters: a hang-up after `done` but before the row is written must charge the real counts, and `estimateCutUsage` then reports `measured`.

   e. The decision, in the two `catch` blocks (streaming line 350, non-streaming line 393):

```ts
      if (clientGone) {
        await recordOnce("error", { errorDetail: CLIENT_DISCONNECTED, cut: true });
        return;
      }
      // Charged only if the upstream answered 200 and something arrived. A vendor 4xx/5xx
      // before the stream started generated nothing, so it stays a $0 error row.
      await recordOnce("error", { errorDetail: errorDetailOf(err), cut: eventsSeen > 0 });
```

   Keep the existing comments about why `clientGone` returns without a response. Add one sentence to the "Quota ... block-new" comment (line 183) and to the module docblock (the paragraph at line 37, "Quota is **block-new, finish-in-flight**"): an abort by the client, or by the call deadline, is not a quota cut; the budget never cuts an admitted call.

   f. The `usage.record({...})` call keeps `outcome` as passed. Do not add a `cancelled` outcome: `GatewayOutcome` is a shared enum with the portal and the DB (see the comment on `CLIENT_DISCONNECTED`, line 63).

6. Test fakes. `FakeUsageStore` (`apps/edge/src/test/fakes.ts:202`) already sums live; no change. Use the `FakeLlmProvider` knobs added by the SP-4 task.

7. Tests in `apps/edge/src/gateway/llm.test.ts` (new `describe("cut and failed calls are charged")` plus edits):
   - Extend the real-socket hang-up test (lines 577-607): the row has `outcome: "error"`, `errorDetail` matching `/^client_disconnected;usage=(measured|estimated|mixed)$/`, `costMicroUsd > 0`, `stopReason` null. Do the same for the non-streaming test (line 609), which asserts nothing about the row today.
   - The exploit. Compute the expected charge for `ASK` plus a `system` of 3,000 `x` characters: `ceil(3002 / BYTES_PER_TOKEN)` input tokens through `costUsd` (both exported from `@azx-pbc/shared`). Build the edge with `dollarsPerDay` set just below that figure in dollars. Hang up before any delta (make `provider.onDelta` wait on a promise for index 0, abort the client, then release). Assert the row charges the input estimate with `;usage=estimated`; then send a second request and assert it is `429 quota_exceeded` and a `quota_blocked` row is written. This is the test that proves the gate moves.
   - Measured wins where exact: `provider.earlyUsage = { inputTokens: 1200, outputTokens: 0, ... }`, a hang-up after the first delta: the row's `inputTokens` is exactly 1200 and `outputTokens` is the byte estimate of what was relayed; marker `;usage=mixed`.
   - OpenAI shape: `provider.errorAfterDeltas = new LlmProviderError("openai stream ended without a usage block")` with a few deltas, streaming: the row is charged, `outcome: "error"`, `errorDetail` starts with that text and ends `;usage=estimated`, and the client still gets the in-band error frame (existing behavior).
   - No estimate on a vendor rejection: `provider.error = new LlmProviderError("x", 429)`, then 400, then 500: each row has `costMicroUsd` 0 and no `;usage=` in `errorDetail`.
   - Marker survives truncation: `errorAfterDeltas` with a 1,000-character message: the stored `errorDetail` is at most 300 characters and ends with `;usage=estimated`.
   - Hang-up after `done`: `done` was received, then the socket drops before the row is written. If this is hard to time, cover it by calling the handler with a `codec` that throws in `writeDone` while `clientGone` is true; if neither is practical, say so in `results/` rather than skip silently.
   - Normal completion: a `done`-terminated call has no marker and `stopReason` "end_turn" (the existing happy-path tests already assert the row).

8. Telemetry tests (same change):
   - `apps/edge/src/gateway/telemetry.test.ts`: with `startRecordingTelemetry`, call `meterCutCharge` and assert the data point for `INSTR_GATEWAY_CUT_CHARGES` has exactly `helix.app_id` and `helix.usage.basis` as attribute keys, no user identifier, and that each `CUT_CHARGE_BASES` value is accepted. Follow the existing cases at the top of that file.
   - `apps/edge/src/spanRedaction.test.ts`: add a case that drives a cut call (use `errorAfterDeltas` with `app.inject()`, as the app-data cases at line 147 drive a gateway route) with a planted prompt fragment in `messages[].content` and a planted `userOid`, then scans every recorded span attribute and metric attribute: no value contains the prompt fragment, the oid, a URL or a scope string, and `helix.usage.basis` is present with an allowed value.
   - Re-run the new tests with `OTEL_SDK_DISABLED=1` and confirm they still pass.

9. Docs.
   - `docs/features/observability.md`: add `helix.gateway.cut_charges | counter | appId, basis (measured / estimated / mixed; operational only, never reconciled with the ledger. Alert on a high share of estimated: it means the vendor is not delivering counts)` to the instrument table (line 185); add a `helix.usage.basis` bullet to the span-attribute notes for `helix.gateway.llm`.
   - `docs/features/llm-gateway.md`: in "Metering" (line 88) add the cut-call rows: `outcome: error`, the `;usage=` marker, `stopReason` null, the rule per field, and the stated residuals (non-streamed reasoning tokens, an edge crash mid-stream write no row). Change "Calls that never reach the provider record selectively" only if it becomes untrue.
   - `docs/adr/0021-metering-ledger.md`: add `## Amendment (<date of the commit>): cut and failed calls are charged`. State (1) a frozen `costMicroUsd` may be an estimate for a call that ended without a final usage block, and the row says so; (2) the Decision's wording is stale: edit the first Decision bullet ("Daily budgets are token/request-denominated") and the Consequences bullet that calls dollars a derived view so both say budgets are USD-denominated, and note that in the amendment; (3) block-new is unchanged, and an abort by the client or the wall-clock deadline is not a quota cut. Append-only is unchanged.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The exploit test is red before the change (a hang-up charges $0 and the next request is admitted) and green after. Save the red run in `results/`.
- [ ] The telemetry tests and the redaction scan pass, and pass again with `OTEL_SDK_DISABLED=1`.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes. The smoke runner does not call the LLM, so it proves the edge and egress still boot and proxy; the `llm.test.ts` real-socket tests are the evidence for the call paths. Say so in `results/`.
- [ ] ADR-0021 amended; `docs/features/observability.md` and `docs/features/llm-gateway.md` updated.
- [ ] Committed with `fest commit -m "SP-5: charge cut and failed LLM calls"`.
- [ ] Not verifiable here: how close the estimate is to what a real vendor bills (the heuristic is labeled an estimate in every row), and whether real vendors deliver counts in the assumed cadence. Nothing Azure-specific.