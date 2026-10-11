# Iterate gate: sequence 01 (spend controls)

All findings from the testing gate (`gate-testing.md`) and the code review (`review-01-spend-controls.md`) are fixed, recorded as documented, or deferred with a reason. Fixes landed in five batches, each on its own branch, gated by the coordinator (`./check-and-lint.sh`, smoke, browser lane where the change touched it), and fast-forwarded to `main`.

| Finding | Disposition | Where |
| --- | --- | --- |
| R-1 rollout order takes down LLM | Fixed | IT-1 (`it1-rollout-boot-shutdown.md`) |
| R-2 one tenant can trip the shared ceiling | Fixed per owner decision: bounded cut charges, approval for new grants and at create, 3x default ceiling and boot warning; per-app fairness not built (decided) | IT-2, IT-3 |
| S-1 lease lock waits starve the pool | Fixed (250 ms lock timeout, refusal on timeout) | IT-4 |
| S-2 dev gateway outside the ceiling | Documented as an accepted precondition (ADR-0051, rollout notes) | IT-1 |
| S-3 restarts strand leases | Fixed (abort 3 s before the shutdown deadline) | IT-1 |
| S-4 LLM hang-up during admission | Fixed | IT-4 |
| S-5 fresh LLM grant skips classifier | Fixed | IT-3 |
| S-6 app creation skips classifier | Fixed (owner decision), response kept backward compatible | IT-3 |
| S-7 SP-2 test proves nothing | Fixed | IT-5 |
| S-8 egress span reports 200/ok on hang-up | Fixed, docs updated | IT-4 |
| S-9 exact-delta platform tests | Fixed | IT-5 |
| S-10 tests that pass without the behavior | Fixed | IT-5 |
| S-11 catalog checks drifted | Fixed (one SQL source) | IT-1 |
| S-12 `usage.ts` structure | Fixed | IT-4 |
| S-13 fetch lease held to TTL | Fixed | IT-4 |
| S-14 portal shows no cap for unset budgets | Deferred: needs the install default exposed through `GET /api/v1/config` and UI work in the portal SPA | Follow-up |
| S-15 overshoot claim | Fixed (docs and ADR-0051 corrected) | IT-2 |
| Suggestion: `EDGE_LLM_MAX_CALL_MS` upper bound | Fixed | IT-1 |
| Suggestion: `visibilityGroupIds` default | Fixed | IT-5 |
| Suggestions: docs nits, egress pooling test origin | Fixed | IT-2, IT-5 |
| Suggestions: `pg_temp` in the definer's `search_path`, unused `hour` column, partial index, `truncate` import location, `retry-after` time zone | Deferred: low value now; adopt when the code next changes | Follow-up |
| Testing gate: dev container cannot run the browser lane (no `xauth`, Playwright build mismatch) | Deferred: fix in `.devcontainer/Dockerfile` and `post-create.sh` | Follow-up |

## Follow-ups found during iteration (not review findings)

- `POST /api/v1/apps` with `visibility: public` skips the visibility classifier (same class as S-6, outside spend controls).
- `ANTHROPIC_DEFAULT_MAX_OUTPUT_TOKENS` in `packages/shared/src/pricing.ts` duplicates `DEFAULT_MAX_TOKENS` in `apps/edge/src/gateway/provider.ts`.
- A lease lock-timeout refusal is counted with reason `concurrency_app`, indistinguishable from a full cap.
- Per-model context-window and output limits in `pricing.ts` are not verified against vendor documentation.

## Final state

`main` at `ecdc5b3`. Every batch passed the full gate; IT-3 and IT-4 also passed the browser lane (10/10). Known flaky tests outside the sequence are listed in `gate-testing.md`.
