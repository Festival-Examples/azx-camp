# Testing gate: sequence 01 (spend controls)

Run on `main` = `8bb294f` (all of SP-1 to SP-13), inside the dev container, every command with `ulimit -c 0`. Logs are the `gate-testing-*` files in this folder.

| Check | Result |
| --- | --- |
| `./check-and-lint.sh`, run 1 | 235 of 236 test files; the one failure is `apps/portal/src/deploy/diagnose.test.ts` > "stays fast on a pathological many-entry zip", a 3 s timing bound seen flaking before (SP-1, SP-2). Not touched by this sequence. |
| `./check-and-lint.sh`, run 2 | All steps passed, 236 of 236 test files. |
| Adversarial telemetry suites with `OTEL_SDK_DISABLED=1` (`spanRedaction`, `traceBoundary`, egress `spanAttributes`, gateway `telemetry`) | 4 files, 46 tests passed. |
| `just infra build` | Passed. |
| `just dev smoke` | 31 passed, 0 failed, 1 skipped (real-browser render needs `HELIX_SMOKE_CHROME`). |
| `just dev smoke` with `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100` | 31 passed, 0 failed, 1 skipped; the platform-ceiling startup check passes on a fresh database. |
| `just dev smoke` with `HELIX_SMOKE_CHROME` set | 34 passed, 0 failed, 0 skipped, including the SPA render in a real browser. |
| `just check lane` (connections browser lane) | 10 passed. |
| Repository after the gate | Clean. |

## Environment fixes made to run the lane

The dev container could not run the browser lane as built:

- `xvfb-run` failed with "xauth command not found". Installed `xauth` in the running container (not in the image; a rebuild loses it).
- The lane's pinned Playwright needs `chromium-headless-shell` build 1243; post-create installs the latest build only. Installed with `pnpm --filter @azx-pbc/connections-lane exec playwright install chromium`, the same command CI uses.

Both are dev-container gaps worth fixing in `.devcontainer/Dockerfile` and `post-create.sh` (follow-up, outside this festival's scope).

## Flaky tests seen across the sequence

All outside the changed code, all passing when rerun alone: `connectionsJourney.integration.test.ts` (known, HEALTH-1), `diagnose.test.ts` (timing), `password-login.test.ts`, `password.test.ts`, `data.test.ts`, `approvals.test.ts`, `retire.integration.test.ts` (host load average was 20 to 80 during the run). One flaky test is inside the sequence: the platform-aggregate test in `usage.rls.integration.test.ts` (SP-8/SP-9), which asserts an exact delta in a cross-app sum while other files write rows; it goes to the iterate step.

## Unverified in Azure

Listed per change in `sp2-*.md`, `sp6-*.md`, `sp8-*.md`, `sp9-*.md`, `sp11-*.md`, `sp12-*.md`: Bicep parameters and env wiring (compile-checked only), alert queries, the production owner role under `FORCE` RLS, hang-up propagation through the Container Apps ingress, and lease behavior across real replicas.
