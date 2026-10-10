# Decisions

_Step:_ DECIDE. Each decision lists the recommended answer, the tradeoff, and the design it comes from. **Status** is `pending` until the owner answers; the answer and who gave it are recorded when it arrives.

## Decisions that shape the rest

| # | Decision | Recommended | Tradeoff | Source | Status |
| --- | --- | --- | --- | --- | --- |
| D1 | **Audience.** One trusted organization per install, or app authors who may be hostile? | Treat authors as possibly hostile: ship both containment parts and make the platform spend ceiling required. | If every author is a trusted employee, containment is mostly insurance and documenting the residual is a legitimate answer. | Frame 1; 01 Q1; 02 Q1 | **decided:** Possibly hostile (owner, 2026-10-08) |
| D2 | **Live installs.** Roll the changes out to the two existing installs, or only to installs built from this fork? | Both, staged: build and prove each change on a new install first, then take it to the live installs once there is access to their deployments repo and Azure subscriptions. | The live installs carry the real risk, but every change there needs that access, and the domain move changes every app URL. | Frame 2; 02 Q3; 03 Q2 | **revised:** no rollout to the live installs; deliver the fixed code plus rollout notes for their operators (owner, 2026-10-08) |
| D3 | **Network egress tier.** What control goes behind the SSRF filter? | Fix the SSRF block list and add NSGs on every install now; offer the firewall FQDN allow-list as an opt-in tier for installs with outside authors. | NSGs cannot stop exfiltration to an arbitrary public host. The allow-list can, but costs the firewall's running cost (about 920 USD per month for Standard per `main.bicep:347-351`) and adds an operator step to every new approved origin. | Frame 3; 03 Q1 | **decided:** NSGs + SSRF fixes, allow-list opt-in (owner, 2026-10-08) |
| D4 | **Cut-stream charging.** What does the ledger charge when a stream ends without final usage? | Measured input, else an estimate; output as the larger of measured and a byte-count estimate; the row marks it as estimated. | Counting only measured tokens never over-charges, but charges a deliberate hang-up almost nothing. An estimate can be off by tens of percent. | Frame 4; 01 Q2 | **decided:** Measured, else estimate (owner, 2026-10-08) |

## Smaller decisions

**Spend controls (01-spend-controls.md)**

| # | Decision | Recommended | Status |
| --- | --- | --- | --- |
| S1 | Approved apps with no budget on the live installs | List them, set explicit numbers, then deploy the $50 default | recommended default; owner did not object (2026-10-08) |
| S2 | Starting values (not measured) | $50 default per app; platform daily ceiling about one tenth of `platformMonthlyUsdCap` ($100 per day on the $1,000 default); 10 concurrent LLM calls per app; 3 per user; 10-minute call deadline | recommended default; owner did not object (2026-10-08) |
| S3 | Owner of the definer function | A `SELECT` policy for the migration owner role; check against `infra/azure/sql/01-roles.sql` first | recommended default; owner did not object (2026-10-08) |
| S4 | Same default and ceiling for `writesPerDay` and `fetch.requestsPerDay` | Not in this change | recommended default; owner did not object (2026-10-08) |

**Containment (02-app-containment.md)**

| # | Decision | Recommended | Status |
| --- | --- | --- | --- |
| C1 | Apps domain per install, and who owns its DNS and Public Suffix List submission | A separate registrable domain per production install; a delegated subdomain only where the customer will PSL-list it. Needs actual domain names. | **decided:** not chosen by this work; the split is per-install configuration, tested locally only (owner, 2026-10-08) |
| C2 | Image breakage | Default-tight `img-src` after a Report-Only measurement window, with the approval path and `EDGE_IMG_SRC_EXTRA` for exceptions | recommended default; owner did not object (2026-10-08) |
| C3 | Image origins as their own capability | Not yet; decide from the Report-Only data | recommended default; owner did not object (2026-10-08) |
| C4 | Legacy redirect from old app hosts | Yes, off by default, retired when `INSTR_LEGACY_APP_REDIRECTS` reaches zero | recommended default; owner did not object (2026-10-08) |
| C5 | A second dev domain (wildcard to 127.0.0.1, ideally a different registrable domain) | Yes, at least for one staging install | recommended default; owner did not object (2026-10-08) |
| C6 | Narrow the CDN script list | Not in this change; open a separate decision on per-app `scriptOrigins` | recommended default; owner did not object (2026-10-08) |

**Network egress (03-egress-network-control.md)**

| # | Decision | Recommended | Status |
| --- | --- | --- | --- |
| N1 | Test NSG attachment on a scratch copy before touching a live install | Yes, in a scratch resource group | recommended default; owner did not object (2026-10-08) |
| N2 | Fixed private-endpoint IPs for the two Key Vaults | Yes, so the NSG can name them instead of the whole endpoint subnet | recommended default; owner did not object (2026-10-08) |
| N3 | Generate the allow-list from approvals | Not yet; ship a static list plus a drift check (`just infra egress-hosts`) | recommended default; owner did not object (2026-10-08) |
| N4 | Reachability probe as a deploy gate or an alert | An alert plus an explicit `just infra net-verify` step in the operator runbook | recommended default; owner did not object (2026-10-08) |
| N5 | An NSG on `snet-apps` for lateral movement | Defer | recommended default; owner did not object (2026-10-08) |

## Delivery and verification

| # | Decision | Answer | Status |
| --- | --- | --- | --- |
| V1 | Where the work lives | The private `lancekrogers/helix` remote for now. CI stays off, so every change is proven with `./check-and-lint.sh` in the dev container. | **decided** (owner, 2026-10-08) |
| V2 | Testing the domain split | Local only, with a second loopback domain inside the dev environment | **decided** (owner, 2026-10-08) |
| V3 | Disclosure and sending the work to AZX | Handled by the owner; out of scope for this plan | **decided** (owner, 2026-10-08) |
| V4 | Verifying the Azure-specific changes (NSGs, firewall rules, Container Apps subnet behavior, `168.63.129.16`) | Local containers only. Application code is proven in the dev container and the smoke runner; NSG rule logic is simulated with Docker network isolation; Bicep is compile-checked. Azure-only behavior ships labeled **unverified in Azure**. | **decided** (owner, 2026-10-08) |

## Changes during execution

| Date | Change | Why |
| --- | --- | --- |
| 2026-10-09 | CT-1 keeps `link` out of the response-header blocklist (7 headers, not 8). | Browsers do not act on a `Link` header in a `fetch()` response, so stripping it protects nothing and breaks vendor pagination (`rel="next"`). |
| 2026-10-09 | SP-6: removing an explicit LLM cap stays an elevated (approval-required) change. The design called it a reduction to the install default. | The approval classifier runs in the portal, which cannot see the edge's install default. On an install with the default disabled (0) or above $50, treating removal as baseline would let an app author become unlimited without approval. |
| 2026-10-09 | Sequence 01 review R-2: bound cut-call charges (a hung-up call is charged no more than a completed call could cost), require approval for brand-new LLM grants and for capabilities at app creation (S-5, S-6), and sanity-check the platform ceiling against the per-app default. Per-app fairness at the ceiling is not built. | Owner decision. The review showed one tenant could trip the shared ceiling for all apps with estimated charges from hung-up calls on self-created, unapproved apps. |
| 2026-10-09 | S-6 (app creation skips the approval classifier, pre-existing) is fixed in sequence 01, not filed. | Owner decision: it defeats the spend controls for new apps. |
| 2026-10-10 | EG-4: pinning private-endpoint addresses is opt-in (`pinPrivateEndpointAddresses`, default false); with it off the endpoints keep dynamic addresses and the template emits no `ipConfigurations`. New installs should turn it on; the NSG (EG-5) names the pinned addresses when on and falls back to the whole `snet-pe` prefix when off. N2 assumed pinning everywhere. | Applying fixed addresses to an existing install changes live private endpoints; Azure may not allow that after creation (unverified), which would fail every existing install's next deployment. |
| 2026-10-10 | EG-5: the egress NSG defaults to `deny-list-only` (the deny rules for private ranges, platform addresses, and other subnets, without the closing deny-all); `enforce` is recommended for new installs and for existing ones after `just infra net-verify` passes. The NSG is still created on every install, as D3 requires. | The platform-flow allow rules are unverified in Azure; a closing deny-all that misses one would cut egress on an existing install's next deploy. The deny list carries the SSRF-backstop value either way. |
| 2026-10-10 | EG-8: the probe's `wire-server-80`, `wire-server-32526` and `imds-80` checks are informational in every NSG mode. The design expected `blocked` with the NSG on. | Azure documents that NSGs do not filter 168.63.129.16 on ports 80 and 32526, and filter IMDS only through the `AzurePlatformIMDS` service tag, not an address prefix. The EG-5 rules deny by prefix, so on a default (`deny-list-only`) install the probe would fail every run and trip EG-9's alert. The application block list in `ssrf.ts` is the only control on these addresses. Sources and detail: `001_IMPLEMENT/02_network_egress/results/eg8-probe-entry-point.md`. |
| 2026-10-10 | Sequence 02 review (IT-6): the EG-5 reasoning that `deny-list-only` is "safe on upgrade" was wrong as built. Changes: the inbound apps-subnet allow adds the ILB backend ports 31080 and 31443; `deny-vnet-in` and `deny-cgnat` move to `enforce` only; the `deny-wire-server` row is deleted. `deny-list-only` stays the default (D3) but is now outbound-only, with rows that are documented by Microsoft or already enforced by `ssrf.ts`. Existing installs hold `egressNsgEnforce = 'off'` until the scratch-copy test and `net-verify` pass (IT-7 rollout notes). | Microsoft's Container Apps NSG page documents the edge proxy behind the ILB on 31080 and 31443, so the old inbound deny cut edge→egress on every apply. The same page says not to deny 168.63.129.16. The 100.64.0.0/10 deny was a hypothesis row with no proxied-traffic value. Attaching an NSG to a populated subnet is a risk in any mode. Detail: `review-02-network-egress.md`, `it6-nsg-table-fixes.md`. |
| 2026-10-10 | IT-6: with pinning on, the NSG allows egress to reach kv-platform. The design expected kv-platform `blocked` from egress. | Egress takes three secrets as Key Vault references to kv-platform. Container Apps fetches them from `snet-egress`, inferred because kv-platform is private-endpoint-only on working installs. Blocking the vault breaks egress. The egress identity holds Key Vault Secrets User on the whole vault (`rbac.bicep`), so the network layer could never have stopped an egress compromise from reading platform secrets. The real fix, per-secret grants or a separate egress-only vault, is follow-up work. |
| 2026-10-10 | CT-3 keeps a measurement mode: `EDGE_IMG_SRC_REPORT_ONLY` (default false) reproduces CT-2's headers (open enforced `img-src`, tight Report-Only), byte-identical for `https:` approved origins. Non-`https`/`wss` and wildcard-host origins are dropped in every mode (sequence 03 review R-3, G-1). The default is the tight enforced policy; `EDGE_IMG_SRC_ALLOW_ALL` is the permanent relaxation; setting both refuses to boot. The task said "no Report-Only header in any mode". | The design assumes two releases with a measurement window between them. This fork is delivered as one `main` (D2): CI is off, images are built per commit by the operator, and the domain split lands after CT-3, so a "deploy the CT-2 commit first" step cannot be followed. Reusing `ALLOW_ALL` as the measurement mode would fill a permanently relaxed install's Violations screen with report rows. A separate flag keeps the window, and the tight default stays. |
| 2026-10-10 | Sequence 03 review (IT-8): the edge fetch route refuses worker, shared-worker and service-worker loads and any `Service-Worker` request. Proxied responses get `content-security-policy: default-src 'none'`. `service-worker-allowed` and `alt-svc` join the response blocklist. Approved `wss:` origins stay in `connect-src`. | R-1 was a pre-existing gap: the proxy served an approved upstream's bytes on the app origin with no CSP, relayed `Service-Worker-Allowed`, and did not refuse a service-worker registration. That reopened the handoff-token exposure the asset path closes, and bypassed the image-channel policy. R-3: CT-3's https-only `originSources` dropped `wss:` origins, which would break WebSocket apps. |
