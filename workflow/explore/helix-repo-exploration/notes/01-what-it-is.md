# What Helix is

_Repository:_ `/Users/lancerogers/campaigns/azx/projects/helix`, branch `main` at `792557a` (2026-10-08).
_Method:_ read `README.md`, `TOUR.md`, `AGENTS.md`, `docs/README.md`, `docs/platform-architecture.md`, `docs/platform-project-plan.md`, `pnpm-workspace.yaml`, and the ADR files the architecture doc cites. Ran `git log` on `main`. Line counts come from the brief. Read-only; nothing in the repository was changed.

## 1. Summary

Helix is a self-hosted platform for hosting AI-generated static web apps, meaning HTML, JavaScript, CSS, and wasm bundles with no server code of their own (`docs/platform-architecture.md` §1; ADR-0020). Its users are app owners, the coding agents that build the apps, the operators who deploy it, and the people who open the apps. Users sign in once through Entra ID at the platform's edge. Each app gets its own subdomain and session cookie, and calls a same-origin `/_api` gateway for LLM calls, app data, and outbound HTTP. The core design idea is that Helix treats every hosted app as untrusted code and limits what the app can reach, instead of trying to verify the app's code (architecture §1, §9 decision 1). The trust boundary is drawn through three deployable services. The edge faces app users and holds no third-party credentials. The portal owns deploys, approvals, and the database schema. Egress is the only component that holds connection secrets or can reach the internet, and it acts only on instructions the edge has signed after its own policy checks (`TOUR.md` "The services"; ADR-0001).

## 2. Component map

Deployed? is taken from the docs and the Bicep and ADR references noted below. `yes` means it runs as a service or is linked into one; `no` means it is a library, tool, or content that is not part of the running platform; `dev-only` means it is never deployed.

| Package | Path | Plane/role | Deployed? | Source lines | Test lines |
|---|---|---|---|---|---|
| `connections-lane` | `apps/connections-lane` | Playwright browser lane for the OAuth connections journey; a CI gate | no (CI test lane) | 1794 | 0 |
| `dev-idp` | `apps/dev-idp` | Local OIDC issuer with fixture users (`oidc-provider`) | dev-only (README, ADR-0028) | 813 | 234 |
| `dev-oauth-vendor` | `apps/dev-oauth-vendor` | Fixture OAuth vendor with fault injection for tests (`apps/dev-oauth-vendor/README.md`) | dev-only | 732 | 490 |
| `docs` | `apps/docs` | Public VitePress site for operators and app authors (`AGENTS.md` Commands; `docs/README.md`) | yes (GitHub Pages; not part of the platform runtime) | 121 | 0 |
| `edge` | `apps/edge` | Data/policy plane: routing, sessions, CSP, Blob serving, `/_api` gateway (`TOUR.md`) | yes (Container Apps) | 16331 | 22640 |
| `egress` | `apps/egress` | Mechanism plane: attested-instruction verification, secret injection, SSRF controls | yes (own network zone) | 5251 | 8479 |
| `portal` | `apps/portal` | Control plane: portal and deploy API, registry, approvals, secret writes, schema owner | yes (Container Apps, not routable from app hosts) | 15726 | 16278 |
| `portal-web` | `apps/portal-web` | React 19 SPA for the portal, served by the portal | yes (served by `portal`) | 16466 | 8734 |
| `certbot` | `apps/certbot` | Scheduled wildcard TLS job (DNS-01) | yes (scheduled Container Apps job) | not measured (`Dockerfile`, `issue-and-bind.sh`) | not measured |
| `cli` | `packages/cli` | The `helix` CLI, published to public npm (ADR-0032) | no (runs on author machines) | 971 | 586 |
| `deploy-skill` | `packages/deploy-skill` | Agent skill bundle, rendered and served by the portal (ADR-0036) | no (content, served by `portal`) | 136 | 142 |
| `directory` | `packages/directory` | Entra group search and name lookup, portal-only (ADR-0040) | yes (linked into `portal`) | 645 | 519 |
| `secret-store` | `packages/secret-store` | `seal`/`open`/`destroy` custody seam; dev AES-GCM or Key Vault (ADR-0006) | yes (linked into `portal` and `egress`) | 813 | 871 |
| `shared` | `packages/shared` | Zod schemas at every boundary, no build step (`AGENTS.md`) | yes (linked into all services) | 8567 | 6202 |
| `telemetry` | `packages/telemetry` | OpenTelemetry boot, the only place an OTel SDK is imported (ADR-0037) | yes (linked into the three services; inert without an endpoint) | 687 | 525 |
| `examples` | `examples/` | Reference apps that users deploy with `helix deploy`; built `dist/` committed | no (apps for users to deploy) | 4124 | 0 |
| `infra` | `infra/azure`, `infra/entra` | Bicep for the Azure deployment (source of truth per `AGENTS.md`) | no (deploys the platform; not a runtime) | 5325 | 0 |

Notes on the map:

- `pnpm-workspace.yaml` lists only `apps/*` and `packages/*` (lines 1-3). `examples/` and `infra/` are not workspace packages.
- The workspace also pins shared dependency versions in a catalog and forces patched versions of several transitive packages through `overrides` (`pnpm-workspace.yaml` lines 58-62, 67-120). Those overrides carry their own rationale in comments.
- Test lines are large for the edge (22640) and the portal (16278), which fits the docs' emphasis on adversarial tests for auth and SSRF (`AGENTS.md` "Conventions"; `docs/platform-project-plan.md` §6).

## 3. Request flow

The steps below follow the architecture doc's section 3 (system overview), section 4 (identity and serving), section 6 (gateway), and Appendix A (login). The `TOUR.md` "How requests work" section gives the same flow in short form.

1. An app user opens `https://<slug>.<base>/`. With no `__Host-session` cookie, the edge redirects to the central login host `auth.<base>` (architecture Appendix A.1, steps 1-2).
2. Login goes through Entra ID with one registered callback on `auth.<base>`. The edge then mints a 30-second, single-use, audience-bound handoff token, and the app host burns it and sets a host-only session cookie (architecture A.1 steps 5-8, A.3, A.4; ADR-0004).
3. A static asset request is answered by the edge alone. The edge reads the app's current version from its registry projection, a cached copy of Postgres refreshed through LISTEN/NOTIFY (architecture §7; ADR-0017). It applies the access gate, injects the CSP, and streams the file from Blob at `apps/<app-id>/<version>/...` (architecture §4.3, §4.4). In production the edge reads Blob with its managed identity, not an account key (ADR-0027). The portal is not on this path.
4. An app-data call under `/_api/data/...` runs in a Postgres transaction. The edge sets `app.app_id` and `app.user_oid` for the request, and row-level security limits which rows the `helix_edge` role can see. The edge role has no grant on the secrets table (architecture §3 roles table; ADR-0002; ADR-0015).
5. An LLM call under `/_api/llm/...` is checked by the edge for model allowlist, budget, and rate. The edge writes the call to the append-only `gateway_calls` ledger and sends egress a signed instruction (architecture §6.1; ADR-0021). Egress checks the signature, injects the vendor key from its secret store, calls the vendor, and streams the response back through the edge. The edge never holds the vendor key (ADR-0008). The signing is a shared symmetric secret today (`README.md`, Prerequisites; ADR-0013).
6. A fetch call under `/_api/fetch/<url>` follows the same policy and instruction path. Egress resolves the host, rejects private and metadata address ranges, dials the checked IP, and does not follow redirects (ADR-0005; architecture §6.1).
7. Deploys use a separate control-plane host. The CLI or the portal uploads a zip. The portal validates it, stores an immutable version in Blob, and records a `preview` row in the registry. Promotion moves the live pointer to that version, and rollback moves it back (`TOUR.md` "How requests work", Deploys; architecture §5; ADR-0018). The edge picks up the pointer change through LISTEN/NOTIFY.
8. Postgres enforces the split. The portal owns the schema and runs migrations as a separate owner role. The edge can read the registry projection and insert metering and collection rows. Egress can read secrets and update `lastUsedAt` (architecture §3 roles table; ADR-0002).

## 4. Milestones and status

### The plan's milestone table

Source: `docs/platform-project-plan.md` "Status at a glance" (lines 59-72) and the milestone sections (lines 81-107).

| Milestone | Stated status in the plan | Notes in the plan |
|---|---|---|
| M0 Skeleton | Done | Monorepo, dev container, first zod schemas |
| M1 Registry + deploys | Done | Portal API, `helix deploy`, no UI |
| M2 Edge serving | Done | Host routing, registry projection, Blob serving |
| M3 Auth | Done; real Entra registration is live | Local half done in June 2026; Entra tail closed |
| M4 Gateway v0 (LLM, then app-data) | Done | Listed as "(local)" in the milestone section |
| M4.5 Egress: fetch-proxy + connections | Done | Listed as "(local)" in the milestone section |
| M5 Azure + pilot | Deployed; residuals open | Open: a real pilot app end to end, and confirming `deployFirewall` is on in live deployments (lines 74-77, 106-107) |

The plan's header says "Draft v1 · June 2026" (line 3), and its status table says "July 2026" (line 59). The architecture doc says "updated July 2026" (line 3).

### Comparison with `git log` on `main`

`AGENTS.md` line 19 says: "deployed on Azure (M5); feature work at M4.5 — Egress & Connections." The last 40 commits on `main` (2026-09-26 to 2026-10-08) show the following. The sweep commit `62c7f24` (2026-09-22) is outside that window and is cited separately below:

- Feature work after M4.5 is landing. Examples: visitor analytics for hosted apps (`240181a`, 2026-10-02, ADR-0050, merged in `2b63d2c`); the Warden inference-backend proposal (`0763c17`, `f0637a4`, `56fa5a6`, ADR-0049); the Access tab redesign and the Usage "Recent calls" card (`fc9077b`, `2d139d9`); app descriptions (`a82b0b7`); a GitHub-report example (`827e2cd`); and approval delta chips (`29ed559`). The plan does not mention them. `TODO.md` has a follow-up section for ADR-0050 (line 129) but no milestone for it. The plan's last commit is `767c96b` (2026-09-24), and it names no ADR above ADR-0048.
- Azure operations are still changing. `ab07d94` (2026-10-06) raised the `/_api/fetch` body cap to 25 MiB on Azure through a new Bicep parameter.
- Dependency work continues: `c2de317` (fastify, brace-expansion), `1b47eec` (fast-uri), and `e7afbef` (undici), each citing Dependabot alerts.
- CI was turned off for automatic runs in `11b4f14` (2026-10-08). `AGENTS.md` says CI "runs only when dispatched by hand" (lines 61-63), which matches the commit.

### Mismatches (Confirmed unless noted)

1. **"Feature work at M4.5" is out of date.** The commits above are M5-era work, and visitor analytics and the Warden design are not in the milestone plan at all. `AGENTS.md` line 19 should either name a milestone for the current work or say that feature work is no longer tied to milestones. This is the mismatch the brief asked about.
2. **The plan's M5 residuals conflict with `TODO.md` and ADR-0005.** Commit `62c7f24` (2026-09-22, "docs(todo): sweep stale items") edited `TODO.md` and ADR-0005. It removed the item "Deploy a real pilot app end to end," which the commit message says was "deleted as done." It also removed the item "Confirm `deployFirewall` is on in the live deployments," and recorded that item's outcome as an accepted risk in ADR-0005. That record (ADR-0005, "Accepted-risk record (2026-09-22)") says both current production installs run with `deployFirewall = false`. The plan (lines 74-77, 106-107) and the architecture doc (§12, M5 "Outstanding") still list both items as open. The plan was last committed on 2026-09-24, two days after that sweep.
3. **The README says the project is alpha.** `README.md` opens with "Alpha — not yet suitable for public consumption … has not been hardened for production or third-party use." `AGENTS.md` lines 19-21 and the architecture doc say the three planes "run in production." The two statements describe different things, and a new owner would be unsure which one applies. The `README.md` banner should be reconciled with `AGENTS.md`.
4. **The plan's M3 header disagrees with its own table.** Line 90 reads "M3 — Auth ✅ Done (local) · ⏳ Entra tail", while the status table (line 69) says the Entra tail is closed.
5. **The docs carry stale dates.** The plan (June and July 2026) and the architecture doc (July 2026) predate ADR-0038 through ADR-0050, which were all written between August and October 2026. The architecture doc says `ADR-0011` governs shared rate counters (line 84-85), and ADR-0011 is marked Superseded.
6. **The firewall item conflicts with the ADR's own text.** ADR-0005 says "production and untrusted/multi-tenant hosting must keep it." The same ADR's accepted-risk record says both production installs run without it. This is an accepted deviation that the ADR records, but the plan does not reflect it. Note that the repository's own parameter files set `deployFirewall = true` (`infra/azure/main.bicepparam:47`, `infra/azure/main.bicep:372`). The live installs' parameter files are not in this repository, so the difference cannot be checked here (Hypothesis that they live in a separate deployments repository, which `TODO.md` names).

## 5. Who it is for and how it is used

As the docs describe it:

- **App owners** create an app, upload a build (CLI or portal), review approvals for elevated grants, and promote versions to live (architecture §5, §7; `TOUR.md`).
- **Coding agents and the people who run them** build apps and deploy them through the agent skill bundle. Deploys default to `preview`, and a human promotes them, because agent instructions can be influenced by untrusted content (architecture §5.1; ADR-0018).
- **App end users** sign in through Entra ID (or a shared password or public mode) and never see app-specific login code (architecture §4.2, Appendix A.6).
- **Platform admins** approve elevated grants such as new origins, large budgets, and public visibility, and they can revoke sessions (architecture §6.3; `docs/platform-project-plan.md` §5 items 2 and 7).
- **Operators** deploy one independent instance per customer into the customer's own Azure tenancy, under the customer's domain and identity provider (ADR-0028). The public docs site is written for them and for app authors (`docs/README.md` lines 6-9).
- **Contributors** work from the dev container, which runs the platform locally with a fake identity provider, Azurite for Blob, and an encrypted local secret store (`README.md`; `TOUR.md` "Deployment and local development").

The architecture doc's stated scale is "tens of apps, one org, low ops burden" (§2). The docs describe one organization per deployment, with app-id partitioning kept in place so multi-tenancy can be added later (ADR-0023).
