# Known problems and backlog

_Scope:_ Helix's own backlog (TODO.md), SECURITY.md, the dated reviews in docs/reviews/, upstream open issues, and unmerged branches, judged for production use. _Method:_ read TODO.md headings and the long entries I rely on; opened code for 12 backlog items; read SECURITY.md in full; read the review documents' verdicts and spot-checked their actions in code; ran read-only `gh issue view` (#5, #6, #16, #43) and `git log`/`git diff --stat`/`git grep` against `origin/main` for the branches. All paths are relative to `projects/helix/`; local checkout is `main` at 792557a. I did not run tests or builds.

## Summary

The backlog is honest and unusually well kept: 52 open items, finished work deleted, every item tied to an ADR or issue, and the "Pre-M5" section is empty (TODO.md:38-43), so the team clears what it labels launch-critical. The June 2026 review's Critical and most Important findings were acted on (verified below). What remains is mostly policy and scale hardening, not broken crypto. The serious open items are: untrusted apps sharing a registrable domain with portal and auth; an LLM spend-gate bypass through client disconnect; reads being open to any signed-in user; the edge-to-egress instruction binding only partly closed; and a gap between what SECURITY.md says is deployed and what is verified. No exploitable Critical was confirmed in this pass.

## What already meets the bar

- **Backlog discipline.** TODO.md:5 deletes finished work and promotes residuals to their own entries; every item cites an ADR or issue number. The legend (TODO.md:7-14) states gating conditions, and the "Pre-M5" bucket is empty at TODO.md:38-43.
- **Reviews were acted on.** Spot-checked in code: scrypt now N=2^17, r=8, p=1 (`packages/shared/src/scrypt.ts:27-31`, the OWASP-level cost ISSUE-08 asked for); `ownsApp` BOLA guard shipped (TODO.md:28 and `apps/portal-web/src/test/overview-tab.test.tsx:20-22`, `apps/portal/src/plugins/auth.ts`); jti burn and shared rate counters exist (migration `20260721215912_shared_rate_counters_and_jti_burn`) and `apps/edge/src/server.ts:272` sweeps `rate_counters`; RLS on `gateway_calls`/`app_collection_items` (migrations `20260721033820_rls_gateway_calls_collection_items`); the legacy LLM fallback was removed (`docs/adr/0008*.md:3`); `gateway_calls` is insert-only for runtime roles (`migrations/20260721120000_gateway_calls_portal_readonly/migration.sql:27-30`).
- **Method/path binding on the egress instruction exists** (`apps/egress/src/proxy.ts:376-382`), and egress rejects userinfo-bearing targets with 400 `bad_target` (`proxy.ts:361-366`).
- **SECURITY.md is concrete.** Private reporting URL, 2-business-day ack, 7-day assessment, 90-day disclosure window (SECURITY.md:36-37), explicit in-scope surfaces and an out-of-scope list that points at TODO.md for known gaps (SECURITY.md:102-107).
- **Upstream CI green and 0 audit advisories** (given in the brief); no open vulnerability-class issue other than the three labelled security issues below.

## Findings

### KP-1 Untrusted apps share a registrable domain with portal and auth
- **Severity:** High **Status:** Confirmed **Area:** Security / infra
- **What:** Hosted apps, `auth.` and `portal.` all sit under `azx.helix.azxlabs.io`, one eTLD+1 (`azxlabs.io`). Any app can set domain-scoped cookies that the portal and auth hosts receive.
- **Evidence:** `infra/azure/main.bicepparam:18` (`param appsDomain = 'azx.helix.azxlabs.io'`); SECURITY.md:56-57 list apps, auth and portal under the same suffix; TODO.md:47 (Pre-GA, ADR-0019); upstream issue #16 (open, labels `security, important`, filed 2026-06-27) states the cookie-bomb DoS (oversized `Cookie` header gives 431 on portal and all apps), Safe-Browsing reputation blast radius, and same-site coupling. The issue itself says there is no direct session-theft path because `__Host-` cookies hold.
- **Why it matters:** One phishing app can get the whole suffix flagged and take the admin portal down. Cost of fixing rises with every customer URL issued. TODO.md:47 calls it Pre-GA, but the platform is already live (TODO.md:38-43), so the window is already narrowing.
- **Recommendation:** Pick a separate apps registrable domain now (and submit it to the Public Suffix List), before any external owner commits to a URL. Treat as a GA gate.

### KP-2 LLM client-disconnect is not propagated by egress; spend gate undercounts
- **Severity:** High **Status:** Confirmed (code), Hypothesis (exploit effect) **Area:** Egress / gateway
- **What:** Egress calls `undici.request(...)` with no abort signal, so when the edge drops a hung-up client, egress keeps draining the vendor stream. An abandoned stream meters `costMicroUsd` as 0 because `finalUsage` never saw `done`.
- **Evidence:** `apps/egress/src/proxy.ts:606-611` (`request(target.href, { method, headers, body: requestBody, dispatcher })`, no `signal`); grep of `proxy.ts` for `signal|AbortController|raw.on` finds only comments; TODO.md:58 describes the exploit: open N streams, hang up, vendor bills, daily spend gate never moves.
- **Why it matters:** A hostile or buggy app, or any user of a public app, can burn model spend that the budget control cannot see. This is a direct cost-control bypass on the one component that holds vendor keys. I did not reproduce it.
- **Recommendation:** Wire `reply.raw.on("close")` to an `AbortController` passed to `request`; decide a metering rule for cut streams (charge an estimate from input tokens plus bytes seen). Add a test that opens and drops streams and asserts the ledger moves.

- **Coordinator note (2026-10-08):** the design review found the post-header case is probably already handled: egress streams the upstream body through `capBody`, whose `pipeline(source, cap)` destroys the upstream body when Fastify destroys the response on a hang-up (`packages/shared/src/bodyCap.ts`). The confirmed gaps are the pre-header window and the $0 ledger row. See `workflow/design/helix-spend-containment-egress/01-spend-controls.md`, Part 1.

### KP-3 Reads are authenticated-only; no roles model and no real `private` mode
- **Severity:** Medium (High before a second tenant or external owners) **Status:** Confirmed (per TODO; route code opened partially) **Area:** Auth
- **What:** Any signed-in principal can list and read any app. Mutations are guarded by `ownsApp`; reads are not. The SPA renders mutate controls for apps the caller does not own, with a server 403 as the only boundary. `private` visibility does not exist.
- **Evidence:** TODO.md:28 (per-app RBAC residual, ADR-0007, issue #9), TODO.md:29 (`private`); `apps/portal/src/routes/apps.ts:162` (`scope === "mine" ? { ownerId } : {}`) and `:204` (`findUnique({ where: { slug } })` with no owner filter on the read); SECURITY.md:102-104 lists this as a known gap. `PreviewBadge` remains at `apps/portal-web/src/components/primitives.tsx:345`.
- **Why it matters:** Fine for one trusted org; not for handing apps to separate teams or customers. Draft apps, their capability requests and policy are visible to everyone.
- **Recommendation:** Implement TODO.md:29 first (day-one ACL is derived: owner plus admins, so small), then viewer/editor roles. Make it an explicit gate before onboarding anyone outside the operating team.

### KP-4 Edge-to-egress hop: instruction binding is assert-when-present; query and body unsigned; no key rotation
- **Severity:** Medium **Status:** Confirmed (binding), Hypothesis (transport exposure) **Area:** Egress trust
- **What:** Egress checks `method` and `path` only if the instruction carries them, so an instruction without them passes. The query and body were never bound. The signing key is one shared symmetric secret; asymmetric signing, per-app keys and mTLS are all open.
- **Evidence:** `apps/egress/src/proxy.ts:376-382` (`instruction.method !== undefined && ...`, `instruction.path !== undefined && ...`; comment says "Assert only when bound ... rollout safety"); `packages/shared/src/instruction.ts:97-98` (`method`, `path` are `.optional()`); TODO.md:54-57; upstream #6 (open, `security, important`) and #5 (open, `security, important`, "edge to egress is plain HTTP"). For #5: `infra/azure/main.bicep:732` builds `egressBaseUrl` as `https://<fqdn>` with egress on internal Container Apps ingress (`infra/azure/modules/containerapp.bicep:44`), so the hop is TLS-terminated at the ACA ingress in the live deployment. The app-level TLS the issue describes (egress `Fastify` with no `https`) I did not re-open, and the in-container leg behind the ingress is still HTTP.
- **Why it matters:** Both issues are conditional on an attacker on the east-west path, which the ACA environment narrows. The optional-claim path is the only piece with no environmental mitigation: an old or forged-shape instruction skips the checks. Issues #5 and #6 are stale relative to the repo (their cited line numbers predate current code) and should be updated or closed with the real residual.
- **Recommendation:** Make `method` and `path` required (the deploy window the TODO waits for has long passed: TODO.md:54 says edge and egress ship together and instructions live 30 s). Re-triage #5/#6 against current code; decide mTLS/workload identity or accept the ACA-ingress posture in an ADR.

### KP-5 SECURITY.md and the deployment story disagree; a firewall control is unverified
- **Severity:** Medium **Status:** Confirmed **Area:** Docs / security ops
- **What:** SECURITY.md:113-114 says "There are not currently any public-facing deployments", while the same file lists a live reference deployment as in scope (SECURITY.md:56-57) and TODO.md:38-43 says the platform is "deployed on Azure". It also lists "confirming `deployFirewall` is on in the live deployments" as an open item (SECURITY.md:104).
- **Evidence:** SECURITY.md:104, 113-114; TODO.md:38-43.
- **Why it matters:** The outbound allowlist firewall is the primary SSRF and egress control the June challenge said should be primary (docs/reviews/2026-06-26-adr-challenge.md, ADR-0005 row). Not knowing whether it is on in production means the central network control is asserted, not verified. A security policy that misstates exposure also misdirects reporters.
- **Recommendation:** Verify `deployFirewall` in each live install, record the result in an ops runbook, and remove the line from SECURITY.md. Rewrite the Testing section to match reality.

### KP-6 Enabling `password` visibility is baseline, not elevated; re-display writes no audit row
- **Severity:** Medium **Status:** Confirmed **Area:** Auth / approvals
- **What:** Only a move to `public` elevates (`classifyVisibilityChange`, `const elevated = to.mode === "public"`). Turning on `password` sharing needs no admin approval; the classifier ignores exposure when classifying later deltas; password re-display is the one credential action without an audit row.
- **Evidence:** `packages/shared/src/approval.ts:542-543, 573`; TODO.md:27.
- **Why it matters:** Password mode is now a real sharing mode (the demo-only ban was rescinded, TODO.md:27) but it can be switched on by any owner without a second pair of eyes.
- **Recommendation:** Do the three moves in TODO.md:27 (elevated enable, exposure-aware classifier, audit row on re-display). Control-plane only.

### KP-7 `gateway_calls` has no retention or erasure path (PII kept forever)
- **Severity:** Medium **Status:** Confirmed (grants), Hypothesis (no pruning job) **Area:** Data / compliance
- **What:** No role has DELETE on `gateway_calls`; the table stores request paths and `userName`/`userEmail`. No pruning job found; TODO.md says none exists.
- **Evidence:** `apps/portal/prisma/migrations/20260616000001_edge_role_grants/migration.sql:24` (edge `SELECT, INSERT`), `20260721120000_gateway_calls_portal_readonly/migration.sql:29` (portal INSERT/UPDATE/DELETE revoked); TODO.md:141 (ADR-0021 amendments). A separate TODO.md:89 notes connection-secret destroy is a soft delete with 90-day retention, so crypto-shredding is not available there either.
- **Why it matters:** A GDPR erasure request cannot currently be honoured for metering rows. Fine for an internal pilot; a blocker for external customers in the EU.
- **Recommendation:** Choose a retention basis, add a controlled pruning/pseudonymisation path (a DB role used only by a job), document in the privacy notes.

### KP-8 Registry projection: multi-replica cold-start and scale gaps
- **Severity:** Medium **Status:** Hypothesis (not opened in code) **Area:** Infra / ops
- **What:** A cold replica with the database down returns 503 for all apps while `/health` can read green; the LISTEN connection budget caps at about 30 replicas; every commit forces a full-table reload per replica.
- **Evidence:** TODO.md:142 (ADR-0025 items 3-5). `infra/azure/modules/containerapp.bicep:57` sets `maxReplicas` default 3, so multi-replica is already the deployed shape.
- **Why it matters:** The health-green-but-serving-503 case defeats the platform's own availability alerting during a database incident. Scale ceiling is irrelevant at tens of apps.
- **Recommendation:** Land the readiness fix (not-ready until first load, or durable snapshot) now; defer the cursor reload.

### KP-9 Relaxed CSP plus anonymous shared writes leaves a third-party stored-XSS path
- **Severity:** Medium **Status:** Confirmed (CSP), Confirmed (TODO record) **Area:** Security
- **What:** `script-src` carries `'unsafe-inline' 'unsafe-eval'` and a CDN allowlist; no SRI; `object-src 'none'` still missing. On `public` apps with `sharedWrite`, anonymous third parties can write content other users read. Authenticated 412 floods on a shared key are metered but not bounded.
- **Evidence:** `apps/edge/src/serving/csp.ts:65`; TODO.md:79-83. The 2026-06-26 challenge raised the same point (ADR-0009 and 0010 rows). SECURITY.md declares relaxed CSP out of scope (SECURITY.md:94-97), which is consistent for hostile apps but does not cover the third-party author case.
- **Why it matters:** The "apps are hostile anyway" argument does not protect visitors from a different attacker writing into the app's data.
- **Recommendation:** Make `public` + `sharedWrite` an approval-gated opt-in (TODO.md:80); add `object-src 'none'`; separate the anonymous write budget.

### KP-10 Handoff token travels in the query string
- **Severity:** Medium (Low for confidentiality; token is single-use, 30 s) **Status:** Confirmed **Area:** Auth
- **What:** `/_auth/complete?token=...` leaves the spent token in every app user's browser history.
- **Evidence:** `apps/edge/src/app.ts:525` (route `url: "/_auth/complete"`); `apps/edge/src/serving/assets.ts:44` names `/_auth/complete?token=...`; TODO.md:33 (issue #20 residual) lists the bounds (single-use, 30 s TTL, audience-bound, `no-referrer`, `no-store`).
- **Why it matters:** Bounded and well-argued, so low exploitability; it is a known weakness in the most security-sensitive flow.
- **Recommendation:** Move to POST form-post or fragment delivery when the auth flow is next touched.

### KP-11 Entra group-claim overage is a hard denial
- **Severity:** Low now, Medium at scale **Status:** Confirmed **Area:** Auth
- **What:** Above about 200 groups Entra drops the `groups` claim. The edge uses an empty list and denies group apps.
- **Evidence:** `apps/edge/src/auth/oidc.ts:161-177` (`groupsClaimOverflowed`, logging only); TODO.md:31; ADR-0040 decision 10. Token-size measurement at that scale is still open (TODO.md:32).
- **Why it matters:** Fail-closed and diagnosable, but a legitimate member is locked out until a Graph call is allowed on the sign-in path, which ADR-0003 forbids.
- **Recommendation:** Keep deferred until a customer has many groups; the `ApplicationGroup` claim variant is the cleaner fix. Document the limit in the operator guide.

### KP-12 `GET /api/v1/apps?scope=all` fails past about 32k apps
- **Severity:** Low **Status:** Confirmed **Area:** Portal API
- **What:** `version.groupBy` with `appId: { in: appIds }` passes one bind per app; Postgres' limit gives Prisma `P2029`.
- **Evidence:** `apps/portal/src/routes/apps.ts:166-172`; TODO.md:48 (seen on a polluted test DB, 33,235 rows).
- **Why it matters:** Not reachable at the stated scale (tens of apps), but `scope=all` is unpaginated by construction.
- **Recommendation:** Chunk or join; add pagination when app counts grow.

### KP-13 Unmerged and stale branches
- **Severity:** Low **Status:** Confirmed **Area:** Repo hygiene
- **What:** 10 non-main branches; three are fully merged and seven carry commits, of which five look superseded by `main`. See the table in the Unmerged branches section.
- **Evidence:** `git log --oneline origin/main..origin/<branch>` for each branch; `git branch -r --merged origin/main` lists `chore/justfile`, `ci/split-checks-and-bicep`, `feat/fetch-proxy-path-metering`, `feat/platform-observability`.
- **Why it matters:** Branches that look like open work but are not mislead a new owner.
- **Recommendation:** See the branch table.

### KP-14 Upstream feature request #43 (agent deploy UX)
- **Severity:** Low **Status:** Confirmed **Area:** Product / docs
- **What:** A user reports deploying from Claude or Codex needs copy-pasted instructions and argument with the assistant. Filed 2026-10-06, no comments.
- **Evidence:** `gh issue view -R AZX-PBC-OSS/helix 43`. `packages/deploy-skill` and the CLI exist and are the obvious home.
- **Why it matters:** Adoption friction, not a production risk.
- **Recommendation:** Answer it with a one-line install of the deploy skill and document it on the first docs page.

## Review follow-through (docs/reviews/)

Docs/reviews/README.md:3-6 says nothing there is maintained; conclusions were folded into ADRs.

| Review | Conclusion or recommendation | Acted on? |
|---|---|---|
| 2026-06-25 architecture review (`docs/reviews/2026-06-25-architecture-review.md:12-18`) | Containment architecture sound; risks are the edge-to-egress seam (single symmetric secret) and "documented v0" shortcuts to close before multi-tenant. 17 issues (ISSUE-01 header blocklist, 02 chunked caps, 04 replay/aud, 08 scrypt cost, 12-13 RLS, 15 throttle, 16 DSN fallback) and 3 decisions (DEC-01 ownership, DEC-02 anonymous writes, DEC-03 CSP). | Mostly yes: scrypt 2^17 (`scrypt.ts:27`), jti burn and shared counters (migration `20260721215912`), RLS migrations, `ownsApp`. Still open: DEC-02 (TODO.md:80-83), DEC-03 (TODO.md:79; `csp.ts:65`), aud/key rotation and asymmetric keys (TODO.md:55-56, issue #6). |
| 2026-06-26 ADR challenge (`docs/reviews/2026-06-26-adr-challenge.md`) | All 13 ADRs WEAKEN, none overturned; ADR text overstated delivery. Priority code fixes: 0007 owner gate, 0011 throttle, 0013 per-app keys + method/path binding, 0008 remove legacy LLM fallback. | 0007 done (`ownsApp`), 0011 done (`apps/edge/src/server.ts:173-175, 272`), 0008 done (ADR-0008:3), method/path binding done but optional (KP-4). Per-app-derived keys explicitly rejected as unsound (TODO.md:56 and the "Explicitly rejected" section from line 151). Dependency allowlist (0003) still open (TODO.md:21). |
| 2026-06-26 verification (`...adr-challenge-verification.md`) | Re-checked each row: most Hold, several Holds-but-overstated; flagged live BOLA on secrets routes and ungated legacy LLM fallback. | Both flagged defects fixed (above). |
| 2026-06 build-vs-buy (`docs/reviews/2026-06-build-vs-buy.md:1-17`) | Build is right if the static-only bet holds; the open fork is thin apps plus fat gateway (current) vs full-stack apps with microVM isolation. | The static-only route was chosen (custom backends deferred, TODO.md:144 and `docs/design/custom-backends.md`). No decision doc recording the fork was found; open question. |
| 2026-08-20 Entra group probe (`docs/reviews/2026-08-20-entra-group-permissions-probe.md:79-100`) | Ask for only `GroupMember.Read.All`; serve "my groups" from the user's own delegated `User.Read` token. | Yes: folded into ADR-0040; the picker and my-groups endpoint shipped (TODO.md:31). Residual overage and token-size measurement open (TODO.md:31-32). |

## Backlog map

TODO.md has 52 open items (my count from the checkbox lines), grouped by my classification. The file has no checked boxes, no items under "Pre-M5" (TODO.md:38-43), and a "Pre-GA" section of two (TODO.md:45-48).

| Area | Open items | Highest severity | Representative items (TODO.md line) |
|---|---|---|---|
| Auth | 7 | Medium | password on the approvals spine (27); per-app RBAC (28); real `private` mode (29); group-claim overage (31); token-size measure (32); handoff token off the query string (33); redaction residual (34) |
| Security (non-auth) | 9 | High | separate apps domain (47); CSP supply chain (79); anonymous shared-write model (80); 412 flood on shared key (81); shared DELETE verb (82); per-app shared-row cap (83); secret erasure (89); plaintext dwell and cache (90); hosted-build isolation gates (143) |
| Egress / connections | 10 | High | client-disconnect abort (58); required method/path claims (54); asymmetric signing (55); long-tail key strategy (56); mTLS (57); per-binding method/path allowlist (64); hmac-timestamp knobs (65); rotate-panel UX (66); egress cache sizing (96); stranded sealed entry (97) |
| Data | 4 | Medium | export memory bound (72); composite drain cursor (73); stale-form concurrency (139); `gateway_calls` retention/erasure (141) |
| Portal / SPA | 10 | Low | unbounded `IN` in `scope=all` (48); offline manifest lint (103); operator kill switch flag (104); bundle salvage items (114-118); withdraw control (140); usage chart timezone (131) |
| Infra / ops | 7 | Medium | registry multi-replica hardening (142); Foundry live validation (124); gpt-4.1 recheck (125); `modelVersion` omission (126); Foundry private endpoint (127); GeoIP DB refresh (133); wildcard TLS pre-apply wrapper (146) |
| Observability | 1 | Low | metrics to an Azure Monitor workspace (147) |
| Testing | 0 explicit | n/a | None listed as items; test-DB hygiene was closed (48). Gaps found elsewhere are in other notes. |
| Docs | 0 explicit | n/a | None listed |
| Other | 4 | Low | trim `openid-client` (20); dependency allowlist in CI (21); custom backends (144); multi-org tenancy (145) |

Numbers sum to 52.

### TODO.md items checked against code (12)

| TODO.md | Item | State | What I opened |
|---|---|---|---|
| 47 | Separate apps domain | Open | `infra/azure/main.bicepparam:18` |
| 58 | Egress abort propagation | Open | `apps/egress/src/proxy.ts:606-611`; grep for `signal` |
| 54 | Required method/path claims | Partly done (asserted when present) | `proxy.ts:376-382`; `packages/shared/src/instruction.ts:97-98` |
| 48 | Unbounded `IN` in `scope=all` | Open | `apps/portal/src/routes/apps.ts:162-177` |
| 27 | Password visibility baseline | Open | `packages/shared/src/approval.ts:573` |
| 28 | Per-app RBAC | Partly done (mutations guarded; reads open) | `apps/portal/src/routes/apps.ts:162, 204` |
| 29 | Real `private` mode | Open | grep for `"private"` in `packages/shared/src/visibility.ts` found no mode |
| 31 | Group overage | Open (log only) | `apps/edge/src/auth/oidc.ts:161-177` |
| 33 | Handoff token in URL | Open | `apps/edge/src/app.ts:525`; `assets.ts:44` |
| 141 | `gateway_calls` retention | Open | migrations `20260616000001`, `20260721120000` |
| 115 | Mime allowlist for media | Open | `apps/portal/src/deploy/mime.ts`; `mp4`, `csv`, `vtt` absent |
| 140 | Withdraw control in portal | Open | `useWithdrawRequest` defined at `apps/portal-web/src/api/mutations.ts:203`, no render site found by grep |
| 79 | `object-src 'none'` | Open | `apps/edge/src/serving/csp.ts:65`; directive not present |

None of the items I checked was done-but-unticked, which fits the file's delete-on-done rule. The one drift I found is in SECURITY.md, not TODO.md (KP-5).

## SECURITY.md summary

- **Threat model:** every hosted app is untrusted code, contained per app (SECURITY.md:4). Boundaries promised: app origin and session, user data, ungranted capabilities, secrets, internet access from the edge.
- **Reporting:** GitHub private advisory (SECURITY.md:15-20); ack in 2 business days, assessment in 7, 90-day coordinated disclosure (36-37); no bounty. The URL points at the public `AZX-PBC-OSS/helix`, which a private fork cannot receive; reports need a route for the fork.
- **Admitted limitations:** beta, posture still changing (9); open `img-src` and navigation exfiltration, relaxed CSP (94-97); per-app RBAC missing; `deployFirewall` unconfirmed; PSL submission pending (102-105). Contradictory line: "no public-facing deployments" (113-114), see KP-5.

## Upstream open issues (AZX-PBC-OSS/helix)

| # | Title | Labels | Summary | Production severity |
|---|---|---|---|---|
| 5 | Edge-egress hop is plain HTTP | security, important | Neither edge's undici `Agent` nor egress's Fastify has TLS config; signed instruction replayable and response bodies visible on-path. Downgrades to Minor under a private network with encrypted east-west. | Medium. Live deployment uses `https://` to internal ACA ingress (`main.bicep:732`), so the exposure is mostly closed; issue is stale. |
| 6 | Instruction binds only the origin | security, important | Part A: method, path, query, body unsigned; Part B: no `aud`, no key rotation. Conditional on the plaintext hop. | Medium. Method and path now bound when present (`proxy.ts:376-382`); query/body/aud/rotation still open. |
| 16 | Untrusted apps share the registrable domain | security, important | Cookie-bomb DoS, reputation blast radius, same-site coupling; cost grows with customer URLs. | High as a GA gate (KP-1). |
| 43 | Make it easy to deploy from Claude/Codex | none | Adoption friction when deploying with an AI assistant. | Low. |

The issue list shows only these four open issues.

## Unmerged branches

Seed ahead/behind counts re-confirmed with `git log origin/main..origin/<branch>`.

| Branch | What it is | Superseded by main? | Recommendation |
|---|---|---|---|
| `ci/audit-report-job` (1 ahead) | Adds `scripts/audit-report.mjs` and a CI job that reports `pnpm audit` advisories without gating (+298 lines). | No; `package.json` on main has no `audit:report`. | Rebase, merge if you want advisory reporting (CI is manual-dispatch only right now, so low value); otherwise archive. |
| `docs/adr-0038-approval-expiry-and-queue-age` (2) | ADR on no approval expiry plus an SPA "pending for N days" label. | Yes; main has `docs/adr/0039-no-approval-request-expiry.md` and `ApprovalsPage.tsx:49` `ageLabel`. | Delete. |
| `feat/approvals-prior-decisions` (2) | Prior decisions on the admin approval queue (#26). | Yes; main has `priorDecisions` in `ApprovalsPage.tsx:108-170`. | Delete. |
| `fix/24-approvals-decision-cas` (2) | Compare-and-swap on approval decision and apps policy write. | Yes; main has commits 299d486 and 9e65ffb with the same messages and CAS in `apps/portal/src/routes/approvals.ts:77, 315`. | Delete. |
| `fix/bug-class-ledger` (1) | Vendor usage counts coerced at the wire; egress rejects userinfo targets. | Yes; main commit f675938 has the same message and `proxy.ts:361-366`. | Delete. |
| `test/approvals-gate-coverage` (2) | Tests for the approvals admin gate; stop the suite inheriting `PORTAL_ALLOW_SELF_APPROVE`. | Largely; main has the `admin gate` describe (`approvals.test.ts:146`) and sets `PORTAL_ALLOW_SELF_APPROVE: "false"` in `vitest.config.ts`. Hypothesis that every added test is already on main. | Check by cherry-pick dry run, then delete. |
| `prototype/lovable-at-home` (7, 432 behind) | Spike: bolt.diy builder, OpenAI-compatible gateway, `@helix/app-sdk`, Anthropic prompt caching on the LLM request. | No (a prototype). Prompt caching is not on main (`provider.ts:115` says "no cache_control yet"). | Archive as a tag; consider cherry-picking the prompt-caching change on its own, since caching affects cost and metering. |
| `ci/split-checks-and-bicep`, `feat/fetch-proxy-path-metering`, `feat/platform-observability` (0 ahead) | Fully merged. | Yes (`git branch -r --merged`). | Delete. |

## Missing for production / staff-level quality

- **A written GA gate.** The backlog uses "Pre-GA" and "Before multi-tenant" labels (TODO.md:7-14) but nothing lists which items must be closed before external customers, and the June challenge noted that milestone labels without a forcing function slip (adr-challenge.md, meta-finding 3). Create a single checklist (KP-1, KP-3, KP-4, KP-7, KP-9 are candidates).
- **Verification of live controls.** SECURITY.md:104 admits the firewall state is unconfirmed; there is no runbook entry or automated check that proves it (KP-5).
- **A decision record for the strategic fork** in build-vs-buy section 5; the review ends by saying it cannot settle it.
- **Security reporting path for the fork.** SECURITY.md routes to the upstream advisory form; a private fork has no equivalent configured.
- **Ownership beyond one person.** 556 of 564 commits are by one author (brief); the backlog is detailed enough for a handover, but there is no named on-call or triage owner for the security issues (#5, #6, #16 sat open 3 to 4 months).

## Open questions

- Is `deployFirewall` on in each live install, and which installs exist?
- Which milestone defines "GA", and are external app owners planned before KP-1 can be done?
- Should issues #5 and #6 be closed and re-filed against the current residual?
- Does the private fork have a security advisory route, or should SECURITY.md change?
- Did `test/approvals-gate-coverage` add any assertion that is not already on main?
