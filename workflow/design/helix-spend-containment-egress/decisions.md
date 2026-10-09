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
