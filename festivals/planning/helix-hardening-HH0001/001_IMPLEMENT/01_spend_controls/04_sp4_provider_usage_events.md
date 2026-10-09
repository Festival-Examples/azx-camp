---
fest_type: task
fest_id: 04_sp4_provider_usage_events.md
fest_name: sp4 provider usage events
fest_parent: 01_spend_controls
fest_order: 4
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.33423-06:00
fest_tracking: true
---

# Task: sp4 provider usage events

## Objective

Make the Anthropic and OpenAI stream mappers yield a `usage` event the moment the vendor reports token counts, so a call that is cut later still has whatever counts arrived. Implements SP-4 from 01-spend-controls.md.

## Requirements

- [ ] No prerequisite from an earlier task in this sequence (the design orders it after `03_sp3_cut_stream_usage_estimate.md` only for review order). `05_sp5_charge_cut_and_failed_calls.md` consumes these events.
- [ ] `LlmStreamEvent` (`apps/edge/src/gateway/provider.ts:17-19`) gains `{ type: "usage"; usage: LlmUsage }`.
- [ ] `mapAnthropicStream` yields `usage` at `message_start` and again at a `message_delta` that carries an `output_tokens`: at most twice per call. Each event carries the full accumulated four-field `LlmUsage`, not a delta.
- [ ] `mapOpenAiStream` yields `usage` when the usage chunk is parsed, before the terminal `done`. A stream with no usage block still throws `openai stream ended without a usage block` and yields no `usage` event.
- [ ] `RoutingLlmProvider` and `EgressLlmProvider` forward the new events unchanged (they use `yield*`; confirm with a test, make no code change).
- [ ] `wireCount` still rejects a present-but-invalid count: a `1e999` count throws `LlmProviderError`, and no `usage` event is emitted before that throw. A numeric string count passes and arrives as a number.
- [ ] The gateway handler keeps compiling and behaves exactly as before: the two event loops in `apps/edge/src/gateway/llm.ts` get an explicit branch for the new event that does not touch the ledger totals. Ledger rows are unchanged by this task.
- [ ] Existing whole-array assertions are updated, not loosened: `provider.test.ts:126`, `openaiProvider.test.ts:130`, `egressLlmProvider.test.ts:138`.
- [ ] No new runtime dependency.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-4-provider-usage-events`.

2. Edit `apps/edge/src/gateway/provider.ts`.

   a. The event type (lines 17-19):

```ts
export type LlmStreamEvent =
  | { type: "delta"; text: string }
  /**
   * Token counts the vendor has reported so far, cumulative. Yielded as soon as they
   * are known (Anthropic: at `message_start` and `message_delta`; OpenAI: with the final
   * usage chunk), so a caller that loses the stream still holds them. The terminal
   * `done` carries the final counts.
   */
  | { type: "usage"; usage: LlmUsage }
  | { type: "done"; stopReason: string; usage: LlmUsage };
```

   Update the docblock above `LlmStreamEvent` ("Every provider streams: it yields `delta` events as text arrives and a final `done` event") to mention the `usage` events.

   b. `mapAnthropicStream` (line 98). In `case "message_start":` (line 113), after the four `wireCount` assignments, add:

```ts
        yield {
          type: "usage",
          usage: { inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens },
        };
```

   In `case "message_delta":` (line 134), yield the same object only inside the existing `if (event.usage?.output_tokens != null)` block, after `outputTokens` is updated. A `message_delta` with no usage field changes nothing and yields nothing. Leave `message_stop` and the end-of-body fallback `done` as they are.

   c. `mapOpenAiStream` (line 235). In the `if (event.usage)` block (line 260), after `inputTokens` and `outputTokens` are assigned from `wireCount`, add:

```ts
      yield {
        type: "usage",
        usage: { inputTokens, outputTokens, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 },
      };
```

   The block is inside the `for await` loop, so the event is yielded when the chunk is parsed, before `[DONE]` ends the loop. Do not move the `sawUsage` throw.

   d. Do not edit `wireCount`, `parseSse`, `routingLlmProvider.ts`, or `egressLlmProvider.ts`: the last two forward with `yield*` (`apps/edge/src/gateway/routingLlmProvider.ts:47`, and the `yield* this.#vendor.mapStream(res.body)` in `egressLlmProvider.ts`).

3. Keep the handler compiling and neutral. In `apps/edge/src/gateway/llm.ts` the streaming loop (lines 337-345) and the non-streaming loop (lines 380-386) both end in an `else` that reads `ev.stopReason`; the new variant has no `stopReason`, so typecheck fails without a change. Add an explicit branch before the `else` in both loops:

```ts
          } else if (ev.type === "usage") {
            // Interim counts; `done` carries the final totals and still overwrites finalUsage.
            // Nothing is recorded from an interim event here.
          } else {
            Object.assign(finalUsage, ev.usage);
            finalStopReason = ev.stopReason;
          }
```

   (For the non-streaming loop the shape is `if (ev.type === "delta") content += ev.text; else if (ev.type === "usage") { ... } else { ... }`.) This task does not change what a ledger row contains.

4. Make the fake able to express the new cases. Edit `FakeLlmProvider` in `apps/edge/src/test/fakes.ts` (class at line 152, `stream` at line 170). Today it emits only `delta` events and a final `done`. Add two optional knobs, both off by default so every existing test is unchanged:
   - `earlyUsage?: LlmUsage`: when set, `stream()` yields `{ type: "usage", usage: this.earlyUsage }` before the first delta (the shape of Anthropic's `message_start`).
   - `errorAfterDeltas: Error | null = null`: when set, `stream()` throws it after yielding all deltas instead of yielding `done` (the shape of "upstream returned 200, then the stream broke").

   `05_sp5_charge_cut_and_failed_calls.md` uses both. Add one test in `apps/edge/src/gateway/llm.test.ts` (in `describe("happy paths")`, line 110) that sets `earlyUsage` and asserts a normal streamed call still meters once with the `done` totals, so the interim event provably does not double-count.

5. Update and add tests. In `apps/edge/src/gateway/provider.test.ts`:
   - Line 126, the whole-array `toEqual`: the transcript at lines 22-29 now produces `usage {11, 0}`, `delta Hello`, `delta world`, `usage {11, 4}`, `done`. Write the expected array in full (all four `LlmUsage` fields on each event).
   - Numeric-string test (line 238): additionally assert the first `usage` event has `inputTokens: 11` as a number (`typeof === "number"`).
   - Non-finite test (line 260): collect the events seen before the rejection and assert none is a `usage` event, so an invalid count never leaks out as a usage value.
   - New: a `message_delta` with no `usage` field yields no `usage` event.
   - New: a transcript that ends right after `message_start` and one delta (no `message_stop`) yields the `usage` event before the delta, so a cut stream has the input count.

   In `apps/edge/src/gateway/openaiProvider.test.ts`:
   - Line 130: expected array becomes `delta`, `delta`, `usage {10, 7, 0, 0}`, `done`.
   - New: the stream that has content but no usage block (line 189 region) rejects with `LlmProviderError` and yields no `usage` event.
   - New: `RoutingLlmProvider` forwards a `usage` event unchanged. The existing `Recorder` provider (line 268) yields only `done`; add a second small provider that yields `usage` then `done` and assert the collected events through `routing.stream(...)` equal what the inner provider yielded.

   In `apps/edge/src/gateway/egressLlmProvider.test.ts`:
   - Line 138: the SSE fixture (lines 27-33) yields `usage {10, 0}`, `delta Hello`, `usage {10, 5}`, `done`; write it out in full.

6. Telemetry: this task adds no seam, no instrument and no attribute, so there is nothing to register. Docs: add one sentence to the "Provider seam + streaming" section of `docs/features/llm-gateway.md` (line 48, which says events are `delta` then a final `done`) saying a `usage` event carries interim counts. The fuller description lands with the charging change.

7. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The updated mapper tests assert the new events, including the numeric-string and `1e999` cases, and pass.
- [ ] `./check-and-lint.sh` passes in the dev container (typecheck proves the handler branches are exhaustive). Output saved under `results/`.
- [ ] `just dev smoke` passes (a normal LLM call path still boots and the edge and egress still start). The smoke runner does not call the LLM itself (`grep -i llm .claude/skills/run-helix/smoke.mjs` returns nothing), so the `llm.test.ts` real-socket tests carry the "a normal call still completes" evidence; say that in `results/`.
- [ ] Committed with `fest commit -m "SP-4: yield usage events from the provider mappers"`.
- [ ] Nothing Azure-specific. Not verified here: that the real vendors send `message_start` usage and `message_delta` usage in the cadence the design assumes (one `message_delta` near the end for Anthropic, one usage chunk at the end for OpenAI). The design marks this a hypothesis; the estimate in the next change is built for the worst case.
