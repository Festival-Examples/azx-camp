# Iterate batch IT-4: hang-up windows, egress telemetry, lease contention

Fixes review findings S-4, S-13, S-8, S-1, S-12.

- **S-4.** `apps/edge/src/gateway/llm.ts`: after admission and before the provider is called, a client that already left (`reply.raw.destroyed && !writableEnded`) is marked gone; no vendor call is made, a cut row with `client_disconnected` is written, and the lease is released by the existing `finally`.
- **S-13.** `apps/edge/src/gateway/fetch.ts`: the lease is released at once when the socket is already gone after acquire, instead of waiting for the TTL.
- **S-8.** `apps/egress/src/proxy.ts`: when the edge hangs up before response headers were sent, the span omits `helix.outcome` and `helix.upstream.status` (they used to read `ok` and 200 by default) and the duration sample carries no outcome dimension. `spanAttributes.test.ts` asserts it. The coordinator updated `docs/features/observability.md`, which still described the old behavior.
- **S-1.** `apps/edge/src/gateway/leaseStore.ts`: `SET LOCAL lock_timeout = '250ms'` in acquire; a lock timeout (55P03) returns a refusal for that scope instead of holding a pool connection, so one app flooding its own scope cannot starve other apps of connections.
- **S-12.** `apps/edge/src/gateway/usage.ts`: imports consolidated, metering helpers grouped; no behavior change.

## Evidence

- `llm.test.ts` "does not call the provider when the client leaves during admission", `fetch.test.ts` "releases the lease when the socket is already gone after acquire", `leaseStore.integration.test.ts` "refuses quickly when an advisory lock is already held on the scope", `spanAttributes.test.ts`. The agent reports each would fail without its fix.
- Gate: 237 of 237 test files (`it4-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`it4-smoke.txt`). Browser lane: 10 passed (`it4-browser-lane.txt`).

## Note

A lock-timeout refusal reaches the handlers through the same path as an at-cap refusal, so it is counted with reason `concurrency_app`. Operators cannot tell contention from a full cap in the counter; acceptable for now, recorded for a follow-up if it matters in practice.

## Executor

cursor-agent, `composer-2.5`, 65 tool calls.
