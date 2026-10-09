---
fest_type: task
fest_id: 03_sp3_cut_stream_usage_estimate.md
fest_name: sp3 cut stream usage estimate
fest_parent: 01_spend_controls
fest_order: 3
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.333874-06:00
fest_updated: 2026-10-09T15:15:10.33359-06:00
fest_tracking: true
---


# Task: sp3 cut stream usage estimate

## Objective

Add one pure function in `packages/shared` that estimates what a cut or failed LLM call cost, from measured token counts where the vendor delivered them and byte counts where it did not. Implements SP-3 from 01-spend-controls.md.

## Requirements

- [ ] No prerequisite from an earlier task in this sequence. The function is not called by any handler yet; `05_sp5_charge_cut_and_failed_calls.md` wires it in.
- [ ] `BYTES_PER_TOKEN` is an exported named constant, value `3` (the owner's starting value; a guess until real traffic exists, so it must be a single place to change).
- [ ] `estimateCutUsage({ measured, requestBytes, relayedBytes })` returns the token counts to charge and a `basis`:
  - input tokens = the measured input count when a usage event delivered one, else `ceil(requestBytes / BYTES_PER_TOKEN)`;
  - output tokens = `max(measured output, ceil(relayedBytes / BYTES_PER_TOKEN))`. Max, not replace: the vendor bills output generated up to the cancel, which is more than what streamed through, and a measured count can lag (Anthropic reports about one output token at `message_start`);
  - cache read and cache creation counts come from `measured` when present, else 0;
  - `basis` is `measured` when both fields came from the measurement, `estimated` when both came from bytes, `mixed` otherwise.
- [ ] Failure paths. The function never returns a negative number, `NaN`, or `Infinity`, whatever the inputs: zero bytes, multibyte text, a huge input, a negative or non-finite byte count (treated as 0), a fractional byte count. Results are safe integers; a result that would exceed `Number.MAX_SAFE_INTEGER` is clamped.
- [ ] The estimate has no dependency on `Buffer`: `packages/shared` is re-exported from the browser-facing barrel (`packages/shared/src/index.ts`), so the caller computes byte lengths and passes numbers.
- [ ] `CUT_CHARGE_BASES` (the allowed `basis` values) is defined in `packages/shared/src/telemetry.ts`. The design lists this constant under the change that adds the counter (`05_sp5_charge_cut_and_failed_calls.md`), but the estimate's return type needs it now, so it moves here. The SP-5 task must not add it again.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-3-cut-stream-estimate`.

2. Add the basis vocabulary to `packages/shared/src/telemetry.ts`, next to the other bounded vocabularies (for example after `PROVIDERS_RECONCILE_OUTCOMES`, line 254). Follow their shape (a `const` tuple, then the derived type):

```ts
/**
 * How a cut or failed LLM call's charge was derived: the `helix.usage.basis` span
 * attribute and the `helix.gateway.cut_charges` dimension. `measured`: both counts
 * came from the vendor's usage block. `estimated`: both came from byte counts.
 * `mixed`: one of each (for example a measured input and an estimated output).
 */
export const CUT_CHARGE_BASES = ["measured", "estimated", "mixed"] as const;
export type CutChargeBasis = (typeof CUT_CHARGE_BASES)[number];
```

3. Create `packages/shared/src/usageEstimate.ts`. `LlmUsage` is defined in `packages/shared/src/llm.ts` (`LlmUsageSchema`, lines 28-33, type at line 34). `telemetry.ts` imports nothing, so importing its type here creates no cycle.

```ts
import type { LlmUsage } from "./llm.js";
import type { CutChargeBasis } from "./telemetry.js";

/**
 * Bytes per token used when a call ends without a vendor usage count. English averages
 * about 4; 3 over-counts it, which is the safe direction for a budget gate. A heuristic,
 * wrong by tens of percent for non-Latin text, code, or reasoning models whose hidden
 * tokens are billed and never streamed. Tune here.
 */
export const BYTES_PER_TOKEN = 3;

export interface CutUsageEstimate {
  usage: LlmUsage;
  basis: CutChargeBasis;
}

function tokensFromBytes(bytes: number): number {
  if (!Number.isFinite(bytes) || bytes <= 0) return 0;
  return Math.min(Math.ceil(bytes / BYTES_PER_TOKEN), Number.MAX_SAFE_INTEGER);
}

export function estimateCutUsage(input: {
  /** The last usage event the provider delivered, or undefined if none arrived. */
  measured: LlmUsage | undefined;
  /** UTF-8 length of the system prompt plus every message's content. */
  requestBytes: number;
  /** Sum of the UTF-8 length of every text delta relayed to the app. */
  relayedBytes: number;
}): CutUsageEstimate {
  const { measured } = input;
  const estimatedOutput = tokensFromBytes(input.relayedBytes);
  const inputTokens = measured ? measured.inputTokens : tokensFromBytes(input.requestBytes);
  const outputTokens = Math.max(measured?.outputTokens ?? 0, estimatedOutput);

  const inputMeasured = measured !== undefined;
  const outputMeasured = measured !== undefined && measured.outputTokens >= estimatedOutput;
  const basis: CutChargeBasis =
    inputMeasured && outputMeasured
      ? "measured"
      : !inputMeasured && !outputMeasured
        ? "estimated"
        : "mixed";

  return {
    usage: {
      inputTokens,
      outputTokens,
      cacheReadInputTokens: measured?.cacheReadInputTokens ?? 0,
      cacheCreationInputTokens: measured?.cacheCreationInputTokens ?? 0,
    },
    basis,
  };
}
```

   Check the edge cases against the sketch before relying on it. With `measured` present at `outputTokens: 0` and no bytes relayed, `outputMeasured` is true (0 >= 0) and the basis is `measured`, which is accurate: the vendor said zero so far. With `measured` absent and `relayedBytes` 0, the output is estimated at 0 and the basis is `estimated`. Do not change these semantics without writing the reason in a comment.

4. Export from the barrel: add `export * from "./usageEstimate.js";` to `packages/shared/src/index.ts` (the existing line exports are `llm`, `llmOpenai`, `pricing`, `usage` at lines 16-19). `packages/shared/src/telemetry.ts` stays on its own subpath (`packages/shared/package.json` exports `./telemetry`), as it is today.

5. Add `packages/shared/src/usageEstimate.test.ts`, in the style of `packages/shared/src/pricing.test.ts`. Cases and what each asserts:
   - zero bytes and no measurement: both counts 0, basis `estimated`;
   - 9 request bytes and 9 relayed bytes, no measurement: 3 input, 3 output, basis `estimated` (pins `ceil` and the divisor);
   - measured input 1200 and 3 relayed bytes: input is exactly 1200 (not the byte estimate), output is `max(measured, estimate)`;
   - measured output larger than the byte estimate: output is the measured one and basis is `measured`;
   - measured output smaller than the byte estimate (Anthropic's lagging count): output is the estimate and basis is `mixed`;
   - multibyte text: pass the byte count of a string such as `"héllo 日本語"` computed with `new TextEncoder().encode(s).length` and assert the result equals `ceil(bytes / BYTES_PER_TOKEN)`;
   - huge input (`Number.MAX_SAFE_INTEGER`, `Number.MAX_VALUE`): no overflow, the result is a safe integer;
   - `-5`, `NaN`, `Infinity`, `-Infinity` bytes: treated as 0, never negative, never `NaN`;
   - fractional bytes (`10.4`): `ceil` of the division, still an integer;
   - cache counts: carried from `measured`, 0 otherwise;
   - the returned `basis` is always a member of `CUT_CHARGE_BASES`.

   In `packages/shared/src/telemetry.test.ts`, add a short case that `CUT_CHARGE_BASES` equals `["measured", "estimated", "mixed"]`, the way that file pins `SESSION_DENIAL_REASONS` (imported at its top).

6. No handler, edge, or egress change, so no instrument and no docs row yet. The constant is documented by its docblock; the observability inventory row for `helix.gateway.cut_charges` lands with the instrument in `05_sp5_charge_cut_and_failed_calls.md`.

7. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths: other readers cannot resolve them.

## Done When

- [ ] All requirements met.
- [ ] `usageEstimate.test.ts` passes, including the non-finite and overflow cases.
- [ ] Typecheck shows no new error in any package that imports `@azx-pbc/shared` (the barrel is browser-consumed, so the portal SPA must still build; the typecheck and docs steps of the gate cover it).
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` is not required: nothing calls the function yet and no running service changes.
- [ ] Committed with `fest commit -m "SP-3: add the cut-stream usage estimate"`.
- [ ] Nothing Azure-specific. The accuracy of `BYTES_PER_TOKEN = 3` against real vendors is not tested here; it is a guess until an install shows its traffic.