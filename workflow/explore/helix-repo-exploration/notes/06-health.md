# Code health

_Scope:_ the project's own gates, CI history, dependencies, and change process at `main` = `792557a` (2026-10-08). _Method:_ ran `just check static` locally, read upstream CI runs with `gh run list/view -R AZX-PBC-OSS/helix`, ran `pnpm audit` and `pnpm outdated -r`, read git history.

## Summary

The code is in good mechanical health. Typecheck, lint, format, the planning-ID scan, and the docs build pass locally, and the last upstream CI run on `main` passed every job, including the sharded test suite, the Playwright browser lane, and all four image builds. There are no known vulnerable dependencies. The weak points are process: 7 of the last 30 CI runs on `main` failed, at least one of them a flaky integration test. Almost every change lands directly on `main`. On the private fork, nothing automated gates a merge anymore.

## What already meets the bar

- **Static gate passes.** `just check static` on `792557a`: typecheck 10s, lint 5s, refs 0s, format 4s, docs 3s, all passed.
- **Full CI passed on the same application code.** Upstream run 37537931019 at `24e4b32` (2026-10-06): static, test 1/3, 2/3, 3/3, browser lane, bicep compile, CLI pack, and the edge, portal, egress, and certbot image builds all succeeded in about 4.5 minutes. `792557a` differs from `24e4b32` only by the justfile, the CI trigger change, and docs.
- **No known vulnerabilities.** `pnpm audit`: 0 info, 0 low, 0 moderate, 0 high, 0 critical.
- **Large, real test suite.** About 66k lines of tests against about 66k lines of source. Edge has more test code than source (22,640 vs 16,331 lines).
- **Dependency hygiene is active.** Recent commits bump vulnerable transitive dependencies within days (`24e4b32` "patch multipart and build-tool vulnerabilities", `e7afbef` undici, `1b47eec` fast-uri).

## Findings

### HEALTH-1 Flaky integration tests on main
- **Severity:** Medium **Status:** Confirmed **Area:** Testing
- **What:** CI failed on `main` in 7 of the last 30 runs. At least one failure cannot have been caused by its commit.
- **Evidence:** `f0637a4` changed only `docs/adr/0049-warden-optional-inference-backend.md` and `docs/adr/README.md`, yet test shard 1/3 failed in `apps/edge/src/routing/connectionsJourney.integration.test.ts` ("two approved apps share one connection", `AssertionError: expected 403 to be 200`), and the next run passed with no fix. On 2026-09-26 the browser lane failed four runs in a row (`640ffbe`, `65cb58f`, `c9215f7`, `0dfb07c`, `442cc95`), ending with `453055e` "fix(lane): one CI retry — the runner transiently closed a po…", which adds a retry. `c2fdc8d` "test(egress): scope the renewal advisory-lock count to the t…" fixed a test-isolation failure from `ca14a49`.
- **Why it matters:** Flaky tests teach a team to rerun red builds instead of reading them. The flaky test covers connection sharing between apps, which is an authorization path.
- **Recommendation:** Track flaky tests explicitly, fix the race in `connectionsJourney.integration.test.ts` (the 403 suggests a projection or NOTIFY ordering race), and avoid retries that hide failures.

### HEALTH-2 No pre-merge gate
- **Severity:** High **Status:** Confirmed **Area:** Change process
- **What:** Changes go straight to `main`, and nothing enforces the gate before or after a merge on the private fork.
- **Evidence:** `git log --first-parent 24e4b32` has 502 commits; 499 of them are not merges. Upstream has 10 merged PRs in total (`gh pr list -R AZX-PBC-OSS/helix --state all`). On `lancekrogers/helix`, branch protection is unavailable: `gh api repos/lancekrogers/helix/branches/main/protection` returns HTTP 403 "Upgrade to GitHub Pro or make this repository public to enable this feature". CI triggers are commented out (PR #1, 2026-10-08).
- **Why it matters:** The only gate is a developer remembering to run `./check-and-lint.sh`. All seven red runs above happened on `main` itself, so each failure was seen only after it had landed.
- **Recommendation:** Pick one enforced gate: a cheap required CI job (static checks only), a local pre-push hook that runs `just check static`, or a self-hosted runner. Require PRs for anything outside docs.

### HEALTH-3 Major-version drift building up
- **Severity:** Low **Status:** Confirmed **Area:** Dependencies
- **What:** 50 packages are outdated. 9 are a major version behind.
- **Evidence:** `pnpm outdated -r`: `@types/node` 24 → 26 (intentional while the runtime is Node 24), `@vitejs/plugin-react` 5 → 6, `jsdom` 29 → 30, `react-router` 7 → 8, `typescript` 6 → 7, `undici` 7 → 8, `vite` 7 → 8, `vitest` 4 → 5. Prisma's "latest" is `8.0.0-rc.21`, a release candidate.
- **Why it matters:** `undici` sits on the egress and edge outbound paths. Major upgrades get harder the longer they wait.
- **Recommendation:** Schedule the toolchain majors (Vite, Vitest, TypeScript) as one change and the runtime majors (`undici`, `react-router`) as separate, tested changes.

### HEALTH-4 Tests cannot run outside the dev container
- **Severity:** Low **Status:** Confirmed **Area:** Developer experience
- **What:** The suite needs Postgres and Azurite at the hostnames `db` and `azurite`.
- **Evidence:** `vitest.globalSetup.ts` creates `helix_test` with `psql "postgresql://helix:helix@db:5432/helix"`. Run on the macOS host it fails with `psql: error: could not translate host name "db" to address`. CI aliases both names to `127.0.0.1` (`.github/workflows/ci.yml:199`, `echo "127.0.0.1 db azurite" | sudo tee -a /etc/hosts`).
- **Why it matters:** This is intended, but it means only the dev container or CI can prove a change. With CI off, the dev container is the only full gate.
- **Recommendation:** Keep the dev container as the supported path. A `just` recipe that starts `db` and `azurite` with host aliases would let the suite run on a laptop when the container is not in use.

## Not run

- The full test suite and the browser lane locally (need Postgres, Azurite, and xvfb). Upstream CI results stand in for them.
- `infra build` (no `az` on the host). Upstream CI's bicep job passed at `24e4b32`.
