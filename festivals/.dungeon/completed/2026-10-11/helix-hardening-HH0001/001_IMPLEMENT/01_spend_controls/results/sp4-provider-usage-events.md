# SP-4 result: usage events from the provider mappers

**Result: done.** `LlmStreamEvent` gains `{ type: "usage"; usage }`, cumulative token counts yielded as soon as the vendor reports them: Anthropic at `message_start` and at each `message_delta` with `output_tokens`, OpenAI with its final usage chunk. `RoutingLlmProvider` forwards them unchanged. The LLM handler (`apps/edge/src/gateway/llm.ts`) has explicit `usage` branches in both the streaming and non-streaming loops that record nothing yet; the final `done` event still sets the ledger totals. SP-5 uses the interim counts to charge cut streams.

## Evidence

- Mapper tests (`provider.test.ts`, `openaiProvider.test.ts`, `egressLlmProvider.test.ts`) assert the new events, including a numeric-string count, `1e999` and invalid counts (rejected, no `usage` emitted), a `message_delta` without usage, a stream cut after `message_start`, and the OpenAI no-usage-block error. `llm.test.ts` shows an early usage event does not double-count metering.
- Gate: all 232 test files passed, all steps green (`sp4-gate.txt`). Typecheck proves the handler branches are exhaustive.
- Smoke: 31 passed, 0 failed, 1 skipped (real-browser render) (`sp4-smoke.txt`). The smoke runner does not call the LLM; it shows edge and egress still boot and serve.
- The agent's first gate run hit the known `connectionsJourney` flake and an `apps/egress/src/retire.integration.test.ts` `beforeAll` timeout; its second run and the coordinator's run were clean.

## Unverified

That real vendors send usage in the cadence the design assumes (Anthropic `message_start` then a `message_delta` near the end; OpenAI one final usage chunk). Not Azure-specific.

## Executor

cursor-agent, `composer-2.5`, 36 tool calls.
