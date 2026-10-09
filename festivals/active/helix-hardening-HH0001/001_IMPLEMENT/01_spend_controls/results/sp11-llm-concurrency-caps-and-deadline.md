# SP-11 result: concurrency caps and a call deadline

**Result: done.** The LLM handler (`apps/edge/src/gateway/llm.ts`) now admits a call only after a per-replica gate (`apps/edge/src/gateway/replicaGate.ts`, `EDGE_LLM_MAX_IN_FLIGHT`, default 200) and SP-10's leases for the app (`EDGE_LLM_MAX_APP_IN_FLIGHT`, default 10) and, for signed-in callers, the user within the app (`EDGE_LLM_MAX_USER_IN_FLIGHT`, default 3). Each cap can be set to 0 to switch it off. Refusals are 503 `capability_unavailable` with `retry-after: 1` and the reasons `concurrency_replica`, `concurrency_app`, `concurrency_user` on SP-7's counter and span. A lease-store failure refuses the call (503, `retry-after: 5`). Every upstream call has a wall-clock deadline (`EDGE_LLM_MAX_CALL_MS`, default 600000; cannot be 0) through `AbortSignal.timeout`; a call that hits it is charged on SP-5's cut path and answered 502. Leases live for the deadline plus a grace period, and the edge sweeps expired rows on a timer. Bicep parameters and edge and dev-gateway env added.

## Lease lifecycle (reviewed)

Gate first, then lease acquire; the gate is left on every refusal and on acquire failure. After admission one `finally` releases the leases on every exit path, after `recordOnce` has written the ledger row, so the next admission check sees the spend.

## Evidence

- `llm.test.ts` "concurrency caps and the call deadline": per-app and per-user caps, anonymous callers not user-scoped, replica gate full, release ordering on stream, non-stream, error, and hang-up, caps at 0, lease failure fails closed, deadline abort charged with an SSE error, lease TTL equals deadline plus grace, metrics without personal dimensions, and the KP-2 exploit: eight hung-up streams are charged, leases return to zero, and the platform ceiling refuses the ninth call (run sequentially for stability).
- `replicaGate.test.ts`, `config.test.ts`, `spanRedaction.test.ts`, `telemetry.test.ts`.
- Gate: all 236 test files passed (`sp11-gate.txt`). `just infra build` passed (`sp11-infra-build.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`sp11-smoke.txt`); the edge and dev gateway boot with the real `PgLeaseStore` and the sweep scheduled.

## Unverified

In Azure: the Bicep parameters and env wiring (compile-checked only), and lease behavior across real Container Apps replicas (proven locally with two pools in SP-10's tests).

## Executor

cursor-agent, `composer-2.5`, 215 tool calls.
