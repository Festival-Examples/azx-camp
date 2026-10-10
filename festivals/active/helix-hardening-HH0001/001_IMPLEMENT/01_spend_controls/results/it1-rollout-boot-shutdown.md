# Iterate batch IT-1: rollout order, startup safety, shutdown

Fixes review findings R-1, S-11, S-3, S-2 (documented), and the `EDGE_LLM_MAX_CALL_MS` bound suggestion.

- **R-1.** `apps/docs/src/deploy/updates.md` now orders the upgrade: role bootstrap, migrations, images, then the template, and says the new edge image enforces lease caps from code defaults before the template is applied and that the guarded grants are skipped silently if roles are missing. The edge refuses to start when any lease cap is above 0 and its role cannot SELECT, INSERT, and DELETE on `inflight_leases` (`PgLeaseStore.checkInflightLeasesAccess`, wired in `apps/edge/src/server.ts`). The probe's insert and delete run in one transaction that always rolls back.
- **S-11.** One catalog query: `PLATFORM_SPEND_CHECK_SQL` in `apps/edge/src/gateway/usage.ts`; `platformSpendDefinerCheck.ts` deleted.
- **S-3.** In-flight LLM calls are aborted through a process-level signal combined into each call's `AbortSignal.any`, so a shutdown writes a cut row and the `finally` releases the leases. Review changed the agent's first version, which aborted the moment the shutdown signal arrived (cutting every live stream on every deploy): the abort now fires `SHUTDOWN_ABORT_MARGIN_MS` (3000 ms) before the hard deadline, or immediately if the grace period is no longer than that (`packages/shared/src/lifecycle.ts`). ADR-0051 updated.
- **S-2.** Documented, not enforced: enabling `deployDevGateway` leaves `env=dev` LLM spend outside the platform ceiling (ADR-0051, rollout notes).
- **Suggestion.** `EDGE_LLM_MAX_CALL_MS` rejects values above 2147483647; Bicep `@maxValue(2147483647)`.

## Evidence

- Tests: `leaseStore.inflightCheck.test.ts` (privilege classifier), `leaseStore.integration.test.ts` (check against `helix_edge`), `usage.platformSpendCheck.test.ts`, `lifecycle.test.ts` (abort not fired at the signal, fired at `graceMs - 3000`, immediate when grace is short), `llm.test.ts` (a shutdown-aborted stream writes a cut row and releases its lease), `config.test.ts`.
- Gate: 237 of 237 test files (`it1-gate.txt`). `just infra build` passed. Smoke: 31 passed, 0 failed, 1 skipped (`it1-smoke.txt`); the edge boots with the new lease-table check against a fresh database.

## Executor

cursor-agent, `composer-2.5`: 97 tool calls, plus 36 for the review follow-up.
