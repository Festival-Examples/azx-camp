# Seed observations

Collected on 2026-10-08 while repointing `projects/helix` at the private
`lancekrogers/helix` and adding a justfile. Each item is marked **confirmed**
(read or reproduced) or **hypothesis** (inferred, still to check). Paths are
relative to `projects/helix/` unless they start with `workflow/`. Line numbers
refer to `main` at `24e4b32`.

## Remote and branches

- **Confirmed.** `origin` is now `git@github.com:lancekrogers/helix.git` (private).
  It was created from `AZX-PBC-OSS/helix` (public) at `main` = `24e4b32`, with all
  11 branches and 4 tags (`cli-v0.1.0` through `cli-v0.4.0`) copied. The upstream
  is no longer a configured remote anywhere in the camp.
- **Confirmed.** Branch state against `origin/main` on 2026-10-08 (ahead / behind):

  | Branch                                       | Last commit | Ahead | Behind |
  | -------------------------------------------- | ----------- | ----- | ------ |
  | ci/audit-report-job                          | 2026-08-18  | 1     | 260    |
  | ci/split-checks-and-bicep                    | 2026-09-04  | 0     | 156    |
  | docs/adr-0038-approval-expiry-and-queue-age  | 2026-08-19  | 2     | 245    |
  | feat/approvals-prior-decisions               | 2026-08-19  | 2     | 241    |
  | feat/fetch-proxy-path-metering               | 2026-08-29  | 0     | 202    |
  | feat/platform-observability                  | 2026-09-01  | 0     | 170    |
  | fix/24-approvals-decision-cas                | 2026-08-19  | 2     | 239    |
  | fix/bug-class-ledger                         | 2026-09-22  | 1     | 112    |
  | prototype/lovable-at-home                    | 2026-07-07  | 7     | 432    |
  | test/approvals-gate-coverage                 | 2026-08-19  | 2     | 245    |

  Three branches have nothing that is not on `main` and are candidates for
  deletion. The other seven carry unmerged commits.

## Fork-sensitive surfaces

- **Confirmed.** `.github/workflows/release-cli.yml:3,25-27,31,176` publishes
  `@azx-pbc/helix-cli` to public npm on a `cli-v*` tag through OIDC trusted
  publishing (`id-token: write`, `npm publish --provenance`).
  **Hypothesis:** the npm trusted publisher is bound to `AZX-PBC-OSS/helix`, so
  a `cli-v*` tag pushed to the fork would fail at publish.
- **Confirmed.** `.github/workflows/docs.yml:12-14,52,67` deploys GitHub Pages on
  every push to `main`. Its setup note at `docs.yml:9` targets
  `repos/AZX-PBC-OSS/helix/pages`. **Hypothesis:** Pages on a private repo
  needs a paid plan, so this job may fail on the fork.
- **Confirmed.** `.github/workflows/ci.yml:57-58` runs on push. Jobs at
  `ci.yml:75,103,257,347,372,457` are static, test (sharded, Postgres +
  Azurite), browser-lane (Playwright), bicep, package, and images.
  **Hypothesis:** this now bills Actions minutes to the personal account.
  **Update 2026-10-08:** PR #1 on `lancekrogers/helix` comments out the
  automatic triggers in `ci.yml`, `docs.yml`, and `release-cli.yml`, leaving
  `workflow_dispatch` only. Until it merges, `main` still has them.
- **To inventory.** AZX identity in code and config: the `@azx-pbc/*` package
  scope, `*.helix.azxlabs.io` hostnames, `infra/azure` and `infra/entra`
  parameter files, and image names `helix-edge`, `helix-portal`, `helix-egress`.

## Repo hygiene

- **Confirmed.** `build-images.sh:4` says "NOT committed; delete when you're
  done", but the file is tracked. It was added in `c3babda` ("infra: fix portal
  image build (offline prisma generate) + add build script").
- **Confirmed.** `build-images.sh` has drifted from the CI images job
  (`.github/workflows/ci.yml:457`). It builds three apps (no `certbot`) and
  passes no GeoIP build args, while CI builds four and sets `GEOIP_DB_MONTH`
  or `GEOIP_CACHE_KEY` for the portal. `just image build` follows CI.
- **Confirmed.** `.devcontainer/Dockerfile:9,15` says shellcheck and
  actionlint are there for CI parity ("the same lint CI runs over scripts/
  (shellcheck job)"), but no workflow under `.github/workflows/` runs either
  tool.
- **Confirmed.** `TODO.md` is 41 KB. It is the repo's own backlog and the
  starting point for the KNOWN-PROBLEMS step.
- **Confirmed.** `docs/adr/` has 51 entries; `docs/reviews/` holds dated
  reviews from 2026-06 and 2026-08.

## Environment

- **Confirmed.** The project expects work inside the dev container
  (`AGENTS.md`, Environment section). Tests need Postgres and Azurite.
- **Confirmed.** The repo ships its own end-to-end runner:
  `node .claude/skills/run-helix/smoke.mjs` (also `just dev smoke` on the
  `chore/justfile` branch) boots edge, portal, egress, the dev IdP, and the
  SPA, then runs its checks and shuts down. Start the RUN step with it; see
  `.claude/skills/run-helix/SKILL.md` for prerequisites and flags.
- **Confirmed.** On the macOS host, `pnpm` fails before running anything:
  `ERROR Failed to switch pnpm to v11.5.3. Looks like pnpm CLI is missing at
  "/Users/lancerogers/Library/pnpm/.tools/@pnpm+macos-arm64/11.5.3/bin"`.
  `package.json` pins `"packageManager": "pnpm@11.5.3"`.
- **Confirmed.** Building the default `linux/amd64` images on Apple Silicon
  fails under QEMU. `just image build edge` aborted after `pnpm install`
  finished, with `node: ../deps/uv/src/unix/linux.c:1427: uv__io_poll:
  Assertion 'errno == EEXIST' failed` (exit 134). Native builds work:
  `PLATFORM=linux/arm64 just image build edge` and `... portal` both
  succeeded on 2026-10-08. Shippable amd64 images need CI or an amd64 builder.
- **Confirmed.** `.devcontainer/Dockerfile:35,53,54,61` installs the Azure CLI,
  herdr, moshi, and Claude Code with `curl ... | sh`. That is supply-chain
  surface to weigh in the HEALTH step.
