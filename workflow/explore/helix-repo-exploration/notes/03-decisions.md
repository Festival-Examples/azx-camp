# Architecture decisions

_Repository:_ `/Users/lancerogers/campaigns/azx/projects/helix`, branch `main` at `792557a` (2026-10-08).
_Method:_ read every file in `docs/adr/`. The directory holds 50 numbered ADRs and `README.md`, which is the index, so the "51 entries" in the brief is 50 ADRs plus the index. For each ADR I read the title, the status line, and the decision section (the first 28 lines of the section in most cases, which was enough for every claim below). Where an ADR has an amendment or resolution section, I noted its presence and read it only where a claim below depends on it. Also checked against `docs/platform-architecture.md`, `docs/platform-project-plan.md`, `AGENTS.md`, `README.md`, `TOUR.md`, `TODO.md`, and `pnpm-workspace.yaml`, and ran read-only `git` and `grep` commands. Nothing in the repository was changed.

## 1. ADR index

"Status" is copied from each ADR's own status line, shortened where the line is long. The index in `docs/adr/README.md` is compared in section 3.

| Number | Title | Status (as written in the ADR) | Superseded by / amends | One-line decision |
|---|---|---|---|---|
| 0001 | Three-runtime split along trust boundaries | Accepted | Co-deploy allowed by 0012; seam hardened by 0013 | Edge, portal, and egress run as separate containers along the trust boundary, and egress is always separate. |
| 0002 | Postgres least-privilege role split + RLS | Accepted; has an amendment section (not read) | - | Each runtime has its own Postgres role, the edge has no grant on secrets, and app data is row-level secured by session settings. |
| 0003 | Dependency-minimal edge, hand-written SQL (no ORM) | Accepted | - | Every runtime dependency in the edge needs review, and database access is hand-written parameterized SQL. |
| 0004 | Edge-terminated auth: OIDC handoff + password visibility | Accepted; has an amendment section (not read) | - | The edge runs the central OIDC login, issues a 30-second single-use handoff token, sets `__Host-` cookies, and offers password visibility. |
| 0005 | Egress SSRF + secret-injection mechanism | Accepted; amended 2026-08-04 (`hmac-timestamp` recipe) | Amended in place | Egress checks each resolved IP, dials that IP directly, does not follow redirects, and filters headers in both directions. |
| 0006 | `SecretStore` custody seam (dev envelope / prod Key Vault) | Accepted (amended 2026-07-29, Key Vault wired) | Amended 2026-07-29 | One `seal`/`open`/`destroy` interface, with an AES-GCM envelope in dev and Key Vault references in production. |
| 0007 | Portal authorization v0: authenticated == authorized | Accepted; gap closed by the `ownsApp` gate; amended 2026-08-10 and 2026-09-22 | Amended 2026-08-10, 2026-09-22 | Mutating routes require the app owner or an admin. Per-app owner, editor, and viewer roles are still not built. |
| 0008 | LLM vendor key resolved by egress (legacy fallback removed) | Accepted; amended 2026-07-20 | Amended 2026-07-20 | The vendor key is a platform secret that egress resolves and injects, and the edge never holds it. |
| 0009 | Relaxed CSP posture for hostile app code | Accepted (revisit: supply-chain hardening) | - | CSP limits where app data can go and allows inline and `eval` code plus a fixed CDN list. |
| 0010 | Anonymous writes to `shared` keys on public apps | Accepted (revisit: threat model) | - | Public apps may write `shared` keys without a login, limited by a key allowlist and a daily write budget. |
| 0011 | In-memory rate-limit / throttle state (single-replica) | Superseded (2026-07-21) | Superseded by shared Postgres counters (named in the ADR's Resolution; no ADR number) | Per-process counters for a single replica, replaced by counters in Postgres. |
| 0012 | Edge and portal may co-deploy as one binary in v0 | Accepted; has an amendment note (not read) | Relied on by 0001 | Edge and portal may share one binary in v0. Egress never does. |
| 0013 | Egress trust model: harden the attested-instruction seam | Accepted (direction 2026-06-26); step 1 shipped 2026-07-21; step 2 partly; step 3 open | Steps tracked in the ADR's Resolution | Instructions gain a one-time `jti` and an audience, bind method and path, and later move from a shared secret to asymmetric signing. |
| 0014 | Same-origin `/_api/*` gateway as the single capability choke point | Accepted (recorded retroactively) | - | The whole gateway sits at `/_api/*` on each app's own origin, so apps need no CORS and no bearer token. |
| 0015 | App-data: three scopes (user / collection / shared), writer ≠ reader | Accepted (recorded retroactively) | - | Three data scopes, and a write grant never implies a read grant. |
| 0016 | Capability manifest + baseline/elevated approval classifier | Accepted (recorded retroactively) | - | Baseline manifest changes apply immediately, and elevated changes wait for platform-admin approval. |
| 0017 | Edge registry projection over Postgres LISTEN/NOTIFY | Accepted (recorded retroactively) | - | The edge keeps an in-memory copy of the registry, refreshed by LISTEN/NOTIFY and a periodic full reconcile. |
| 0018 | Deploy model: upload-only, immutable versions, preview→live pointer flip | Accepted (recorded retroactively) | - | Deploys upload immutable versions as previews, and promotion or rollback is one pointer flip. |
| 0019 | Subdomain-per-app isolation with host-scoped cookies | Accepted (recorded retroactively); has an amendment section (not read) | - | Each app has its own subdomain, and host-only `__Host-` cookies keep the sessions apart. |
| 0020 | Static-only hosted apps in v1 | Accepted (founding constraint) | - | Hosted apps are static files, and every dynamic capability goes through the platform gateway. |
| 0021 | Metering/audit ledger: `gateway_calls`, append-only | Accepted (recorded retroactively); has an amendment section (not read) | - | Each gateway call writes one append-only row with a frozen cost. Quotas block the next request, not the one in flight. |
| 0022 | Self-hosted edge/auth, not a cloud-vendor edge | Accepted (founding build-vs-buy) | - | The proxy, auth, CSP, and gateway are Helix code, not a vendor front door. |
| 0023 | One org now, app-id partitioning everywhere | Accepted (forward-compatibility) | - | One organization for now, with every table and grant keyed by app id so an org level can be added later. |
| 0024 | Portal/CLI authentication: bearer JWT verified over JWKS | Accepted (recorded retroactively) | - | Portal mutations accept bearer JWTs verified statelessly against the issuer's keys, and the CLI uses a device-code login. |
| 0025 | Registry projection hardening (observability, jitter, cold-start) | Accepted (2026-06-26); items 1-2 implemented 2026-07-31; 3-5 open | - | A list of hardening items for the registry projection, in priority order. |
| 0026 | Hosted-build isolation prerequisites | Accepted (2026-06-26); displaced in practice by 0030 | Displaced by 0030 in practice, not superseded | If hosted builds ever ship, four launch gates must hold first. Nothing is built, because no builder exists. |
| 0027 | Blob authentication: managed identity, not the storage account key | Accepted (2026-07-20) | Resolves the P0 raised in 0001 | Both planes authenticate to Blob with managed identity, and the account key is never placed in a container. |
| 0028 | Deployment model: single-tenant, customer-deployed | Accepted (2026-07-22); has an amendment note (not read) | Parameterizes architecture decision 11 and reframes 0019 | Each customer runs an independent instance in its own cloud, under its own domain and identity provider. |
| 0029 | Platform secret delivery: deployment-injected env vars, not ACA Key Vault references | Superseded in part (2026-09-17) | Delivery half reversed by its own Update. App-contract half and 0006 still stand. | Platform secrets reach containers as environment variables set at deploy time. The index lists this as Accepted. |
| 0030 | Repo-backed apps: pull CI-built attested artifacts (no hosted build) | Proposed (2026-07-27) | Displaces 0026 in practice | Repo-backed apps are pulled as attested OCI artifacts that CI publishes, and Helix never builds code. |
| 0031 | Connection providers: MCP-first delegated auth, tenant-key as fallback | Accepted (2026-09-25); phases 1-4 implemented, 5-7 future | Amended 2026-08-04, 2026-09-25, 2026-09-28 | A provider catalog that prefers delegated auth, with tenant keys as a policy-bound fallback. The index lists this as Proposed. |
| 0032 | CLI naming (`helix`) and distribution (public npm, bundled) | Accepted (2026-07-30); has an amendment note (not read) | - | The binary is `helix`, the package is `@azx-pbc/helix-cli`, and it is published to public npm. |
| 0033 | OpenAI-compatible gateway surface and multi-provider routing | Accepted; section 3 amended by 0034 | Amended by 0034 | An OpenAI-compatible surface sits beside the native one, behind a wire-codec seam, for text chat only. |
| 0034 | Structured output on the LLM gateway (both surfaces) | Accepted; amends 0033 section 3 | Amends 0033 | `json_schema` structured output is served on both surfaces and is always enforced. |
| 0035 | Offline capability: platform-owned, scope-confined service worker | Accepted (implemented 2026-08-04/05; amended twice in the file) | Reverses the platform-wide service-worker ban for one named exception | Apps can get a platform-authored service worker limited to a non-root path. Apps never ship their own. |
| 0036 | Deployment capability catalogue: authed instance endpoint, deployment-agnostic public docs | Accepted; decision 7 (public docs site) marked deferred | - | An instance-wide catalogue endpoint, plus docs written so they hold for any deployment. |
| 0037 | Platform observability: OpenTelemetry behind an OTLP-only boundary | Accepted (phase 1 shipped; see Amendments) | Nine amendments in the file: numbered items 1-7, then two headed subsections both titled "Amendment 7" and "Amendment 8" (the numbering collides) | Services export only OTLP, and only `packages/telemetry` imports an SDK. The backend is chosen in `infra/`. |
| 0038 | Malformed upload bundles: salvage in the portal SPA, contract unchanged | Accepted; "implementation not yet started" | - | Bundle salvage happens in the portal's browser code, and the upload contract stays a zip of the build directory's contents. |
| 0039 | Pending approval requests do not expire | Accepted (2026-08-13) | - | Approval requests stay pending until a person approves, denies, asks for changes, or withdraws them. |
| 0040 | Group visibility: security groups, one admin-consented Graph permission, behind a directory seam | Accepted; amended 2026-08-25 (decision 11) | Amended 2026-08-25 | Security groups are the visibility source, read through one Graph permission behind a seam with no member-listing method. |
| 0041 | App-data write concurrency: compare-and-swap on an opaque version, mandatory on `shared` | Accepted (2026-08-24); amended 2026-08-25 | Amended 2026-08-25 | Writes carry an opaque version, and `shared` writes must send a precondition. |
| 0042 | Prefix grants on `shared` app-data, with a list verb | Accepted; implemented 2026-09-03; has an amendment section (not read) | - | Prefix grants and a keys-only list verb on `shared`, approved as their own elevated category. |
| 0043 | App-data identifiers are printable ASCII | Accepted (2026-09-03) | - | Keys, collection names, and grant prefixes are printable ASCII, 1 to 256 characters. |
| 0044 | Declarative wildcard TLS custom-domain bindings | Accepted (2026-09-04) | - | TLS bindings are declared in the Bicep template, behind a one-time bootstrap flag. |
| 0045 | App-triggered durable jobs: a platform-owned plane behind an HTTP contract | Proposed (2026-09-11) | - | A fourth service, `helix-jobs`, runs platform-owned job types behind an HTTP contract, and apps never supply code. |
| 0046 | Azure AI Foundry as a keyless LLM backend | Accepted | Relates to 0008, 0033 | Egress mints a managed-identity token per call for an allowlisted connection, pinned to one host. |
| 0047 | Operator-declared servable model set (allowlist/blocklist), catalogue-side only | Accepted | Amends the catalogue scope of 0036 | Operator variables narrow the servable model list. They can never extend it. |
| 0048 | Canonical principal identifier: the Entra `oid` claim, captured at source in both planes | Accepted (2026-09-21); amendment selects a straight cutover | Amendment section (not read) | The canonical user id is the Entra `oid` claim. A token without it fails login, and there is no fallback to `sub`. |
| 0049 | Warden as an optional inference backend | Proposed (2026-10-01; amended 2026-10-02) | Phase 2 deferred | Warden can be an optional upstream. Helix keeps pricing, budgets, and authorization in both modes. |
| 0050 | Visitor analytics for hosted apps | Accepted (2026-10-02) | - | Each HTML document load writes a keyed, truncated visit record to Postgres. Locations come from an offline file in the portal. |

## 2. Load-bearing decisions

Twelve decisions that a new engineer must know before changing code. Each is a single sentence on why, with the ADR that holds it.

1. **Three planes, and egress is always its own container.** A compromise of the public-facing edge should reach no connection secret and no arbitrary internet route. (ADR-0001, ADR-0012)
2. **The edge has no grant on `app_secrets`, and its database role is `NOBYPASSRLS`.** This grant absence is what limits what an edge compromise can dump. Keep it true in any change, and keep `role-split.integration.test.ts` passing. (ADR-0002; `AGENTS.md` lines 33-34)
3. **Connection and vendor secrets are read only by egress, through the `SecretStore` seam.** One seam means dev and production differ only in the custody backend, and the edge never holds a vendor key. (ADR-0006, ADR-0008)
4. **Egress checks each resolved IP, dials that IP directly, and does not follow redirects.** DNS rebinding and a redirect to a metadata endpoint are the two main SSRF routes, and both are closed here. (ADR-0005)
5. **The edge stays dependency-minimal, with hand-written SQL and no ORM.** Every package in the edge runs inside the trusted path, so each addition needs a review. (ADR-0003)
6. **Each app gets its own subdomain and host-only `__Host-` cookies. Path-based routing is not an option.** Apps on a shared origin could read one another's sessions and storage. (ADR-0019; `docs/platform-architecture.md` section 9, decision 2)
7. **The `/_api/*` gateway on the app's own origin is the only route to platform capabilities.** One choke point gives one place for auth, budgets, and audit, and it avoids CORS and bearer tokens in app code. (ADR-0014)
8. **Elevated grants wait for platform-admin approval, and the edge sees only effective settings.** The classifier is the single gate for privilege changes, and it has to stay in one place. (ADR-0016; ADR-0039 for why requests never expire)
9. **Deploys create immutable versions that start as previews, and a person promotes them.** Agent-driven deploys can be steered by untrusted content, so the promotion step is the guardrail. (ADR-0018; `docs/platform-architecture.md` section 5.1)
10. **The `gateway_calls` ledger is append-only, and quotas block the next request, not the one in flight.** Spend and audit have to reconcile, and a stream must not be cut off mid-answer. (ADR-0021)
11. **Blob access uses managed identity. The storage account key stays out of every container.** An account key in the edge would let an edge compromise rewrite every app's bundle. (ADR-0027, and the escalation note in ADR-0001)
12. **The canonical user id is the Entra `oid`, with no fallback to `sub`.** `sub` is pairwise per client, so keying user data on it splits one person into several identities. (ADR-0048)

## 3. Possibly stale or contradicted

Each item is marked Confirmed (I read both sides of the conflict) or Hypothesis (inferred, not fully checked).

**S1. ADR-0038 says implementation has not started. It has.** Status: **Confirmed.**
- Evidence: `docs/adr/0038-bundle-salvage-in-the-portal-spa.md` line 3 says "Accepted — reviewed and agreed; implementation not yet started." The repository has `packages/shared/src/bundlePlan.ts`, `apps/portal-web/src/deploy/archive.ts`, and `apps/portal-web/src/deploy/UploadStep.tsx`. Commits `d7446b9` (pure planner), `c364e2d` (folder and zip drop with in-browser salvage), and `b18a6b3` (planner fixes) all landed on 2026-08-17.
- Action: change the status line to reflect what shipped, and record which decisions are still open.

**S2. ADR-0036 defers the public docs site. The site exists.** Status: **Confirmed.**
- Evidence: ADR-0036 status (lines 6-7) and decision 7 (line 156 onward) say the site build is not built. `apps/docs/` exists with `package.json` and `src/`. `.github/workflows/docs.yml` exists. `AGENTS.md` line 45 says the site is published to GitHub Pages. `docs/README.md` lines 6-9 say the site uses the generic render from ADR-0036 decision 7.
- Action: change the status to say decision 7 is implemented, and cite where the site's build is defined.

**S3. ADR-0001's decision text still describes the edge holding the Blob account key.** Status: **Confirmed.**
- Evidence: `docs/adr/0001-three-runtime-split.md` line 17 says the edge "does hold its own operational secrets — the Blob account key…". ADR-0001's escalation section (lines 36-40 of the same file) raised that key as a P0. ADR-0027 (2026-07-20) removed it: the edge uses managed identity, and the account key is never injected into any container. `docs/platform-architecture.md` lines 82-83 describe the managed-identity design.
- Action: edit the decision parenthetical to match ADR-0027, and link ADR-0027 from it.

**S4. The architecture doc cites a superseded ADR for current behavior.** Status: **Confirmed.**
- Evidence: `docs/platform-architecture.md` lines 84-85 say "Rate counters are shared through Postgres ([ADR-0011])". ADR-0011's status is "Superseded (2026-07-21)". `docs/platform-project-plan.md` line 147 cites ADR-0011 the same way. The current behavior is described by ADR-0011's Resolution section, which is not a separate ADR.
- Action: cite the Resolution or a new ADR. Do not cite a superseded decision as the source of current behavior.

**S5. Index entry for 0029 disagrees with the file.** Status: **Confirmed.**
- Evidence: `docs/adr/README.md` lists 0029 as "Accepted". The file's status line says "Superseded in part (2026-09-17)" and reverses the delivery mechanism.
- Action: correct the index row.

**S6. Index entry for 0031 disagrees with the file.** Status: **Confirmed.**
- Evidence: `docs/adr/README.md` lists 0031 as "Proposed". The file says "Accepted (2026-09-25)", with phases 1-4 implemented and the 2026-09-28 amendment implemented.
- Action: correct the index row.

**S7. Index entry for 0007 drops the note that the gap was closed.** Status: **Confirmed.** Minor.
- Evidence: the index says "Accepted (revisit before multi-tenant)". The file says the "authenticated == authorized" gap is "closed" by the `ownsApp` gate, and it adds a 2026-08-10 amendment for reads.
- Action: update the index to match the file's current state.

**S8. ADR-0037 says six amendments; the section has nine, and the numbering collides.** Status: **Confirmed.**
- Evidence: the status paragraph (lines 3-9) says "six things the implementation found". The Amendments section starts at line 277 with numbered items 1-7 (items 1-7 at lines 283, 301, 306, 317, 325, 334, 343). It then adds `### Amendment 7` (line 362, about decision 2's route) and `### Amendment 8` (line 420). The headed "Amendment 7" is a different topic from numbered item 7, so a reference to "Amendment 7" is ambiguous.
- Action: change the status count to nine, and renumber the headed subsections so they do not reuse 7 and 8.

**S9. ADR-0037 decision 2 still reads as the preferred route, which Amendment 7 rejects.** Status: **Confirmed.** Reading hazard, not a contradiction.
- Evidence: decision 2 names the Container Apps managed OpenTelemetry agent as "the first choice." Amendment 7 (line 362 onward) says it "is not viable" for two reasons. `infra/azure/main.bicep` lines 782-788 record the same finding, and lines 816 and 827 deploy the OTel collector module instead.
- Action: mark decision 2 as superseded by Amendment 7 at the point where it is written.

**S10. ADR-0005 says production must keep the egress firewall. Both current production installs run without it.** Status: **Confirmed.**
- Evidence: the "Deployment note (2026-07-23, `deployFirewall`)" section of ADR-0005 (lines 64-77, not the Decision section) says "production and untrusted/multi-tenant hosting must keep it (or an equivalent network egress control)." The same note's "Accepted-risk record (2026-09-22)" says "both current production installs run with `deployFirewall = false`." The repository's parameter files set `deployFirewall = true` (`infra/azure/main.bicepparam:47`, `infra/azure/main.bicep:372`). The live installs' parameters are not in this repository.
- Action: keep the accepted-risk record, and make the production requirement say what the accepted exception is. The plan (lines 74-77) still lists the firewall confirmation as an open M5 item, which `TODO.md` no longer does.

**S11. The architecture doc says edge and portal have no outbound internet route. The accepted-risk record says that depends on the firewall.** Status: **Confirmed.**
- Evidence: `docs/platform-architecture.md` line 117 says "the edge and portal run with no outbound internet route." ADR-0005's Deployment note says turning `deployFirewall` off means "letting the edge reach the internet directly." The `TODO.md` item removed in commit `62c7f24` said that with the firewall off, "the app subnets keep default internet egress."
- Action: state the condition in the architecture doc.

**S12. The README calls the project alpha. AGENTS.md and the architecture doc call it production.** Status: **Confirmed.**
- Evidence: `README.md` opens with "Alpha — not yet suitable for public consumption … has not been hardened for production or third-party use." `AGENTS.md` line 19 says "The three planes run in production on Container Apps against real Entra OIDC." `docs/platform-architecture.md` line 3 says the implementation "is deployed on Azure."
- Action: state one current status, with the date, in all three.

**S13. The plan and the architecture doc do not mention ADR-0045 through ADR-0050.** Status: **Confirmed.**
- Evidence: among ADRs numbered 0038 and above, `docs/platform-project-plan.md` and `docs/platform-architecture.md` cite only ADR-0048 (checked with grep). The plan was last committed on 2026-09-24 (`767c96b`), and ADR-0049 and ADR-0050 were written on 2026-10-01 and 2026-10-02.
- Action: add a section to the plan that lists the post-M5 decisions and their status.

**S14. ADR-0007 says reads are now gated for per-subject data. The architecture doc says reads remain authenticated-only.** Status: **Hypothesis.**
- Evidence: `docs/platform-architecture.md` section 7 (around line 321) says "reads remain authenticated-only, so any authenticated principal can still see any app's metadata." ADR-0007's status line (2026-08-10 amendment) extends the owner gate to "reads that return per-subject data." Both can be true if the architecture doc refers only to app metadata. I did not open the portal read routes to check which reads are gated.
- Action: confirm which reads are gated, then make both documents say the same thing.

**Checked and consistent (no conflict found).** These ADRs are marked Proposed, and I looked for code that would contradict that status. I did not find any:
- ADR-0049 (Warden). The only mentions in `apps/` are comments, at `apps/edge/src/server.ts:215`, `apps/edge/src/gateway/provider.ts:230`, `:274`, `:525`, and `apps/edge/src/config.ts:179`. No Warden client exists.
- ADR-0030 (repo-backed apps). No GHCR or attestation code in `apps/` or `packages/` `.ts` files.
- ADR-0045 (durable jobs). No `helix-jobs` or `/_api/jobs` code in `apps/` or `packages/` `.ts` files.

## 4. Gaps

Significant decisions visible in the code or docs that have no ADR.

**G1. The portal's persistence stack has no decision record of its own.** Confirmed for the title check; Hypothesis for the bodies.
- What: Prisma 7 with a `pg` driver adapter; the portal owns the schema and migrations; migrations run as a separate owner role and as an ACA job.
- Where: `docs/platform-project-plan.md` section 1 (lines 13-14); section 4 M5 (line 104); `docs/platform-architecture.md` section 3 and the roles table. No ADR title names Prisma or the portal's ORM. Prisma appears in seven ADR files, and I did not read those bodies, so one of them may record part of the decision. The stack is decided only in `docs/platform-project-plan.md` section 1 as far as I checked.

**G2. The portal SPA's frontend stack has no decision record.** Confirmed.
- What: Vite, React 19, Mantine, TanStack Query, React Router, and the decision that the SPA is the only package on `moduleResolution: bundler`.
- Where: `docs/platform-project-plan.md` section 1 (line 15); `AGENTS.md` line 27. Mantine appears in zero ADRs.

**G3. The dev-gateway and its `env=dev` tier have no decision record.** Hypothesis.
- What: an isolated development tier on the same app, served through `dev-api` by the `helix_dev` role, with separate tokens and secrets.
- Where: `README.md` ("Develop an app against Helix (dev mode)" and the `pnpm dev:devgw` command). `helix_dev` appears in two ADRs, and the dev gateway is mentioned in five. I checked the titles and counts, not the bodies, so I cannot say whether one of them records the decision.

**G4. Images come from public GHCR, not a private registry.** Confirmed.
- What: the platform's container images are published to public GitHub Container Registry, not to a private Azure Container Registry.
- Where: `docs/platform-project-plan.md` line 104 lists it as a change made beyond the original scope. Only ADR-0030 mentions GHCR, and that ADR is Proposed and about app artifacts.

**G5. CI is manual-only, and no ADR records the decision.** Confirmed.
- What: automatic triggers were commented out on 2026-10-08 (commit `11b4f14`) to save Actions minutes. CI runs only when dispatched by hand.
- Where: `AGENTS.md` lines 61-63 describe it. The commit is the only other record.

**G6. The dependency-override policy has no decision record.** Confirmed.
- What: `pnpm-workspace.yaml` forces patched versions of several transitive packages (`brace-expansion`, `deepmerge-ts`, `mysql2`, `vite`) through `overrides`, with the reasoning in comments. Some comments say when to remove an override.
- Where: `pnpm-workspace.yaml` lines 22-62. The rule of "patch transitive dependencies through the workspace" is not in any ADR.

**G7. The zero-runtime-dependency rule for `packages/secret-store` is stated only in `AGENTS.md`.** Confirmed as to location; Hypothesis as to ADR coverage.
- What: `packages/secret-store` and `packages/directory` hand-roll their Azure and Graph REST calls over global `fetch`, so the edge-adjacent mechanism plane takes no SDK dependency.
- Where: `AGENTS.md` line 32. ADR-0040 covers the directory package. I did not read ADR-0006 closely enough to say whether it states the same rule.

**G8. Per-user caps are deferred to a separate ADR that does not exist yet.** Confirmed.
- What: ADR-0049 says per-user caps "are built natively in Helix … That is a separate ADR."
- Where: ADR-0049 decision 2 (the second sub-bullet under "Phase 1 keeps enforcement in Helix").

**G9. The trust-proxy setting is recorded only as an ADR-0011 amendment.** Confirmed.
- What: `EDGE_TRUST_PROXY` must name the ingress addresses, not a hop count. `TODO.md` records that a 2026-09-03 check found the shipped `auto` default trusted nothing.
- Where: `docs/platform-project-plan.md` lines 147-150, ADR-0011's 2026-09 amendment (line 42), and the `TODO.md` item "Make `EDGE_TRUST_PROXY` self-reporting on `/health`." The decision does not have its own record.
