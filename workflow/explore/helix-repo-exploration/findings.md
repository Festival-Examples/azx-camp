# Helix: what it is, what is wrong, and what stands between it and production

_Assessed:_ `projects/helix` at `main` = `792557a`, 2026-10-08.
_Bar:_ production quality at staff-engineer level. Would a staff engineer sign off on running this for real customers, and on handing it to a team to own?
_Reading the ratings:_ **Critical** blocks production use or is an exploitable security gap. **High** is a serious risk or a major missing capability. **Medium** should be fixed before scaling the team or traffic. **Low** is polish. **Confirmed** means a reviewer opened the code or ran the command; **Hypothesis** means inferred and not yet checked.

## Bottom line

- **Helix is a well-designed, single-author platform for hosting untrusted AI-generated web apps.** It splits the work across three services by trust level (edge, portal, egress) and enforces the split in the database grants, the dependency graph, and lint rules. The design reasoning is unusually explicit: 51 ADRs, a dated backlog, and adversarial test suites.
- **The code is in good mechanical health.** Typecheck, lint, format, and the docs build pass. The last upstream CI run passed every job, including about 66k lines of tests and four image builds. `pnpm audit` is clean.
- **It is not yet production-ready for external customers, and not yet ready to hand to a team.** The blockers are mostly operational and organizational rather than code: a single-instance data tier with untested backups, no staging or rollback path, alerts wired to nobody by default, no incident runbooks, no enforced merge gate, and a bus factor of one.
- **The security design is strong, but known gaps remain open.** No Critical issue was found, and no path from a hosted app to another app's session or to a plaintext secret. But hosted apps share a registrable domain with the portal and auth hosts (upstream issue #16), and the CSP leaves an image and navigation channel open, so an app can send out anything its signed-in viewer can read. Cost controls are optional and checked after the fact, and abandoned LLM streams escape the spend gate. The edge-to-egress instruction signs only part of the request with one shared secret that has no rotation path. Both live production installs run without the egress firewall, and its rule allows every hostname anyway. Upstream issues #5 and #6 are partly stale: the hop is HTTPS in the Bicep, and `aud` and single-use `jti` are implemented.
- **The fork changes the ownership picture.** The live installs' configuration lives in a private "deployments repo" that is not part of this repository. Publishing, images, docs hosting, the npm scope, and domains all still point at AZX.

## What Helix is

Helix hosts AI-generated static web apps (HTML, JavaScript, CSS, wasm) and treats every app as untrusted code. Users sign in once through Entra ID. Each app gets its own subdomain and session cookie, and reaches platform capabilities only through a same-origin `/_api` gateway: LLM calls, per-user and shared app data, and outbound HTTP.

| Plane | Service | Role | Trust |
| --- | --- | --- | --- |
| Data/policy | `apps/edge` | Terminates app-user traffic: host routing, sessions and OIDC handoff, CSP, Blob serving, the `/_api` gateway, policy for outbound calls | Untrusted traffic, no third-party secrets, least-privilege DB role |
| Control | `apps/portal` + `apps/portal-web` | Deploy API, registry, approvals, secret writes, Prisma schema and migrations, the React SPA | Privileged, not routable from app hosts |
| Mechanism | `apps/egress` | Verifies the edge's signed instruction, injects secrets, enforces SSRF controls, calls the vendor | The only holder of plaintext secrets and internet access |

It runs on Azure Container Apps with Postgres, Blob, and Key Vault, defined in Bicep. Everything also runs locally in the dev container. The stated scale is "tens of apps, one org, low ops burden", one install per customer. Status: deployed (M5), with feature work continuing past the milestone plan. Details: [notes/01-what-it-is.md](notes/01-what-it-is.md).

## Scorecard

| Dimension | Rating | One-line verdict | Notes |
| --- | --- | --- | --- |
| Architecture and design | Strong | Trust-boundary split is real and enforced in grants, deps, and lint | [01](notes/01-what-it-is.md), [03](notes/03-decisions.md), [09](notes/09-code-quality-backend.md) |
| Security design | Adequate | Strong design with open gaps: careful auth, RLS role split, pinned-IP SSRF filter; no Critical, but two High structural gaps (shared domain, CSP exfiltration) and optional cost controls | [07](notes/07-security.md), [04](notes/04-known-problems.md) |
| Backend code quality | Strong | Uniform error handling, streaming caps, graceful shutdown; a few 800-1,000-line modules | [09](notes/09-code-quality-backend.md) |
| Frontend and CLI | Adequate | Coherent SPA and CLI; no error boundary, no 404 route, no code splitting, partial a11y | [10](notes/10-frontend-cli-docs.md) |
| Testing | Adequate | Large and adversarial, but flaky integration tests reach `main`; no portal browser E2E | [06](notes/06-health.md), [10](notes/10-frontend-cli-docs.md) |
| Change control and CI/CD | Weak | Direct pushes to `main`, no branch protection, CI now manual-only | [06](notes/06-health.md), [08](notes/08-operability.md) |
| Release and environments | Missing | No staging, no platform version tags, `imageTag` defaults to `latest`, no rollback procedure | [08](notes/08-operability.md) |
| Infrastructure resilience | Weak | Postgres HA off, no zones, LRS Blob, one replica minimum | [08](notes/08-operability.md) |
| Data protection and DR | Weak | 7-day default backups, no geo-redundancy, no restore drill, no retention policy for the ledger | [08](notes/08-operability.md), [04](notes/04-known-problems.md) |
| Observability | Adequate | Careful OTLP design and redaction tests; no SLOs or dashboards | [08](notes/08-operability.md) |
| Alerting and incident response | Weak | Alerts notify nobody by default, email only; no incident runbooks | [08](notes/08-operability.md) |
| Documentation | Adequate | Very thorough, but drifting: 10 stale or contradicted ADR records, README says "alpha" | [03](notes/03-decisions.md), [10](notes/10-frontend-cli-docs.md) |
| Developer experience | Adequate | Dev container plus `just`; tests need the container; no amd64 image builds on Apple Silicon | [02](notes/02-how-it-runs.md), [06](notes/06-health.md) |
| Ownership | Weak | One author wrote 556 of 564 commits; no CODEOWNERS, on-call, or dependency automation | [08](notes/08-operability.md) |
| Fork readiness | Weak | Builds and tests without AZX, but publishing, images, domain, Azure target, and the live installs' config all depend on AZX | [05](notes/05-fork-impact.md) |

## What is already at staff level

- **The trust boundary is enforced, not just documented.** The edge has no Prisma or `secret-store` in its runtime dependencies (`apps/edge/package.json:13-22`). ESLint bans raw SQL against RLS tables outside three store modules, bans bare `pool.connect()` on the edge, bans `propagation.extract` on edge and portal, and confines the OpenTelemetry SDK to boot files (`eslint.config.mjs:54-66, 117-279`). The `helix_edge` role has no grant on `app_secrets`, and `role-split.integration.test.ts` holds that line.
- **Decisions are recorded with their reasons.** 51 ADRs, 12 of which a new engineer must know before changing code ([03](notes/03-decisions.md) §2). The backlog is kept honest: finished items are deleted, each open item cites an ADR or issue, and the launch-critical section is empty (`TODO.md:38-43`).
- **Tests are serious.** About 66k lines of tests against about 66k lines of source; edge has more test code than source. Adversarial suites cover auth, SSRF, span redaction, and the trace boundary, and they scan every attribute of every span.
- **Failure handling is deliberate.** Opaque error bodies toward untrusted callers with tests behind them (`apps/edge/src/errors.ts:125-164`), body caps and timeouts on egress streams (`apps/egress/src/proxy.ts:592-692`), a shared graceful-shutdown contract (`packages/shared/src/lifecycle.ts:79-130`).
- **The infrastructure code is careful.** Private endpoints, per-plane managed identities, a no-credential migrate job, managed-identity Blob access, and an outside-in health probe that reads the `/health` body.
- **The SPA follows its own constraints.** Runtime config from `GET /api/v1/config` rather than build-time hosts (`apps/portal-web/src/lib/deployment.ts:32-48`), zod parsing on every API call (`apps/portal-web/src/api/client.ts:5-56`), OIDC with PKCE.

## Production blockers

Ranked by risk to running Helix for real customers. Each row links to the full finding.

| # | Blocker | Severity | Findings | Key evidence |
| --- | --- | --- | --- | --- |
| 1 | **Single-instance data tier with untested backups.** One Postgres server with HA off, no zones, LRS Blob without soft delete or versioning, and no documented or tested restore. | High | OPS-1, OPS-2 | `infra/azure/modules/postgres.bicep:66-71`: HA `Disabled`, `backupRetentionDays: 7`, `geoRedundantBackup: 'Disabled'` |
| 2 | **Alerts notify nobody by default, and there are no incident runbooks.** The action group is email-only and exists only if `alertEmails` is set, which neither parameter file does; cost budgets are skipped too. None of the 8 runbooks covers a database outage, certificate expiry, an LLM vendor outage, or an egress compromise. Certificate renewal is unmonitored with the committed defaults. | High | OPS-4, OPS-5, OPS-6 | `infra/azure/main.bicep:303` `param alertEmails array = []`; `docs/runbooks/` |
| 3 | **No staging, no pinned releases, no rollback.** Every change is tested in production. `imageTag` defaults to `latest`, there are no platform version tags, and the migrate job is manual and forward-only. | High | OPS-3 | `infra/azure/main.bicep:288` `param imageTag string = 'latest'`; `git tag` lists only `cli-v*` |
| 4 | **Nothing gates a change before it reaches `main`.** 499 of the 502 commits on `main`'s first-parent history were pushed directly rather than merged. Branch protection is not available on the private repo's plan, and CI triggers are commented out, so the adversarial security suites run only when someone dispatches CI by hand. | High | HEALTH-2, OPS-16 | `gh api repos/lancekrogers/helix/branches/main/protection` → HTTP 403; `.github/workflows/ci.yml:57-65` |
| 5 | **Hosted apps share a registrable domain with the auth host and portal.** Untrusted app pages sit under the same eTLD+1 as login and the control plane, enabling cookie-bomb denial of service and lookalike phishing. Open upstream as issue #16. | High | SEC-1, KP-1 | [07](notes/07-security.md) SEC-1 |
| 6 | **An app can send out anything its signed-in viewer can read.** The CSP allows images from any HTTPS host and top-level navigation, plus `'unsafe-inline' 'unsafe-eval'` and five public script CDNs. `connect-src` is tight, but the image and navigation channels are open. The repo documents this as an accepted residual. | High | SEC-2 | `apps/edge/src/serving/csp.ts:68` `img-src https: data: blob:` |
| 7 | **Spend and capacity controls can be bypassed or are off.** Egress passes no abort signal to the vendor call, so a hang-up before the vendor's first byte does not stop the call, and any cut stream is recorded in the ledger at $0. (Corrected 2026-10-08 by the design review: after the first byte, the response pipeline probably already tears the vendor call down; see `workflow/design/helix-spend-containment-egress/00-frame.md`.) Budgets are optional (unset means unlimited), checked after the fact, per app only, with no platform-wide ceiling or concurrency cap. | High | KP-2, SEC-4, OPS-14 | `apps/egress/src/proxy.ts:606-611` (no `signal`); `TODO.md:58` |
| 8 | **Bus factor of one, and the live configuration is not in this repo.** One author wrote 556 of 564 commits. Operational knowledge lives in a 1,340-line infra README and ADR amendments. The live installs' parameters and accepted risks live in "the operator's private deployments repo". | High | OPS-12, FORK-3 | `docs/adr/0005-*.md:79-87`; no CODEOWNERS; `wc -l infra/azure/README.md` = 1340 |
| 9 | **Portal authorization is owner-or-admin, and reads are open to any signed-in user.** There are no per-app roles. This is acceptable for one trusted org and a blocker before outside app owners. | High before a second tenant | CQ-8, SEC-8, KP-3 | `apps/portal/src/plugins/auth.ts:22-24`; ADR-0007 |
| 10 | **No real network egress control in production.** Both live installs run with `deployFirewall = false` (an accepted cost decision), the firewall rule allows every FQDN when it is on, and there are no NSGs behind the SSRF filter. Destination control is the application-level filter in `apps/egress/src/ssrf.ts` alone. | Medium | OPS-9, SEC-7, [03](notes/03-decisions.md) S10 | `infra/azure/modules/firewall.bicep:108` `targetFqdns: ['*']`, `:84` `threatIntelMode: 'Alert'` |
| 11 | **Platform secrets cannot be rotated and are broadly readable.** The instruction-signing key is one HS256 secret shared by edge and egress, with no `kid` or rotation path. Anyone with Contributor on the resource group can read every platform secret. | Medium | SEC-6, OPS-10 | `infra/azure/README.md` "Known deploy gotchas"; [07](notes/07-security.md) SEC-6 |

## Gaps to staff-level engineering

These are not launch blockers, but a staff engineer would expect them before a team owns the system.

- **Testing.** Flaky integration tests reach `main`; the clearest is `connectionsJourney.integration.test.ts`, which failed on a docs-only commit (HEALTH-1). The portal has no browser end-to-end tests (only jsdom), examples are not built or checked by the gate (FE-7), and no matrix links each claimed security mitigation to the test that holds it ([07](notes/07-security.md), Missing).
- **Security hardening.** The handoff token is not bound to the browser that started login, which allows login CSRF (SEC-3). The signed instruction leaves query and body unsigned and its method and path claims optional (SEC-5). Internal hops have no client authentication or scheme guard (SEC-11). Shared-password apps use an IP-keyed throttle and an unbounded KDF queue (SEC-9). Images and CI actions are not pinned by digest or signed (SEC-10). Production guards depend on `NODE_ENV` alone (SEC-12). No independent review of the OIDC handoff is recorded.
- **Code structure.** A few 800-1,000-line modules mix wiring, policy, and handlers: `apps/edge/src/config.ts` (902), `apps/edge/src/app.ts` (832), `apps/portal/src/routes/providers.ts` (1,007) (CQ-1). The RLS lint rule allows three files rather than proving each query runs inside `withPartition` (CQ-2). The dev gateway duplicates the consent flow (CQ-5).
- **Resilience details.** One replica minimum for edge, egress, and the collector, with untuned probes (OPS-7). An edge replica that boots during a database outage serves 503 for every app (OPS-15). Gateway metering is fire-and-forget with no alert on write failures (CQ-4).
- **Frontend.** No React error boundary (FE-2), unknown routes fall through to the apps list (FE-1), no route-level code splitting (FE-3), accessibility is spot fixes rather than a standard (FE-10).
- **Observability.** Instrumentation is careful, but there are no SLOs, dashboards, or capacity model (OPS-11).
- **Data lifecycle.** The `gateway_calls` ledger has no retention or erasure path (KP-7, OPS-13).
- **Documentation drift.** Ten ADR records contradict the code or each other ([03](notes/03-decisions.md) §3). The README says "alpha" while the platform runs in production (FE-11). `examples/README.md:67-72` says the CLI is unpublished (FE-4). `infra/azure/README.md:655-658` says CI publishes on push. The `ci.yml` header still says the repo is public and minutes are free, which contradicts the note PR #1 added below it ([02](notes/02-how-it-runs.md) §6). `build-images.sh` is stale and should go.
- **Dependencies.** 9 packages are a major version behind, including `undici` on the outbound path (HEALTH-3). There is no Dependabot or Renovate configuration in the fork (OPS-12).
- **Developer experience.** Tests need the dev container (HEALTH-4). `.env.example` omits the TLS variables the edge needs to boot (02 §6.4). Dev container tools are unpinned (02 §6.5). Host `pnpm` cannot switch to the pinned 11.5.3 on this Mac.

## Missing entirely

- A staging environment and a promotion path to production.
- A disaster-recovery plan with stated RPO and RTO, and a restore drill on record.
- On-call and escalation, with each alert linked to a runbook.
- SLOs, dashboards, and a capacity model.
- An enforced merge gate and a review requirement.
- A written production or GA gate: the list of items that must close before outside customers ([04](notes/04-known-problems.md), Missing).
- A secret and key rotation procedure that has been exercised.
- Image integrity: digest pinning, SBOM, signing.
- Browser end-to-end tests for the portal.
- A threat-model-to-test traceability matrix, and a recorded independent security review.
- A second maintainer, CODEOWNERS, and dependency update automation.
- A fork operator guide: your domain, image registry, npm scope, and Azure target.
- A customer-facing statement of the trust model, including what an app can send out (SEC-2) and what a password app protects (SEC-9).

## Decisions the owner has to make

1. **Audience.** Is Helix for one trusted organization (the pilot posture), or for outside app owners and customers? This sets the priority of blockers 5, 6, 7, and 9.
2. **Access to the live installs.** Get the private deployments repo and Azure access for the existing installs, or treat this fork as a new install with its own Azure target (FORK-3, blocker 8).
3. **Fork identity.** Keep or replace the `azxlabs.io` domain, the `@azx-pbc` npm scope (or stop publishing the CLI from the fork), the `ghcr.io/azx-pbc-oss` image default, GitHub Pages for docs, and the security contact (FORK-1 to FORK-6).
4. **Upstream relationship.** Add a fetch-only `upstream` remote and keep tracking issues #6 and #16, or cut ties (FORK-7).
5. **CI budget.** Which gate to pay for. The minimum that closes blocker 4 is the static checks plus the security suites on every pull request, or a local pre-push hook if Actions stays off (HEALTH-2, FORK-9).
6. **Accepted risks to re-confirm.** Firewall off in production (ADR-0005), the CSP image and navigation channel (SEC-2), and the egress response-body echo (CQ-3).
7. **Licensing and attribution** for new work on the fork (FORK-8).

## Recommended next steps

Proposed dispositions, following the camp's sizing rules. Nothing here has been created yet.

**Small, actionable now (camp intents):**

- Restore an enforced gate: `just check static` plus the adversarial security suites on pull requests, or a pre-push hook while Actions stays off.
- Propagate client disconnects through egress to the vendor call, with a test that drops streams and checks the ledger (KP-2).
- Fix the race in `apps/edge/src/routing/connectionsJourney.integration.test.ts` (HEALTH-1).
- Set `alertEmails` for any live install and add runbooks for the four uncovered failure modes (OPS-4, OPS-5).
- Documentation sweep: ADR status lines and index, README status banner, `examples/README.md` CLI section, infra README CI wording, the `ci.yml` header, and removing `build-images.sh`.

**Needs a decision first (`workflow/design/` documents):**

- Production topology and recovery: HA Postgres, zones, backup retention and geo-redundancy, Blob protection, restore drill, staging, release tagging and rollback.
- Hosted-app isolation: moving apps to their own registrable domain (#16) and the CSP posture (SEC-1, SEC-2).
- Cost and abuse controls: required budgets, a platform-wide spend ceiling, concurrency caps (SEC-4, OPS-14).
- Fork identity and ownership plan (decisions 2 to 4).
- Per-app portal roles (CQ-8), as a new ADR.

**Multi-phase work (a festival), once the decisions above are made:**

- `helix-production-readiness`, phased roughly as change control, then release and environments, then resilience and recovery, then security hardening, then ownership and handoff. Plan it through the `fest next` loop rather than scaffolding it up front.

## Notes index

| File | Contents | Produced by |
| --- | --- | --- |
| [00-seed-observations.md](notes/00-seed-observations.md) | First observations while repointing the fork and adding the justfile | Coordinator |
| [01-what-it-is.md](notes/01-what-it-is.md) | Summary, component map, request flow, milestone status vs git history, users | Claude Haiku subagent |
| [02-how-it-runs.md](notes/02-how-it-runs.md) | Prerequisites, local dev, gate, CI/CD map, build and deploy, DX gaps | Claude Haiku subagent |
| [03-decisions.md](notes/03-decisions.md) | ADR index, load-bearing decisions, stale or contradicted ADRs, ADR gaps | Claude Haiku subagent |
| [04-known-problems.md](notes/04-known-problems.md) | Backlog map of 52 open TODO items, reviews, upstream issues, branches (KP-) | Claude Sonnet subagent |
| [05-fork-impact.md](notes/05-fork-impact.md) | What is tied to AZX and what the private fork changes (FORK-) | Claude Haiku subagent |
| [06-health.md](notes/06-health.md) | Gate results, CI history and flaky tests, audit, dependency drift (HEALTH-) | Coordinator |
| [07-security.md](notes/07-security.md) | Security and trust-boundary review (SEC-) | Claude Sonnet subagent |
| [08-operability.md](notes/08-operability.md) | Topology, data, release, secrets, networking, observability, incidents, cost, ownership (OPS-) | Claude Sonnet subagent |
| [09-code-quality-backend.md](notes/09-code-quality-backend.md) | Backend architecture and code quality (CQ-) | cursor-agent, `composer-2.5` |
| [10-frontend-cli-docs.md](notes/10-frontend-cli-docs.md) | Portal SPA, CLI, examples, docs (FE-) | cursor-agent, `composer-2.5` |

## Method and confidence

- **Who did what.** Seven reviewers worked in parallel from one shared brief: two Claude Haiku subagents (inventory and indexing), three Claude Sonnet subagents (known problems, security, operability), and two cursor-agent runs on `composer-2.5` (backend code quality; frontend, CLI, and docs). The coordinator ran the gates and CI history, wrote the health note, and wrote this synthesis.
- **How claims were checked.** Every finding in the notes cites `path:line` or a command. The coordinator did not re-check every finding. It re-opened the evidence for at least one claim behind each of the 11 blockers: Postgres HA, retention and geo settings; `alertEmails = []`; `imageTag = 'latest'` and the tag list; the 403 on branch protection and the commented-out triggers; the shared `azxlabs.io` domain in `main.bicepparam` and ADR-0019; the CSP `img-src`; the missing abort signal; the ADR-0005 accepted-risk record; `ownsApp` in the portal auth plugin; the firewall's `targetFqdns: ['*']`; and the instruction JWT header with no `kid`. It also re-opened 10 claims from the cursor-agent reviews, the security review's corrections to upstream issues #5 and #6, and every line range cited under "What is already at staff level". All matched. Two citation errors were found and fixed in the notes: line numbers attributed to the root `README.md` that belong to `infra/azure/README.md`, and a commit count.
- **What was not run.** The full test suite and browser lane locally (they need Postgres, Azurite, and xvfb; upstream CI results stand in), any deployment or `az` command, and anything against the live installs. Claims about live production come from the repository's own records, such as ADR-0005.
- **Line anchors** refer to `main` at `792557a`, except in `00-seed-observations.md`, which uses `24e4b32`.
