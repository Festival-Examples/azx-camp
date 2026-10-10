# SP-12 result: optional per-app lease cap on the fetch path

**Result: done.** `EDGE_FETCH_MAX_APP_IN_FLIGHT` (default 0, off; Bicep parameter `fetchMaxAppInFlight`) caps concurrent fetch-proxy calls per app across replicas with SP-10's leases on scope `fetch:app:<appId>`. Over the cap the call is refused before egress with `429 rate_limited`, the `concurrency_app` reason on SP-7's counter (capability `fetch`), and `helix.reason` on the span; no ledger row. A lease-store failure refuses with `503 upstream_error`. The lease is released on `reply.raw` `close`, which fires after the streamed body finishes or on a hang-up (a `finally` would free it at the headers), and is idempotent; a 10-minute TTL is the backstop. Fetch and LLM leases use separate scopes.

## Evidence

- `fetch.test.ts` "fetch per-app concurrency cap": refusal at the cap, lease held through the streamed body, release on hang-up, abort, and completion, cap off (acquire never called), acquire failure 503, scope isolation from `llm:app`, metric dimensions. Plus `config.test.ts` and `spanRedaction.test.ts`.
- Gate: all 236 test files passed (`sp12-gate.txt`). `just infra build` passed (`sp12-infra-build.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`sp12-smoke.txt`).

## Notes for the sequence review

- If the socket is already gone when the `close` listener attaches, the slot is held until the 10-minute TTL. SP-2 handles the same race with a `reply.raw.destroyed` check; the fetch path could do the same.
- A 4.9 GB `core` dump appeared at the repository root during the agent's runs and broke the format step; it was deleted before commit. From here on, every container command runs with `ulimit -c 0`.

## Unverified

In Azure: the Bicep parameter and env wiring (compile-checked only).

## Executor

cursor-agent, `composer-2.5`, 144 tool calls.
