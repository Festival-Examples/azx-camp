# How Helix builds and runs

_Scope:_ How `projects/helix` at `792557a` is set up, built, run, checked, published, and deployed. Descriptive, not a findings report. Section 6 lists developer-experience gaps and marks each one Confirmed or Hypothesis.

_Method:_ Read the files named in the brief with `cat -n` or `awk`: `.devcontainer/` (Dockerfile, docker-compose.yml, devcontainer.json, post-create.sh, REMOTE.md, start-remote.sh, db-init/01-roles.sql), `.env.example`, `package.json`, `justfile`, `.justfiles/*.just`, `check-and-lint.sh`, `build-images.sh`, `scripts/*.mjs`, `.github/workflows/*.yml`, `apps/*/Dockerfile`, `apps/certbot/issue-and-bind.sh`, and the deploy sections of `infra/azure/README.md` (lines 298-346, 524-860, 1114-1153). Also read `apps/portal/package.json`, `apps/portal/scripts/migrate-deploy.ts`, `infra/azure/modules/migrate-job.bicep`, `infra/azure/main.bicepparam`, `apps/docs/.vitepress/config.ts`, `.claude/skills/run-helix/SKILL.md`, and `vitest.globalSetup.ts`. Ran `git remote -v`, `git ls-files` with grep counts, and `grep` across `.github` and `infra`. Did not run pnpm, tests, Docker, or builds, and made no network calls.

## 1. Prerequisites

| Need | Version or value | Where it is set | Notes |
| --- | --- | --- | --- |
| Node | 24 or later | `package.json:6-8` (`engines.node >=24`) | The dev image is `typescript-node:24` (`.devcontainer/Dockerfile:3`). The CLI also accepts Node 22.12+ (`packages/cli/package.json:23`). |
| pnpm | 11.5.3 | `package.json:9` (`packageManager`). Enabled through corepack at `.devcontainer/Dockerfile:64`. | CI pins the same version (`ci.yml:92`, `223`, `320`). |
| Docker with Compose | Any recent version | `.devcontainer/docker-compose.yml` | Needed for the dev container and for building images. |
| VS Code Dev Containers | n/a | `.devcontainer/devcontainer.json` | The supported way in (`CLAUDE.md`, Environment section). |
| just | 1.58.0 | `.devcontainer/Dockerfile:24` | Installed in the container. Needed on the host only to run recipes outside it. |
| Azure CLI | Latest from `aka.ms`, not pinned | `.devcontainer/Dockerfile:52` | Used by `just infra build` and by the deploy runbooks. |
| gh | Latest from apt | `.devcontainer/Dockerfile:38-44` | |
| actionlint | 1.7.7 | `.devcontainer/Dockerfile:18-19` | Installed. No workflow runs it (see section 6). |
| shellcheck, mkcert, postgresql-client, jq, ripgrep | apt | `.devcontainer/Dockerfile:10-12` | shellcheck is installed but no workflow runs it. mkcert makes the dev wildcard certificate. |
| Postgres | 18 | `docker-compose.yml:194` (`postgres:18`); CI service at `ci.yml:133` | |
| Azurite | Image with no tag | `docker-compose.yml:214`; CI at `ci.yml:244` | Emulates Blob, Queue, and Table. |
| Jaeger all-in-one | 1.62.0 | `docker-compose.yml:239` | Trace viewer for local telemetry (ADR-0037). |
| Coding agents | Claude Code, codex, opencode, pi | `.devcontainer/Dockerfile:70-83` | Optional for building or running the platform. |

**Secrets.**

- Dev secrets are committed as well-known values in `docker-compose.yml:22-157` and `.env.example:64-69`. Examples: `PORTAL_DEV_TOKEN: dev-deploy-token` (`docker-compose.yml:39`), the edge OIDC client secret `edge-dev-secret` (`docker-compose.yml:103`), and the dev signing keys (`docker-compose.yml:105`, `121-126`). Comments in those files say they are dev-only.
- Generated locally and gitignored: the mkcert certificate and the dev secret-store key (`post-create.sh:49-68`). `.gitignore:35` covers `.devcontainer/certs/`.
- No private keys or long secret-looking literals are tracked. The `.env` files are ignored except `.env.example` (`.gitignore:27-29`).
- Production secrets are created by the operator and stored in Key Vault. The steps and the environment variables are in `infra/azure/README.md:221-297` (secret delivery) and `626-652` (the exports for the first apply).

**Certificates and DNS.**

- The edge refuses to boot in dev without `EDGE_TLS_CERT_FILE` and `EDGE_TLS_KEY_FILE` (`docker-compose.yml:106-113`). The comment says the platform is HTTPS-only.
- Service workers need a secure context. For that, the host browser must trust `.devcontainer/certs/caroot/rootCA.pem`. The post-create script says a click-through warning is enough for most work but not for the offline capability (`post-create.sh:35-48`).
- Dev hostnames use `*.local.helix.azxlabs.io`. The compose comment says this name resolves to `127.0.0.1` (`docker-compose.yml:87-89`). The zone belongs to the upstream organization's domain. I did not resolve the name.

**Network at create or build time.**

- Installers piped to `sh`: Herdr, Moshi, Claude Code (`Dockerfile:52`, `70-72`, `78`).
- `npx -y playwright@latest` runs twice (`post-create.sh:33`, `87`).
- The DB-IP City Lite download, about 127 MB (`ci.yml:504`), runs in post-create and is non-fatal (`post-create.sh:76-84`).

**Azure, for a deploy.**

- Register resource providers, check Postgres SKU availability, and confirm quota for two Container Apps environments (`infra/azure/README.md:524-568`).
- Create Entra app registrations (`infra/azure/README.md:1116-1119`; runbook `docs/runbooks/entra-app-registration.md`).
- Delegate `azx.helix.azxlabs.io` from the parent `azxlabs.io` Cloudflare zone before the first certificate run (`infra/azure/README.md:845-859`).

## 2. Local development

### 2.1 Supported path: the dev container

1. Open the repo in the container (VS Code: Reopen in Container). `devcontainer.json:18` runs `bash .devcontainer/post-create.sh` once after creation.
2. Compose builds the `app` service from `.devcontainer/Dockerfile` with the repo as the build context (`docker-compose.yml:2-9`). It also starts `db` and `azurite` (`docker-compose.yml:187-191`).
3. `post-create.sh` does the following, in order:
   - Hands named volumes to the `node` user (`post-create.sh:4-16`).
   - Links the Claude config file (`:18-24`).
   - Points the pnpm store at a named volume (`:26-30`).
   - Installs Playwright system dependencies (`:32-33`).
   - Creates the mkcert certificate (`:35-56`) and the dev secret-store key (`:58-68`).
   - Runs `CI=true pnpm install` (`:70-74`).
   - Downloads the geolocation database (`:76-84`).
   - Installs Chromium (`:86-87`).
4. Compose sets the environment (`docker-compose.yml:15-157`). Section 2.1 lists the groups below.
5. Dev servers are started by hand (section 2.2).

**Compose services.**

| Service | Image | Host ports | Purpose |
| --- | --- | --- | --- |
| `app` | Built from `.devcontainer/Dockerfile` | `51271` to 22 (ssh), `60000-60010/udp` (mosh) | The workspace. Runs sshd for phone access (`docker-compose.yml:183-186`, `REMOTE.md`). |
| `db` | `postgres:18` | `26663` to 5432 | Owner role `helix`, plus runtime roles from `db-init/01-roles.sql` (`docker-compose.yml:193-211`). |
| `azurite` | `mcr.microsoft.com/azure-storage/azurite` | `37604` (blob), `26585` (queue), `40209` (table) | Blob emulator (`docker-compose.yml:213-225`). |
| `otel-collector` | `jaegertracing/all-in-one:1.62.0` | `27686` (Jaeger UI) | Accepts OTLP on 4318 and stores traces only (`docker-compose.yml:238-245`). |

The identity provider is not a compose service. It runs inside the `app` container on port 3002 so that its issuer URL, `http://localhost:3002`, is the same from the host browser and from the container (`docker-compose.yml:44-48`).

**Processes and ports** (`scripts/stack-env.mjs:13-22`, `devcontainer.json:22-33`):

| Process | Port | Start command |
| --- | --- | --- |
| helix-edge (https) | 8080 | `pnpm dev:edge` |
| helix-egress | 8081 | `pnpm dev:egress` |
| dev gateway (env=dev tier) | 8082 | `pnpm dev:devgw` (not started by default) |
| helix-portal API | 3001 | `pnpm dev:portal` |
| dev IdP (OIDC) | 3002 | `pnpm dev:idp` |
| dev OAuth vendor | 3003 (plain), 3443 (TLS front) | `pnpm dev:vendor`, `pnpm dev:vendor-tls` |
| portal SPA (Vite) | 5173 | `pnpm dev:web` |
| docs site (VitePress) | Default VitePress port | `pnpm dev:docs` |

**Environment groups set by compose** (`docker-compose.yml`):

- Database: `DATABASE_URL` (the owner, used for migrations and tests), plus `PORTAL_DATABASE_URL`, `EDGE_DATABASE_URL`, `EDGE_DEV_DATABASE_URL`, `EGRESS_DATABASE_URL`, and `TEST_DATABASE_URL`. Each runtime service uses its own least-privilege role (`:16-30`, `:118`).
- Blob: `AZURE_STORAGE_CONNECTION_STRING` pointed at Azurite, and `BLOB_CONTAINER` (`:31-35`).
- Identity: `PORTAL_OIDC_*` and `EDGE_OIDC_*` pointed at the dev IdP, plus `PORTAL_ADMIN_GROUP_ID` (`:44-63`, `:99-104`).
- Secrets and keys: `PORTAL_SECRET`, `EDGE_AUTH_SECRET`, `HELIX_INSTRUCTION_SECRET`, `HELIX_INTERNAL_SECRET`, `HELIX_EXCHANGE_SECRET`, and `DEV_SECRETS_KEK_FILE` (`:39-43`, `:105`, `:121-126`, `:157`).
- TLS and trust: `EDGE_TLS_CERT_FILE`, `EDGE_TLS_KEY_FILE`, and `NODE_EXTRA_CA_CERTS` (`:112-114`).
- Public URLs: `EDGE_BASE_DOMAIN=local.helix.azxlabs.io`, `APP_PUBLIC_BASE`, and `DEV_API_PUBLIC_BASE` (`:86-98`).
- Service addresses: `EDGE_EGRESS_URL`, `PORTAL_EGRESS_URL`, and `EDGE_PORTAL_URL` (`:127-137`).
- Telemetry: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` (`:153`).
- Dev-only switches, each refused under `NODE_ENV=production` according to the comments: `EDGE_ALLOW_DEV_MODE`, `PORTAL_ALLOW_SELF_APPROVE`, `EGRESS_ALLOW_PRIVATE`, `EGRESS_ALLOW_INSECURE_CONNECTION`, `PORTAL_OIDC_ALLOW_INSECURE`, and `EDGE_OIDC_ALLOW_INSECURE` (`:28`, `:52`, `:60`, `:104`, `:142-143`). `EDGE_DEV_ALLOW_UNAUTHENTICATED` is `false` (`:71`).

### 2.2 Running each plane

Run `just` with no arguments to list the recipes (`justfile:24-26`). The root justfile loads six modules: `dev`, `check`, `db`, `cli`, `image`, and `infra` (`justfile:6-22`). Each recipe calls a `pnpm` script from `package.json`.

| Plane or task | just | pnpm script | Source |
| --- | --- | --- | --- |
| Edge | `just dev edge` | `pnpm dev:edge` | `dev.just:11-13`, `package.json:11` |
| Egress | `just dev egress` | `pnpm dev:egress` | `dev.just:19-21` |
| Dev gateway | `just dev devgw` | `pnpm dev:devgw` | `dev.just:15-17` |
| Portal API | `just dev portal` | `pnpm dev:portal` | `dev.just:23-25` |
| Dev IdP | `just dev idp` | `pnpm dev:idp` | `dev.just:27-29` |
| Portal SPA | `just dev web` | `pnpm dev:web` | `dev.just:31-33` |
| Docs site | `just dev docs` | `pnpm dev:docs` | `dev.just:35-37` |
| Fixture OAuth vendor | `just dev vendor` and `just dev vendor-tls` | `pnpm dev:vendor`, `pnpm dev:vendor-tls` | `dev.just:39-45` |
| Free stale ports | `just dev clean` | `pnpm dev:clean` | `dev.just:47-49` |

Each dev server frees its port first with `scripts/free-port.mjs`, then runs `tsx watch` (for example `apps/edge/package.json:7`, `apps/portal/package.json:7`).

**Whole stack.** `just dev smoke` runs `node .claude/skills/run-helix/smoke.mjs` (`dev.just:51-54`). The driver starts edge, portal, egress, the dev IdP, and the SPA on a `+1000` port offset, using its own database `helix_smoke` (`SKILL.md`; `stack-env.mjs:63`). It runs 34 checks, including a Chromium render of the SPA, then stops the services. Flags: `--no-browser`, `--only <group>`, `--keep`, and `--offset N`.

**Database.**

- `just db migrate --name <name>` runs `prisma migrate dev` (`db.just:10-13`).
- `just db deploy` runs `prisma migrate deploy` (`db.just:15-17`). `just db reset` drops and recreates the dev database after a prompt (`db.just:19-22`). `just db generate` regenerates the Prisma client (`db.just:24-26`).
- The portal's `postinstall` runs `prisma generate` (`apps/portal/package.json:10`).
- Runtime roles come from `.devcontainer/db-init/01-roles.sql`, which Postgres runs only when the data directory is empty (`01-roles.sql:9-12`).

**Tests.** `pnpm test` runs `vitest run` (`package.json:27`). The global setup creates `helix_test`, then runs `prisma migrate deploy` against it (`vitest.globalSetup.ts:9-23`). Tests need Postgres and Azurite.

**Host path (not the supported path).** `.env.example:1-3` says to copy the file to `.env` for runs outside the container. It sets about eight variables. Compose sets 45 keys for the `app` service. See section 6.

## 3. Quality gate

`./check-and-lint.sh` runs the steps named in `ALL_STEPS` (`check-and-lint.sh:20`). With no step names, it runs all of them. Each step runs even if an earlier one fails, and the script exits non-zero at the end (`check-and-lint.sh:4`).

| Step | Command | Needs Postgres | Needs Azurite | Source |
| --- | --- | --- | --- | --- |
| typecheck | `pnpm typecheck` (`pnpm -r typecheck`) | No | No | `check-and-lint.sh:110`, `package.json:22` |
| lint | `pnpm lint` (`eslint .`) | No | No | `check-and-lint.sh:111`, `package.json:23` |
| refs | `git ls-files` piped to grep for the planning identifiers `I-xx` and `T-nnnn` | No | No | `check-and-lint.sh:118` |
| format | `pnpm format:check` (`prettier --check .`) | No | No | `check-and-lint.sh:119`, `package.json:26` |
| docs | `pnpm --filter @azx-pbc/docs-site build` (VitePress, fails on dead links) | No | No | `check-and-lint.sh:123` |
| test | `pnpm test` (`vitest run`) | Yes (`helix_test`) | Yes | `check-and-lint.sh:128`, `package.json:27`, `vitest.globalSetup.ts` |

- `--fix` runs `lint:fix` and `format` before the steps (`check-and-lint.sh:102-108`).
- Arguments after `--` go to Vitest, and only when `test` is the only step (`check-and-lint.sh:65-70`). This is how CI shards the tests.
- The connections browser lane is not in `ALL_STEPS`. It runs only in CI (`ci.yml:336-341`).

**just wrappers** (`.justfiles/check.just`):

- `just check` runs the full gate (`:7-9`).
- `just check static` runs `typecheck lint refs format docs`. It needs no services (`:15-17`).
- `just check test` runs the test step, with optional Vitest arguments (`:39-42`).
- `just check lane` runs the Playwright connections lane (`:48-50`).

`CLAUDE.md` says to run the gate before committing or reporting a change as finished.

## 4. CI and CD

**Triggers.** All three workflows run only on `workflow_dispatch`:

- `ci.yml` has `push` and `pull_request` commented out (`ci.yml:60-65`).
- `docs.yml` has its `push` trigger commented out (`docs.yml:15-18`).
- `release-cli.yml` has its `push` trigger commented out (`release-cli.yml:28-31`).

Nothing runs on a push or a pull request. `CLAUDE.md` says the same thing: nothing checks a pull request unless someone runs the gate.

| Workflow and job | What it needs | What it does | What it publishes |
| --- | --- | --- | --- |
| `ci` / `static` | No services. Default `GITHUB_TOKEN` with read access. | Installs with `--frozen-lockfile`, then runs `./check-and-lint.sh typecheck lint refs format docs` (`ci.yml:79-105`). | Nothing. |
| `ci` / `test` (shards 1/3, 2/3, 3/3) | Postgres 18 service (`ci.yml:129-144`). Azurite started with `docker run` and the `--skipApiVersionCheck` flag (`ci.yml:240-246`). `db` and `azurite` mapped to 127.0.0.1 (`ci.yml:196-199`). Role SQL run with `psql` (`ci.yml:212-216`). Dev values inline (`ci.yml:146-191`). | Runs `./check-and-lint.sh test -- --shard=N` (`ci.yml:258-259`). | Nothing. |
| `ci` / `browser-lane` | Postgres 18 service only (`ci.yml:281-294`). | Installs Chromium with Playwright, then `xvfb-run pnpm --filter @azx-pbc/connections-lane test` (`ci.yml:337-341`). | Trace artifact, on failure only (`ci.yml:343-349`). |
| `ci` / `bicep` | None. `az` is on the runner image. | `az bicep build` and `build-params` for `infra/azure` and `infra/entra` (`ci.yml:363-374`). | Nothing. |
| `ci` / `package` | Waits for `static`, `test`, and `browser-lane` (`ci.yml:379`). | Builds the CLI, packs it with `pnpm pack`, checks the tarball contents and manifest, then installs it globally with `tsx` removed from PATH (`ci.yml:400-459`). | Artifact `helix-cli-tarball` (`ci.yml:456-459`). Not published to npm. |
| `ci` / `images` (edge, portal, egress, certbot) | Waits for `static`, `test`, and `browser-lane` (`ci.yml:464`). `packages: write` (`ci.yml:466-468`). Logs in to ghcr.io with `GITHUB_TOKEN` (`ci.yml:482-490`). | Builds each `apps/<app>/Dockerfile` for `linux/amd64` with buildx (`ci.yml:517-529`). Tags come from `docker/metadata-action` (`ci.yml:492-502`). | `ghcr.io/<owner>/helix-<app>`, tagged with `sha-*`, the branch name, and the semver on `v*` tags, plus `latest` on the default branch. Pushed on every run that is not a pull request (`ci.yml:525`). A manual dispatch therefore pushes. |
| `docs` / `build` | None. | Builds the docs site and uploads the Pages artifact (`docs.yml:35-57`). | Artifact. |
| `docs` / `deploy` | Pages enabled on the repository, environment `github-pages` (`docs.yml:64-66`). | `actions/deploy-pages@v4` (`docs.yml:68-70`). | GitHub Pages at `https://azx-pbc-oss.github.io/helix/` (`docs.yml:3-4`, `apps/docs/.vitepress/config.ts:19`, `23`). |
| `release-cli` / `publish` | `id-token: write` (`release-cli.yml:33-35`). npm trusted publishing with OIDC. No `NPM_TOKEN` (`release-cli.yml:3-6`). | Checks that the tag `cli-v*` matches `packages/cli/package.json` (`:71-82`). Builds, packs with pnpm, checks the tarball, and smoke-tests on Node 24 and Node 22 (`:84-160`). Publishes with `npm publish --provenance` (`:169-180`). | `@azx-pbc/helix-cli` on public npm. The current version is 0.4.0 (`packages/cli/package.json:3`). |

**Notes on the table.**

- `ci.yml:30-34` says sharding and the early browser lane are worth it because "standard GitHub-hosted runners are free and unbilled for public repos", and that the layout should be revisited "if the repo goes private." The repo is private now. `ci.yml:57-59` says runs bill Actions minutes. The comment at `:30-34` is stale, and the trade-off it describes has reversed.
- The `release-cli` version check reads `GITHUB_REF_NAME` (`release-cli.yml:76`). Hypothesis: on `workflow_dispatch` GitHub sets this to the branch or tag selected in the UI. If so, the job must be dispatched against a `cli-v*` tag. Dispatching from `main` would fail the check. Not run.
- No workflow deploys to Azure, runs the migration job, or runs the role script. The deploy is manual (section 5).
- The static job does not run `shellcheck` or `actionlint`, though the dev image installs both (section 6).

## 5. Build and deploy

### 5.1 Three ways to build an image

1. **CI `images` job** (the authoritative path). Builds four images from `apps/<app>/Dockerfile` with the repo as context, for `linux/amd64` (`ci.yml:461-529`). For the portal it passes `GEOIP_DB_MONTH=skip` on pull requests and `GEOIP_CACHE_KEY=<YYYY-MM>` otherwise (`ci.yml:508-515`, `apps/portal/Dockerfile:23-48`).
2. **`just image build <app> [tag]`**. Same Dockerfiles and the same `linux/amd64` default (`.justfiles/image.just:11`). Tags the result `helix-<app>:local` and never pushes (`image.just:2-3`, `:21-40`). Builds all four apps, including `certbot` (`image.just:39-40`). On Apple Silicon, set `PLATFORM=linux/arm64` (`image.just:5-7`). The geolocation download is skipped unless `GEOIP_DB_MONTH` is set (`image.just:13-15`).
3. **`build-images.sh`**. Builds three apps only: `edge`, `portal`, `egress` (`build-images.sh:53-55`, `41-50`). Defaults to `linux/amd64` (`:31`). It takes optional `REGISTRY`, `PUSH`, and `TAG`. Its examples use an Azure Container Registry named `helixprodacr` (`:8`, `:20-25`). It passes no GeoIP build arguments. The header says the file is not committed and should be deleted (`:3-4`), but git tracks it. See section 6.

`infra/azure/README.md:679-688` also gives a manual `docker build` and `docker push` sequence to `ghcr.io/azx-pbc-oss`.

### 5.2 How images reach Azure

- The image path is GHCR to Container Apps, pulled by tag. The Bicep default for `imageRegistry` is `ghcr.io/azx-pbc-oss` (`infra/azure/main.bicep:285`, `main.bicepparam:33`, `main.bootstrap.bicepparam:47`). The environment variable `HELIX_IMAGE_REGISTRY` overrides it (`main.bicepparam:33`). The tag comes from `HELIX_IMAGE_TAG` (`infra/azure/README.md:764`).
- The template pulls anonymously unless a container app gets a `registries` entry. The README says the GHCR packages must then be public (`infra/azure/README.md:672-677`).
- The Bicep does not create an Azure Container Registry. A grep for `Microsoft.ContainerRegistry` under `infra/` returns zero matches. The ACR named in `build-images.sh` is not part of the deploy path.
- Deploy is manual, in the order of `infra/azure/README.md` steps 1 to 7 (lines 570-860). Step 1 is a `what-if` preview (`:575-577`). Phase 1 uses `main.bootstrap.bicepparam` with `deployApps=false` (`:612-653`). Phase 2 sets `deployApps=true` (`:759-767`).

### 5.3 Migrations in production

- Each migration runs in the `<namePrefix>-migrate` Container Apps Job (`infra/azure/modules/migrate-job.bicep`). The job runs the portal image with the command `pnpm --filter @azx-pbc/portal db:deploy:azure` (`migrate-job.bicep:113-116`). That script is `tsx scripts/migrate-deploy.ts` (`apps/portal/package.json:14`).
- `migrate-deploy.ts` reads the admin password from the Key Vault secret `postgres-admin-password` (`apps/portal/scripts/migrate-deploy.ts:27`). It then runs `prisma migrate deploy` with that connection string (`:92-94`). The job's managed identity has only `Key Vault Secrets User` on the platform vault (`infra/azure/README.md:745-751`).
- The job is `Manual` (`migrate-job.bicep:20-22`). An operator starts it with `az containerapp job start -g <rg> -n <namePrefix>-migrate` and checks the execution (`infra/azure/README.md:737-743`). No workflow starts it.
- Migrations are forward-only (`migrate-job.bicep:24-25`). Re-running an older image does not roll back a migration.
- The four runtime roles (`helix_portal`, `helix_edge`, `helix_egress`, `helix_dev`) are created once by `scripts/create-roles.sh`. The script runs a throwaway job with the admin connection string and deletes it. `CREATE ROLE` is not idempotent (`infra/azure/README.md:690-726`).

### 5.4 TLS certificates (apps/certbot)

- `apps/certbot` is a scheduled Container Apps Job, not an app and not a sidecar (`apps/certbot/Dockerfile:1-12`). Its base image is `python:3.12` with no digest pin (`Dockerfile:17`).
- It requests `*.<appsDomain>` and the apex from Let's Encrypt with the DNS-01 challenge. The `certbot-dns-azure` plugin writes the TXT record using the job's managed identity (`issue-and-bind.sh:102-117`, `Dockerfile:24-26`).
- The container is ephemeral, so the script takes the renewal decision from the expiry of the certificate already in the Container Apps environment store (`issue-and-bind.sh:44-94`). It requests a new certificate only within `RENEW_BEFORE_DAYS` of expiry (default 30; `:28-34`). If the check fails, it issues a certificate (`:52-54`).
- It packages the result as a PFX and uploads it to the Container Apps environment certificate store, not Key Vault (`issue-and-bind.sh:119-135`). The script gives the reason at `:127-130`.
- Every run binds `*.<appsDomain>` to the edge (`issue-and-bind.sh:142-146`). It also binds `portal.<appsDomain>` and `dev-api.<appsDomain>` when those apps are set (`:167-178`). Bindings are repaired on every run, even when no new certificate is issued (`:10-12`).
- The job runs on a daily cron (`infra/azure/README.md:318`). The DNS delegation must exist before the first run (`infra/azure/README.md:857-859`). The bootstrap run is at `infra/azure/README.md:343-349`.
- The default CA is Let's Encrypt staging. It is set in the script (`issue-and-bind.sh:25-27`), in the Bicep (`infra/azure/main.bicep:385`, `main.bicepparam:56`, `modules/certbot.bicep:68`), and in the docs (`apps/docs/src/deploy/configuration.md:61`). To go to production, set `HELIX_ACME_SERVER` to the production directory (`infra/azure/README.md:318-320`). The repository still uses staging.
- `infra/azure/README.md:1120` lists wildcard ACME issuance as "deferred" under "NOT done by this template". The same README describes the certbot job as built (`infra/azure/README.md:298-346`). See section 6.

### 5.5 Runtime images

- `edge`, `egress`, and `portal` start with `node --import tsx src/server.ts` through `pnpm --filter ... start` (`apps/edge/Dockerfile:36`, `apps/egress/Dockerfile:27`, `apps/portal/Dockerfile:69`). The `tsx` loader is used instead of the `tsx` CLI so that the service's own shutdown handling runs (`apps/edge/Dockerfile:6-13`).
- The images keep devDependencies and have no compiled `dist`. The Dockerfile comment calls precompiling a follow-up (`apps/edge/Dockerfile:17-18`).
- Each image runs as user `node` (`USER node`). The portal image also builds the SPA (`apps/portal/Dockerfile:57`).

## 6. Developer-experience gaps

Each item shows the evidence and whether it is Confirmed (I read it or ran it) or Hypothesis (inferred, not checked).

1. **Host pnpm does not run.** `package.json:9` pins `pnpm@11.5.3`. The seed notes record that on the macOS host, pnpm fails before running anything with "Failed to switch pnpm to v11.5.3" because the CLI is missing from the expected path (`workflow/explore/helix-repo-exploration/notes/00-seed-observations.md`, Environment section). Workaround: use the container, or install pnpm 11.5.3 by hand. The hand install was not tested. **Confirmed** (from the seed note's reproduction).

2. **Shippable amd64 images cannot be built on Apple Silicon.** `.justfiles/image.just:5-7` says an amd64 build under QEMU aborts after `pnpm install`. The seed notes record `just image build edge` aborting with exit 134 and a libuv assertion. Native arm64 builds worked. Shippable amd64 images therefore need CI or an amd64 builder. **Confirmed** (the seed note's reproduction).

3. **The supported path needs Docker, host trust setup, and a public DNS name.** The edge will not boot without certificate files (`docker-compose.yml:106-113`). Service workers need the host to trust the mkcert CA (`post-create.sh:43-48`). The dev hostnames depend on `*.local.helix.azxlabs.io` resolving to `127.0.0.1` (`docker-compose.yml:87-89`). **Confirmed** for the file claims. **Hypothesis** for the DNS state, which I did not resolve.

4. **`.env.example` does not cover a host run.** `.env.example:1-3` says to copy it for runs outside the container. It sets about eight variables. Compose sets 45 keys for the `app` service (`docker-compose.yml:15-157`). The compose comment says the edge refuses to boot without the TLS variables (`:106-108`), and `.env.example` does not mention them. A new engineer who copies the file gets a boot failure. **Hypothesis** for the exact failure, since the boot path was not run. **Confirmed** for the missing variables.

5. **Dev container tools are not pinned.** `playwright@latest` is installed without a version (`post-create.sh:33`, `:87`). Herdr, Moshi, Claude Code, and Azure CLI are installed by piping remote scripts to `sh` (`Dockerfile:52`, `70-72`, `78`). Azurite has no tag (`docker-compose.yml:214`). The base image is pinned by tag, not by digest (`Dockerfile:3`). CI keys its Playwright cache to the lockfile (`ci.yml:332-335`), which the dev container does not do. Two environments built on different days can differ. **Confirmed.**

6. **Container config comments and tooling claims are stale.**
   - `devcontainer.json:20-21` says ports are "not yet pinned by any app (M0)".
   - `.devcontainer/Dockerfile:9` says shellcheck is "the same lint CI runs over scripts/". No workflow runs shellcheck. A search of tracked files finds it only in a `disable` directive (`check-and-lint.sh:50`, `infra/azure/scripts/create-roles.sh:99`) and in the Dockerfile.
   - actionlint is installed (`Dockerfile:14-19`), and no workflow runs it.
   - `devcontainer.json:22` forwards ports 10000 and 16686. Those are container ports of other services, and the host ports differ (`docker-compose.yml:223`, `244`). **Confirmed** for the stale comments. **Hypothesis** that the forwarded ports do not work as written.

7. **`build-images.sh` is out of date and still tracked.** The header says the file is throwaway and not committed (`build-images.sh:3-4`), but git tracks it. It names an Azure Container Registry, `helixprodacr` (`:8`, `:20-25`), that no Bicep file creates. It builds three apps and omits `certbot` (`:54`). It passes no GeoIP arguments, while CI does (`ci.yml:508-515`). Use `just image build` instead. **Confirmed.**

8. **Deployment docs disagree with the code.**
   - `infra/azure/README.md:657-658` says CI publishes on pushes to the default branch and on `v*` tags. The triggers are commented out (`ci.yml:61-64`).
   - `infra/azure/README.md:655-664` says CI builds "three images". CI builds four (`ci.yml:475`).
   - `infra/azure/README.md:1120` lists wildcard ACME as not done by the template. `infra/azure/README.md:298-346` and `infra/azure/modules/certbot.bicep` describe it as built.
   - `.devcontainer/db-init/01-roles.sql:3` says production roles are "Terraform-managed". Production uses Bicep, `infra/azure/sql/01-roles.sql`, and `scripts/create-roles.sh` (`infra/azure/README.md:690-726`).
   - `ci.yml:30-34` says the repo is public and runner minutes are free. `ci.yml:57-59` says the repo is private and minutes bill.
   - **Confirmed** for each item.

9. **A stale edge setting fails late in the deploy.** `infra/azure/README.md:584-600` says `what-if` does not catch a stale `HELIX_EDGE_TRUST_PROXY`. The deployment aborts at step 5, after images are built and the apps are deployed. The operator must check the variable by hand. **Confirmed** (documented in the runbook).

10. **Deploy is manual and secret-heavy.** The first apply needs about eleven exported secrets (`infra/azure/README.md:626-652`). The rules differ by secret: DB passwords must be base64url, and signing secrets must be standard base64. The README says a base64url signing secret makes the edge crash on boot (`infra/azure/README.md:626-635`). **Confirmed** (documented).

11. **Nothing links image build, migration, and rollout.** No workflow calls `az containerapp` or starts the migration job (`grep` over `.github/` returns nothing). The migration job is `Manual` (`migrate-job.bicep:20-22`). **Confirmed.**

12. **The role SQL runs only on an empty database volume.** `db-init/01-roles.sql:9-12` says Postgres runs it once, on an empty data directory. Changing the grants means recreating the volume with `docker compose down -v`, which deletes local data. `just db reset` does not recreate roles. **Confirmed** (from the file's own comment; I did not run it).

13. **The local gate is incomplete or needs services.** `just check` and `./check-and-lint.sh` run the test step, which needs Postgres and Azurite (`check.just:7-9`, `check-and-lint.sh:128`). Without them, a new engineer gets test failures. `just check static` avoids services (`check.just:15-17`). The connections browser lane is in CI only (`ci.yml:336-341`), so it is not part of the local gate. **Confirmed.**

14. **Nothing runs on push or pull request.** The triggers are commented out in `ci.yml:60-65`, `docs.yml:15-18`, and `release-cli.yml:28-31`. Each run needs someone to start it by hand. **Confirmed.**

15. **CI and compose hand-copy the same environment.** `ci.yml:146-191` repeats about thirty values from `docker-compose.yml`. The copies have already diverged on purpose: CI omits `PORTAL_ALLOW_SELF_APPROVE` (`ci.yml:166-169`), and compose sets it (`docker-compose.yml:60`). Any future change has to be made in both places. **Confirmed.**

16. **The dev stop helper is Linux-only.** `scripts/free-port.mjs:22-25` calls `ss`. If `ss` is missing, the script returns no listeners and exits without an error (`:12-13`). On macOS, `pnpm dev:clean` would do nothing. Impact is low because the dev servers run in the container. **Hypothesis** (not run on macOS).

17. **Manual dispatch of the CLI release.** The version check reads `GITHUB_REF_NAME` (`release-cli.yml:76`). The manual dispatch must target a `cli-v*` tag. **Hypothesis** (see section 4).
