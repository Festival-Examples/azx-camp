# Operability and production readiness

_Scope:_ Azure deployment, release path, observability, runbooks and ownership of Helix at git `main`. _Method:_ read-only review of `infra/azure/README.md`, `main.bicep`, `main.bicepparam`, the modules (postgres, storage, keyvault, containerapp, aca-environment, firewall, migrate-job, action-group, alerts-*), `.github/workflows/*.yml`, the three app Dockerfiles, `docs/features/observability.md`, ADR-0025, and `docs/runbooks/`. No `az`, docker, or deploy commands were run; nothing was executed against a live install.

## Summary

The infrastructure-as-code is unusually careful for its age. Private endpoints, per-plane identities, a forced-tunnel firewall, a no-credential migrate job, and an outside-in availability probe that reads the `/health` body all exist and are documented with the reasons behind them. The platform is not yet operable as a service for real customers. It is a single-instance topology (no HA Postgres, no zones, LRS blobs, one firewall, one replica minimum), backups are the 7-day Postgres default with no documented or tested restore, and the release path has no staging, no pinned image versions, and no rollback procedure. Alerts deploy only if someone sets `alertEmails`, which no committed parameter file does, and notification is email only. Operational knowledge lives in one author's long README and ADR amendments, with no incident runbooks.

## What already meets the bar

- **Outside-in monitoring that handles the always-200 `/health` contract.** ADR-0025 makes `/health` return 200 in every state so a liveness probe cannot restart a healthy replica (`docs/adr/0025-registry-projection-hardening.md`, implementation note 4). `modules/alerts-availability.bicep` compensates with App Insights standard tests that fail on `"status":"error"` in the body (README "Availability tests"). The `alertsNotify` output exists specifically to flag alerts that reach nobody (`main.bicep:1556-1557`).
- **Data plane is private.** README "The security shape" and "Verifying the isolation" give concrete post-deploy checks; Postgres, Blob and all three Key Vaults are private-endpoint only.
- **Key Vault hygiene.** RBAC authorization, soft delete with 90-day retention (`modules/keyvault.bicep:49-50`), purge protection (`:20`), `kv-delegated` writable by the egress identity only (README "The security shape").
- **Migration path holds no standing admin credential.** A declared manual ACA Job reads the admin password with a one-role identity (`modules/migrate-job.bicep:1-30, 98`). Migrations are forward-only and the file says so.
- **Secret rotation mechanism is specified and was tested.** Versionless Key Vault references, ~30 minute refresh, and the explicit warning that `az containerapp revision restart` does not re-resolve (README "Platform secret delivery", "Known deploy gotchas"; verified 2026-09-17 per the text).
- **Graceful shutdown is implemented and reasoned.** 10 s drain under the 30 s ACA window, and the entrypoint is `node --import tsx` so the tsx CLI does not swallow SIGTERM (`apps/edge/package.json:9`, README "Container shutdown").
- **Cost alerting is reasoned, not copied.** The budget is derived from deployment shape with headroom so it does not fire monthly by design (README "Cost"). LLM spend is split to its own resource group.
- **Failure handling was exercised, not assumed.** ADR-0025 records a severable-proxy experiment that found and fixed an unhandled `pg` pool error that would have killed the edge on a DB drop.
- **Telemetry design is disciplined.** Hand-placed spans, redaction tests, OTLP-only boundary, constants for span names (`docs/features/observability.md`).

## Findings

### OPS-1 Single-instance data tier: Postgres HA off, no zones, LRS blobs
- **Severity:** High **Status:** Confirmed **Area:** Topology and resilience, data
- **What:** Postgres Flexible Server runs one node with `highAvailability: Disabled`. Blob storage is `Standard_LRS`. Neither ACA environment nor the firewall is set zone-redundant. The registry, sessions, rate counters, metering ledger and every app's data live in that one server, and the edge's `/_api/*` and routing depend on it.
- **Evidence:** `infra/azure/modules/postgres.bicep:66-68` (`mode: 'Disabled'`); `infra/azure/modules/storage.bicep:32` (`Standard_LRS`); `grep -n zone` over `main.bicep` and `modules/aca-environment.bicep` shows no `zoneRedundant` setting; `infra/azure/main.bicepparam:15` pins one `Standard_D2ds_v5` with 32 GB.
- **Why it matters:** A zone outage, a host fault, or Azure's routine maintenance restart takes the control plane and the edge's data gateway down. Edge serving of already-loaded apps degrades to stale-registry mode only for projection reads; sessions, counters and app-data reads still need Postgres. Blob loss in one datacenter loses every deployed site's assets.
- **Recommendation:** Decide a stated availability target. For a paid offering, enable zone-redundant HA on Postgres, move Blob to ZRS (or GZRS), set `zoneRedundant` on the apps environment, and raise replica minimums to 2 for edge. Record the accepted risk if the answer is "single instance for now".

### OPS-2 Backups exist only at the Azure default, with no tested restore and no Blob protection
- **Severity:** High **Status:** Confirmed **Area:** Data
- **What:** Postgres has 7-day PITR retention and geo-redundant backup disabled. The storage account has no blob versioning, no soft delete, no immutability, and no lock. No document describes a restore procedure, a recovery objective, or a restore drill. The only mentions of restore in `docs/` concern unarchiving apps and design notes.
- **Evidence:** `infra/azure/modules/postgres.bicep:69-72`; `infra/azure/modules/storage.bicep:26-52` (no `blobServices` properties set beyond defaults); `grep -rli "point-in-time\|PITR\|disaster"` across `docs/`, `infra/`, `AGENTS.md`, `TODO.md` finds no restore runbook; the runbook directory holds eight files, none about recovery (`docs/runbooks/`).
- **Why it matters:** A bad migration, a bad delete, or a region loss has no rehearsed answer. Restoring a Flexible Server into a private-access VNet with the private DNS zone and role passwords re-attached is non-trivial, and the app-bundle blobs have no second copy. Migrations are forward-only (`migrate-job.bicep:1-30`), so a bad migration is recoverable only by restore.
- **Recommendation:** Write and run a restore drill: PITR to a new server, repoint via parameters, verify roles and RLS. Enable blob soft delete and versioning, consider GZRS, extend PITR retention and enable geo-redundant backup if the customer base needs it, and add a resource lock on the data resources. Document a "bad migration" procedure (expand/contract rules, restore point before migrate).

### OPS-3 No staging environment; release path is manual, unpinned, and has no rollback procedure
- **Severity:** High **Status:** Confirmed **Area:** Environments and release
- **What:** The repo describes one install (`helix-prod`). There is no staging parameter file and no deploy workflow. All three workflows run only on manual dispatch. `ci.yml` builds images with tags `sha-<short>`, branch name, semver on `v*` tags, and `latest` (`ci.yml:497-502`), but the repo has no platform `v*` tag, only `cli-v0.1.0` to `cli-v0.4.0`. The committed parameter default for `imageTag` is `latest` (`main.bicepparam:34`). Container apps run in Single revision mode. The README release flow is: set `imageTag`, run a full `az deployment group create`, then manually `job update` and `job start` the migrate job. It contains no rollback section.
- **Evidence:** `.github/workflows/ci.yml:61-65` (triggers commented, `workflow_dispatch` only), `:497-502`; `git tag` output (only `cli-v*`); `infra/azure/main.bicepparam:34`; `infra/azure/modules/containerapp.bicep:126` (`activeRevisionsMode: 'Single'`); `infra/azure/README.md` steps 3, 5, 6; `infra/azure/modules/migrate-job.bicep:1-30` for the migrate flow.
- **Why it matters:** A bad image reaches production with no preview. Using `latest` means a restart or revision can silently pull a different build than the one tested. Single revision mode keeps the old revision only until the new one is healthy; because `/health` is always 200 (ADR-0025), "healthy" does not prove the new revision serves correctly. Image-then-migrate ordering is manual: the README applies the new image before running the migration, and the apps tolerate a missing schema only for first install.
- **Recommendation:** Add a staging parameter file and environment. Publish `v*` platform tags and deploy by digest or immutable tag. Write a release procedure with the order (migrate, then image, or the reverse, per migration type), smoke checks beyond `/health`, and a rollback: previous tag redeploy, plus the restore path from OPS-2 for schema. Add a deploy workflow with required approval and an environment-scoped identity.

### OPS-4 Alerts reach nobody unless `alertEmails` is set, and none of the committed parameter files set it
- **Severity:** High **Status:** Confirmed **Area:** Observability, incident response
- **What:** Every alert rule routes through one email-only action group, created only when `alertEmails` is non-empty. `alertEmails` defaults to `[]`, is not set in `main.bicepparam` or `main.bootstrap.bicepparam`, and the cost budgets are also skipped when it is empty. There is no webhook, SMS, pager, or chat receiver. The `Severity 0` database alert is the only severity-0 rule.
- **Evidence:** `infra/azure/main.bicep:303` (`param alertEmails array = []`), `:857` (action group conditional on `!empty(alertEmails)`), `:975` and `:1003` (budgets conditional on it); `grep alertEmails` over both `.bicepparam` files returns nothing; `infra/azure/modules/action-group.bicep:35-44` (email receivers only); README Alerting section: "With `alertEmails` empty the rules still deploy and still fire — at nobody".
- **Why it matters:** A deployment from the committed parameters has monitoring that looks complete and notifies no one, including the database-down alert and the budget. Email-only routing is not an on-call mechanism.
- **Recommendation:** Make `alertEmails` (or an Azure Monitor receiver) required when `deployApps=true`, failing the deploy on empty. Add an on-call receiver (webhook to a pager) for severity 0 and 1, and document who is on call.

### OPS-5 No incident runbooks for the failures most likely to occur
- **Severity:** High **Status:** Confirmed **Area:** Incident response
- **What:** `docs/runbooks/` has eight files: connection provider rollout, Asana acceptance, Entra group claims rollout, raise fetch body cap, Entra app registration, principal rebase cutover, user labels and erasure, backfill app owners. All are rollout or change procedures. None covers Postgres down or failed over, Key Vault unreachable, wildcard certificate expiry or failed renewal, LLM vendor outage, egress compromise or secret rotation after compromise, bad deploy rollback, or restore. Fragments exist inside the infra README ("How a rotated platform secret actually reaches the apps", "re-bind against the cert already in the environment store"), but they are written as deploy gotchas, not as alert-to-action procedures. No alert description links to a runbook.
- **Evidence:** `ls docs/runbooks/` (eight files); `infra/azure/README.md` "Known deploy gotchas" and "Wildcard TLS"; `infra/azure/modules/alerts-infra.bicep` rule list in the README table (no runbook field).
- **Why it matters:** The team that takes this over gets paged by an alert and has to reconstruct the response from a 1,340-line README and ADR amendments. The egress app is the one component with plaintext connection secrets and a route to the internet; a compromise response (rotate KEK and provider secrets, revoke delegated tokens, cut the egress route) is the highest-stakes undocumented procedure.
- **Recommendation:** Write one short runbook per alert and per scenario named above, each starting from the symptom and the alert name, and link them from alert descriptions. Prioritise egress compromise, Postgres loss/restore, and certificate expiry.

### OPS-6 Wildcard certificate renewal is unmonitored by default and the committed parameters point at Let's Encrypt staging
- **Severity:** Medium **Status:** Confirmed **Area:** Networking, observability
- **What:** `main.bicepparam` sets `deployCertbot = true`, defaults `acmeServer` to the staging directory, and sets `wildcardTlsBound = false`. The availability TLS check defaults off while `acmeServer` is staging, so no monitor checks certificate lifetime on a deployment using the committed defaults. The certbot job runs daily, retries once (`replicaRetryLimit: 1`), and no alert rule watches job execution failures; `alerts-infra.bicep` covers container apps' restart counts, not jobs. The job has no persistent state, so renewal timing is derived from the cert in the ACA environment store and "fails open" to issuing.
- **Evidence:** `infra/azure/main.bicepparam:54-64`; `infra/azure/modules/certbot.bicep:71, 161`; README "Wildcard TLS" and "TLS: the check follows `acmeServer`"; README notes a template re-apply with the gate off strips all custom domains.
- **Why it matters:** After switching to production ACME, expiry is covered only if availability tests and a recipient are configured (see OPS-4). A staging cert left in place yields browser TLS errors for every hosted app. A silent job failure surfaces only when the 14-day expiry warning fires, which leaves little margin if the cause is a DNS or identity regression. One Let's Encrypt account and a 5-per-week duplicate limit make emergency re-issuance fragile.
- **Recommendation:** Alert on certbot job execution failure, and on certificate lifetime independent of the availability tests. Provide a cert expiry runbook (OPS-5). Make production ACME and `wildcardTlsBound = true` part of the production parameter set rather than a manual flip.

### OPS-7 No replica redundancy for edge, egress, or the OTel collector, and no tuned scaling or probes
- **Severity:** Medium **Status:** Confirmed **Area:** Topology and resilience
- **What:** `containerapp.bicep` defaults `minReplicas = 1`, `maxReplicas = 3`, 0.5 CPU / 1 GiB, and `main.bicep` never overrides them for any app. No `scale` rules are defined (ACA applies its default HTTP rule) and no `probes` block exists, so ACA's default TCP probing is all that checks readiness. The OTel collector per environment is `min 1 / max 2`, and the egress plane is one internal app. The firewall is a single instance.
- **Evidence:** `infra/azure/modules/containerapp.bicep:54, 57, 147-150`; `grep -n "minReplicas\|maxReplicas" infra/azure/main.bicep` returns nothing; `grep -n probes` over `infra/azure` returns only comments in alerts modules; `infra/azure/modules/otel-collector.bicep:40-43`.
- **Why it matters:** One replica means every revision swap, node move or crash drops capacity to zero for the app until the new replica passes the TCP check. Egress is the sole path for LLM and fetch-proxy traffic, so its restart interrupts every in-flight LLM call (the drain window is 10 s while the fetch timeout is 120 s, per README "Fetch-proxy body cap" and "Container shutdown"). Because `/health` cannot be used as a readiness probe by design, a replica can pass TCP and still be unable to serve.
- **Recommendation:** Set minimum 2 for edge, portal and egress (with zone redundancy), define explicit HTTP scale rules, and add a readiness probe on a distinct endpoint that returns non-200 only for "cannot serve" states (ADR-0025 argues only against making liveness depend on staleness). Review whether the 10 s drain is adequate for long proxied calls.

### OPS-8 Ingress has no WAF or DDoS layer; edge protection is application-level rate limiting
- **Severity:** Medium **Status:** Confirmed **Area:** Networking
- **What:** The edge is exposed directly on the ACA public load balancer. ADR-0022 rejects a vendor edge (Front Door / App Gateway), the README lists Front Door only as an optional way to reach the internal portal, and no WAF, DDoS plan or CDN appears in the Bicep. Abuse protection is the in-process per-IP limiter and login throttle, which depend on `EDGE_TRUST_PROXY` resolving the real client address.
- **Evidence:** `docs/adr/0022-self-hosted-edge-not-front-door.md:1`; `infra/azure/README.md:421, 1125` (Front Door mentions); no match for `ddos`/`waf` in `infra/azure/**/*.bicep`; README "Verifying the trusted-proxy address" and the `trust-proxy` health sub-check.
- **Why it matters:** The edge hosts untrusted AI-generated apps and serves a wildcard domain. Volumetric or L7 floods go to 1-3 small replicas and Postgres. The rate-limit correctness depends on a header-trust setting that failed silently once (README: the wrong default survived from M5 to 2026-09-03).
- **Recommendation:** Record the DDoS and WAF decision explicitly, then either place a CDN/WAF in front of the wildcard domain or document why the application controls suffice at the target scale. Keep the trust-proxy alert.

### OPS-9 The egress firewall rule allows every FQDN, so the "network allow-list" claim overstates the control
- **Severity:** Medium **Status:** Confirmed **Area:** Networking (egress controls)
- **What:** The README describes the firewall allow-list as the primary SSRF and egress control. The rule for the egress subnet allows `targetFqdns: ['*']` on 80 and 443. The policy's threat-intel mode is `Alert`, not `Deny`. The firewall therefore enforces "edge and portal cannot reach the internet", but for the egress subnet the actual destination control is the application-level `ssrf.ts` validation.
- **Evidence:** `infra/azure/modules/firewall.bicep:108` (`targetFqdns: ['*']`), `:84` (`threatIntelMode: 'Alert'`); `infra/azure/README.md` "Optional: the egress firewall" ("this network-zone allow-list is the **primary** SSRF/egress control").
- **Why it matters:** An egress-app compromise or SSRF bypass has unrestricted internet reach, including data exfiltration to arbitrary hosts, and the only component with plaintext secrets is the one with this reach. At roughly $900 per month (README), the firewall buys isolation of the other planes but not defence in depth for egress.
- **Recommendation:** Correct the documentation wording, set threat-intel to Deny, log firewall flows to Log Analytics with an alert on unusual egress destinations, and consider per-app or per-provider FQDN allow-lists fed from approved manifests.

### OPS-10 Platform secrets are readable by resource-group Contributor, and rotation has no schedule
- **Severity:** Medium **Status:** Confirmed **Area:** Configuration and secrets
- **What:** Key Vault references resolve through `az containerapp secret list --show-values`, so anyone with Contributor on the resource group can read every per-role Postgres DSN, the signing secrets and the edge OIDC private key. The Postgres admin password is also in `kv-platform`. The runbooks cover rotation mechanics, but nothing sets a rotation cadence, an owner, or a reminder for the edge OIDC certificate or the shared HMAC keys. The deploy parameter file hardcodes a placeholder subscription id in every `az.getSecret` line that an operator has to edit by hand.
- **Evidence:** `infra/azure/README.md` "Known deploy gotchas" ("Resource-group Contributor is effectively platform-secret read access", verified 2026-09-17); `infra/azure/main.bicepparam:146-161`; `grep -ni "rotat\|expir" docs/runbooks/entra-app-registration.md` shows no cadence guidance.
- **Why it matters:** The "who can deploy" boundary is also the "who can read all platform secrets" boundary. Without a calendar, the edge certificate used for `private_key_jwt` will expire unannounced and break all sign-ins.
- **Recommendation:** Define deploy roles (a deploy principal separate from human Contributor), alert on certificate expiry, and publish a rotation table (secret, owner, interval, procedure).

### OPS-11 No SLOs, dashboards, or log-based operational views
- **Severity:** Medium **Status:** Confirmed **Area:** Observability
- **What:** The spans and metrics are rich, but the deliverables stop at seven alert rules and the availability test. There are no SLOs, error budgets, workbooks or Grafana dashboards; the repo does not contain a dashboard definition. Metrics sit in App Insights `customMetrics` and the move to an Azure Monitor workspace is listed as a TODO. The OTel log bridge and RUM are "not built yet". Application logs are stdout in a Log Analytics workspace with 30-day retention. The 5xx alert is edge-only with a count threshold (>100 in 15 minutes) that does not scale with traffic, and there is no alert on portal or egress errors, LLM upstream failure rate, or `upstream_throttled` outcomes even though the spans record them.
- **Evidence:** `docs/features/observability.md` "What consumes it" and "Not built yet" (lines ~298-345); `TODO.md:147`; `infra/azure/modules/aca-environment.bicep:34` (`retentionInDays: 30`); README alert table (`-alert-edge-5xx`).
- **Why it matters:** The first customer question ("is it up and how fast") has no defined measure; the first incident has no dashboard to open. A 30-day log window is short for security investigation.
- **Recommendation:** Define two or three SLIs (edge availability, LLM gateway success rate, deploy success), add a workbook, add alerts on egress and LLM error ratios, and set log retention to the period the security posture needs.

### OPS-12 Bus factor: one author, operational knowledge in long prose, no ownership structure
- **Severity:** High **Status:** Confirmed **Area:** Ownership
- **What:** 556 of 564 commits come from one author since 2026-06-11. There is no CODEOWNERS file, no dependabot or renovate config, and `.github/` holds only the three workflows. Operational knowledge is in the infra README (1,340 lines of mixed install steps and gotchas), the ADR amendments, and the code comments, with dated "verified" claims in prose. Many procedures require interactive `az` commands and throwaway jobs (`create-roles.sh` is run-once, role-password changes need a hand-made job).
- **Evidence:** `ls /Users/lancerogers/campaigns/azx/projects/helix/.github` (workflows only); `wc -l infra/azure/README.md` (1340); `git log --oneline | wc -l` (564); `infra/azure/scripts/create-roles.sh`; README step 4 ("run-once", "don't re-run the script").
- **Why it matters:** A new team can reproduce an install by reading carefully, but cannot tell which statements are current. Run-once scripts and hand-built jobs are exactly the steps that get lost.
- **Recommendation:** Split the README into install, upgrade, operate and troubleshoot; mark each gotcha as current or fixed; add CODEOWNERS and dependency update automation; add an on-call and escalation page. Have a second engineer perform a clean install and a restore from the docs alone and fix what breaks.

### OPS-13 Data retention and deletion are open items
- **Severity:** Medium **Status:** Confirmed **Area:** Data
- **What:** `gateway_calls` has no DELETE grant for any role and no pruning job, and it holds request paths and identifying fields. Connection-secret erasure under `kv-connections` is a soft delete with purge protection and 90-day retention. Both appear as open items; one runbook covers user labels and erasure.
- **Evidence:** `TODO.md:89` (connection-secret erasure), `:141` (metering ledger retention/GDPR); `infra/azure/modules/keyvault.bicep:49-50`; `infra/azure/README.md` ("Audit-log shipping to immutable blob" descoped).
- **Why it matters:** A deletion request cannot be fully honoured on the current design, and unbounded ledger growth interacts with the 32 GB disk and the storage alert (85%).
- **Recommendation:** Decide retention periods and implement a pruning/erasure path before onboarding customers with data-deletion obligations.

### OPS-14 Cost controls are notify-only; per-app LLM budget is optional and unlimited by default
- **Severity:** Medium **Status:** Confirmed **Area:** Cost
- **What:** Azure budgets notify and never enforce. The firewall is about 88% of the expected bill (README table: ~$125 baseline, ~$920 firewall). The real LLM control is the per-app `dollarsPerDay`, checked once at admission; an app without a number has no cap, and the doc says that is the most permissive state. The `platformMonthlyUsdCap` is display-only. Budget data lags 8-24 hours.
- **Evidence:** `infra/azure/README.md` "Cost" and "Azure AI Foundry" sections; `docs/features/llm-gateway.md:35-46`.
- **Why it matters:** A runaway or malicious approved app can burn vendor spend within one day before an email arrives. The firewall cost is fixed regardless of load, which matters to a customer-per-install model.
- **Recommendation:** Require a default per-app daily budget and an install-wide daily ceiling enforced at the gateway, and consider the Basic firewall tier or an alternative egress design for small installs.

### OPS-15 Cold start during a database outage blacks out the edge (ADR-0025 item 3 still open)
- **Severity:** Medium **Status:** Confirmed **Area:** Resilience
- **What:** A replica that cannot reach Postgres at boot never loads the registry and returns 503 for all apps while `/health` may read green. ADR-0025 lists this as open (items 3 to 5). Combined with single-replica scaling (OPS-7) and a restart caused by maintenance, a DB blip becomes a full edge outage.
- **Evidence:** `docs/adr/0025-registry-projection-hardening.md` Decision item 3 and the status line ("items 1-2 implemented; 3-5 open").
- **Why it matters:** The documented fail-static stance only holds for replicas that were already loaded.
- **Recommendation:** Close item 3 (persisted last-good snapshot or startup retry with an explicit degraded state), and test a rolling restart during a simulated DB outage.

### OPS-16 CI/CD is manual-only, so nothing gates a deploy today
- **Severity:** Medium **Status:** Confirmed **Area:** Release
- **What:** Since 2026-10-08 `ci.yml`, `docs.yml` and `release-cli.yml` run only on manual dispatch. The publish path (`images` job) depends on `static`, `test` and `browser-lane`, so a manual run is still gated, but a deploy by `az` does not require a CI run. The README says "CI builds and publishes ... on pushes to the default branch", which is no longer true. The Bicep compile job "gates nothing" by design (`ci.yml` header). There is no image scanning, SBOM or signing step in `ci.yml`, and actions are pinned to major tags, not SHAs.
- **Evidence:** `.github/workflows/ci.yml:61-65, 461-466`; `infra/azure/README.md` step 3; `grep -n "cosign\|trivy\|sbom\|attest" .github/workflows/ci.yml` returns nothing.
- **Why it matters:** Whoever has `az` rights can deploy an image no CI run validated, and the docs and process disagree about what happens on merge. Re-enable triggers (or a self-hosted/cheaper runner) before treating `main` as releasable.
- **Recommendation:** Restore triggers on a cost-appropriate scope (for example PR plus `v*` tags only), make the production deploy depend on a successful image build for the exact tag, and update the README step 3 wording.

### OPS-17 Images run TypeScript through tsx at runtime, with no container healthcheck, and pnpm in the start chain of the Dockerfile
- **Severity:** Low **Status:** Hypothesis **Area:** Release, resilience
- **What:** The Dockerfiles run non-root (`USER node`) and start the app with `CMD ["pnpm", "--filter", ... "start"]`, which runs `node --import tsx src/server.ts`. The shutdown documentation says the Node process must receive SIGTERM; this depends on pnpm forwarding the signal to its child, which was not verified here. There is no `HEALTHCHECK`. Base images are `node:24-bookworm-slim` by tag, not digest.
- **Evidence:** `apps/edge/Dockerfile:25-36`, `apps/portal/Dockerfile:67-69`, `apps/egress/Dockerfile:25-27`; `apps/edge/package.json:9`; README "Container shutdown".
- **Why it matters:** If pnpm does not forward SIGTERM, the graceful drain falls back to SIGKILL at 30 s and in-flight LLM calls are cut. Floating base tags make rebuilds non-reproducible.
- **Recommendation:** Verify with a SIGTERM test against the built image (a drain log line should appear); consider `CMD ["node", "--import", "tsx", ...]` directly and digest-pinned bases.

## Missing for production / staff-level quality

- **A staging environment and a promotion path** (parameter file, separate resource group, smoke test, approval gate). Without it every change is tested in production.
- **A rollback procedure** for app releases and for schema changes, including the expand/contract migration policy the forward-only job implies.
- **A tested disaster-recovery plan** with stated RPO and RTO, restore drill results, and Blob protection.
- **On-call arrangements and escalation**: who receives severity 0, how, and what the first ten minutes look like.
- **Alert-to-runbook links** and incident runbooks (OPS-5).
- **SLOs and a dashboard** (OPS-11), plus a capacity model: connection budget per replica (ADR-0025 item 4 estimates about 30 replicas on `max_connections=100`) against the intended scale.
- **Image supply-chain controls**: digest pinning, scanning, SBOM, signing. Images come from a public GHCR owner (`AZX-PBC-OSS`) by default in the parameter file; for a private fork the pull path and package visibility need an explicit decision (README step 3).
- **Deploy identity design**: a least-privilege pipeline principal, so deploys do not require human Contributor on the resource group (OPS-10).
- **Abuse and cost kill-switch** at the platform level (per install daily spend ceiling, suspend app, suspend tenant).
- **Operational ownership**: second maintainer, CODEOWNERS, dependency update automation (50 outdated packages, 9 major per the brief).

## Open questions

- What availability target is the customer-deployed model (ADR-0028) promising? That decides OPS-1, OPS-7 and OPS-8.
- Who deploys to a customer install, with which identity, and from where, now that CI triggers are off?
- Does the `helix-prod` install host real customers today, or only the reference deployment? The README repeatedly refers to "both installs"; the committed parameters carry placeholder subscription ids.
- Is pnpm forwarding SIGTERM in the built images (OPS-17)? Needs a container test, which this review did not run.
- Are `alertEmails` and `acmeServer` set through a parameter file kept outside the repo? If so, OPS-4 and OPS-6 describe the repo defaults only; live state was not inspected.
