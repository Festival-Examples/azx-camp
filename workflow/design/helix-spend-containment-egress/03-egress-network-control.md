# Network egress control behind the SSRF filter

_Problem:_ Problem 3 in [00-frame.md](00-frame.md) (no network-level egress control). _Findings:_ OPS-9 (`notes/08-operability.md`), SEC-7 (`notes/07-security.md`), S10 (`notes/03-decisions.md`, ADR-0005 stale record).

## Summary

Decision D3 applies: fix the SSRF block list and put an NSG on `snet-egress` on every install; the firewall FQDN allow-list is an opt-in tier for installs that run `deployFirewall = true`. Layer 1 (application) closes the gaps in `ssrf.ts` (Azure's `168.63.129.16`, documentation ranges, the 6to4 relay anycast block, IPv6 documentation/SRv6 blocks) and adds a deployment-supplied extra block list so a non-RFC 1918 VNet is covered. Layer 2 (subnet) puts an NSG on `snet-egress` that allows only what egress needs (Postgres, its two Key Vault private endpoints at fixed IPs, DNS, Internet on 80/443, the ACA platform tags) and denies everything else, including the other planes and the platform addresses. Layer 3 (firewall, opt-in) replaces `targetFqdns: ['*']` with an allow-list built from a static platform list plus an operator parameter, sets threat intelligence to Deny, and sends firewall logs to Log Analytics; the list is not generated from approvals (N3), and a drift command (`just infra egress-hosts`) shows the operator what to add. Layer 4 is a Container Apps Job in the egress environment that tries to connect to each forbidden and each required destination and fails on any surprise, started by `just infra net-verify`. Important honest limit: the NSG and the firewall cannot protect Postgres or the two vaults from an SSRF bug, because egress legitimately talks to those; only layer 1 and the lack of credentials on a bare request do that.

**What this work can prove.** Nothing here is deployed to Azure or to the two live installs. The application layer is proven in the dev container (`./check-and-lint.sh`, `just check`, and the smoke runner). Bicep is compile-checked with `just infra build`. The NSG rule set's logic is simulated locally with Docker network isolation (see "Local simulation"). Everything that only Azure can show is labeled **unverified in Azure**: that an NSG can be attached to a populated Container Apps subnet, which flows the platform needs, how `168.63.129.16` behaves, the source address the ILB sees, and the firewall's runtime behavior.

## Current behavior

**Topology.** There are two Container Apps environments on two subnets, not one. `appsEnv` (edge, portal, the opt-in dev-gateway, the certbot and migrate jobs, the apps OTel collector) sits on `snet-apps`; `egressEnv` (egress and the egress OTel collector) sits on `snet-egress` (`infra/azure/main.bicep:752-775`, collectors at `main.bicep:816-832`, egress app at `main.bicep:1044`, certbot and migrate on `appsEnv.outputs.environmentId` at `main.bicep:1495, 1527`). `network.bicep:4-8` states the reason: ACA binds one infrastructure subnet per environment. The egress environment is `internal: true` (`aca-environment.bicep:49-52`; `main.bicep:765-771`), and the egress app uses `external: true`, which in an internal environment means "reachable from the VNet" so the edge in the other environment can call it (`main.bicep:1039-1065`, comment). The subnets are `AzureFirewallSubnet` 10.0.0.0/26, `snet-apps` 10.0.2.0/23, `snet-egress` 10.0.4.0/23, `snet-postgres` 10.0.6.0/24, `snet-pe` 10.0.7.0/24 (`network.bicep:32-36`); the VNet prefix is a parameter (`network.bicep:27`).

**No NSGs.** No `networkSecurityGroups` resource exists in `infra/azure` (frame, Problem 3; SEC-7). Subnet association of the route tables is done inline in the VNet (`network.bicep:10-11, 59-61, 79-81`); `network.bicep:10-11` notes that Azure rejects late route-table association once a subnet holds ACA infrastructure. **Hypothesis:** the same restriction may apply to attaching an NSG to an existing, populated ACA subnet; this decides how an operator of an existing install adopts layer 2 (see Operator rollout notes).

**Routing.** `routing.bicep:12-14` says edge-to-egress traffic uses the system VNet route and never touches the firewall. The same is true of every VNet-local destination: private endpoints, Postgres, the other planes' load balancers. The firewall only sees internet-bound traffic. So the firewall can never be the control against SSRF into private ranges; that is what NSGs are for.

**Firewall (only when `deployFirewall`).** The module is conditional (`main.bicep:507-517`), default `true` (`main.bicep:371-372`); the live installs run `false` (ADR-0005 accepted-risk record, 2026-09-22, as quoted in S10). The egress subnet's rule is `targetFqdns: ['*']` on 80 and 443 (`firewall.bicep:100-113`). Threat intel is `Alert` (`firewall.bicep:84`). A second rule collection allows `acaPlatformFqdns` for **both** subnets (`firewall.bicep:37-64, 125-136`); it includes `*.blob.core.windows.net` and `login.microsoftonline.com`, which are attacker-usable for exfiltration from any tenant or storage account. The list has no entry for Microsoft Graph (the portal's directory client uses `https://graph.microsoft.com`, `packages/directory/src/entra.ts:29-31`), for the ACME directory or Azure Resource Manager (certbot runs in `appsEnv`, `main.bicep:1485-1495`, with an ACME server URL param at `certbot.bicep:67-68`). **Hypothesis:** with the firewall on, those three would be dropped on `snet-apps`; I did not trace the portal's and certbot's actual outbound hosts. The README already says the Key Vault reference path needs the `AzureKeyVault` tag and Entra on the list and that "neither install runs the firewall today; add these before it comes back" (`infra/azure/README.md:269-273`), which is the same problem: the allow-list was never exercised for the platform's own dependencies.

**Cost as recorded in the repo.** The template says the firewall adds about 920 USD per month on top of about 125 USD for a small install (`main.bicep:347-351`), and the README says Basic tier is "~$290/mo, same FQDN model" (`infra/azure/README.md:96-98`). I quote those only as the repo states them.

**Application filter.** `isBlockedAddress` (`ssrf.ts:139-153`) blocks, for IPv4: `0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.0.0.0/24, 192.168/16, 198.18/15, 224/4, 240/4` (`ssrf.ts:41-53`). For IPv6 it blocks `::1, ::, fe80::/10, fec0::/10, fc00::/7, 64:ff9b:1::/48, 100::/64, 2001:db8::/32, 2002::/16, 2001::/23, ff00::/8` (`ssrf.ts:115-127`), and re-checks the embedded IPv4 of `::ffff:0:0/96`, `64:ff9b::/96` and `::/96` (`ssrf.ts:146-148`). Anything that is not an IP literal is refused (`ssrf.ts:151-152`). The check runs on every resolved address and the connector pins the socket to a validated address (`ssrf.ts:168-193, 218-273`). Gaps found by reading the lists:

| Range | Why it matters | Blocked today |
|---|---|---|
| `168.63.129.16/32` | Azure virtual public IP (wire server, platform DNS, health probes). SEC-7 says reachability from a Container Apps workload is untested. | No |
| `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` | IPv4 documentation (TEST-NET-1/2/3). Not routable on the internet, but a fixture or misconfigured private routing could land there. | No (v6 documentation `2001:db8::/32` is blocked, v4 is not) |
| `192.88.99.0/24` | Deprecated 6to4 relay anycast. v6 `2002::/16` is blocked wholesale, so v4 parity is missing. | No |
| `3fff::/20` | IPv6 documentation (the 2024 allocation). | No |
| `5f00::/16` | IPv6 segment-routing SIDs. | No |
| `::ffff:0:0:0/96` | IPv4-translated (SIIT). Not extracted by the mapped/NAT64/compat branches, so `::ffff:0:7f00:1` is treated as public. **Hypothesis:** not routed to IPv4 by a Linux socket, so this is hygiene. | No |
| The install's own VNet prefix | `vnetAddressPrefix` is a parameter (`network.bicep:27`). A customer who picks a public-looking range (for example a range they own) gets no application-level block for it, because the list is hard-coded RFC 1918. | Only if inside RFC 1918 |

The comment on `2001::/23` says it covers ORCHIDv2 (`ssrf.ts:125`). I checked the arithmetic: `2001:10::/28` and `2001:20::/28` fall inside `2001::/23`, so that is correct. The IANA special-purpose registry has further small entries (AS112, AMT, and others); take those from the registry itself when implementing, not from memory. I did not open it.

Existing tests: `ssrf.test.ts` covers the IPv6 table (`ssrf.test.ts:25-52`), public IPv6 targets, zone ids, an IPv4 regression table of only seven addresses (`ssrf.test.ts:72-88`), the URL-normalised alternate literals, DNS-rebind via a mocked `lookup`, and connector dial order. `adversarial.test.ts` has an "egress SSRF hardening" suite (`adversarial.test.ts:139`). No test checks a boundary (first and last address of a range, the address just outside) and no test is tied to the block list as a whole.

## Goals and non-goals

Goals:

1. An egress compromise or SSRF filter bug cannot reach the other planes, the platform addresses, or private ranges beyond Postgres and the two vaults egress uses.
2. These controls work with `deployFirewall = false`, which is the posture of the live installs.
3. With the firewall on, the internet destination set is an allow-list, not `*`.
4. A deployed install can prove which controls are on, from the egress subnet, by an automated check.

Non-goals:

- Stopping exfiltration to a host the allow-list must permit (an approved origin, an LLM vendor). That is the approval classifier's job (ADR-0016).
- Blocking DNS tunnelling through the Azure resolver. **Hypothesis:** it is possible and out of scope.
- Reworking the instruction seam (ADR-0013) or the CSP channels (Problem 2).
- A response-side or per-app control. Network layers see the egress plane as one workload.

## Layer-by-layer: what each one protects and costs

| Layer | Protects against, if the SSRF filter has a bug | Does not protect against | Cost or breakage |
|---|---|---|---|
| 1. Application (`ssrf.ts`) | Everything, when correct; it is the only layer that knows the app's intent and sees resolved IPs. A bug here is the premise. Extra ranges shrink what one bug exposes. | Its own parsing or logic bugs; a range it does not list. | No infrastructure cost. A wrongly added range blocks a real vendor (none of the new ranges are routable to a vendor). |
| 2. NSG on `snet-egress` | Private ranges, platform addresses, the apps subnet and its ILB, `kv-platform` and blob private endpoints, ports other than 80/443 on the internet. Works when the firewall is off. | Postgres, the two vaults egress uses (egress needs them, so the NSG must allow them), and any internet host on 80/443. | Not a firewall-style hourly resource; **Hypothesis:** no separate charge, confirm in the Azure pricing page before telling an owner. Breaks any approved origin on a non-standard port (already broken when the firewall is on, `firewall.bicep:109-112`). Risk of breaking ACA platform traffic if a required rule is missing; see below. |
| 3. Firewall FQDN allow-list | Exfiltration to arbitrary internet hosts after a compromise, and fetches to hosts nobody approved. | Anything VNet-local (routing.bicep:12-14). Hosts that must stay allowed (blob wildcard, Entra, approved origins). SNI/Host mismatch: **Hypothesis** that an application rule without TLS inspection sees only the SNI, so a client that connects to an arbitrary IP with an allowed SNI passes. | The flat firewall cost in `main.bicep:347-351` (not repeated here). A new approved origin is unreachable until the list contains it. Threat-intel Deny needs Standard tier or higher: **Hypothesis** that Basic is alert-only. |
| 4. Probe job | Nothing directly. It detects that layer 2 or 3 is missing or has drifted. | A control that is on but wrong in a way the probe does not test. | One job image command, one scheduled job. Probe traffic is deliberate and harmless. |

## Options

### Application layer plus NSGs on every install, firewall as the optional strong tier (chosen, D3)

Layer 1 and layer 2 are unconditional. Layer 3 and some probe expectations depend on `deployFirewall`. Pros: every install gets a real second layer without the firewall cost, and the control is checkable. Cons: NSG rules for Container Apps cannot be verified in Azure by this work (they ship labeled **unverified in Azure**), and attaching to a populated subnet may not be a pure update. Each stricter behavior is a per-install setting (`egressNsgEnforce`, `egressFqdnMode`, `EGRESS_EXTRA_BLOCKED_CIDRS`) so an install on AZX's documented model (one org per install, ADR-0028) can relax it.

## Options not chosen

- **Application layer only (document the residual).** Rejected: D3 chose NSGs, and leaving a single control in front of the container that holds every connection secret is the state SEC-7 calls out.
- **Replace the Azure Firewall with NAT Gateway plus NSGs.** Rejected: NSGs cannot express FQDNs (`infra/azure/README.md:99-101`), so this is the chosen option with a stable outbound IP, which is not a security gain.
- **Generated FQDN allow-list reconciled from approved origins.** Rejected (N3): it needs a new identity with write access to the firewall policy, a new path from "admin approved an origin" to "infrastructure changed", and a window where an approved origin does not work. Revisit with its own ADR if an install runs the firewall long term.

## Recommendation

Build the chosen option in this order: application layer, NSG, firewall opt-in tier, probe. Reasons:

- The live installs run with the firewall off, and the owner's cost decision stands. NSGs are the only option that improves a firewall-off install without that spend.
- The NSG removes the largest remaining reach of an SSRF bug: VNet-local targets that the firewall never sees.
- The allow-list is the hardest part to keep in sync, and the sync target (approvals at runtime) is not an infrastructure event today. A static list plus drift tooling gets most of the value with none of the new privileged path.
- The two stricter settings default to strict for new installs (NSG enforced, allow-list mode when the firewall is on), and an install on the one-org-per-install model can relax them by parameter.

## Design

### Layer 1: application

Files: `apps/egress/src/ssrf.ts`, `apps/egress/src/config.ts`, call sites of `makeValidatingConnector`.

1. Add to `V4_BLOCKED`: `168.63.129.16/32` (Azure wire server and platform DNS VIP), `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `192.88.99.0/24`. Add to `V6_BLOCKED`: `3fff::/20`, `5f00::/16`, and handle `::ffff:0:0:0/96` by extracting the embedded IPv4 like the mapped form. The hex-embedded variants of `168.63.129.16` are `::ffff:a83f:8110`, `64:ff9b::a83f:8110`, and `::a83f:8110`; all three flow through the existing extraction (`ssrf.ts:146-148`) and so are blocked by the v4 entry, which the test must prove. Take any further special-purpose entries (AS112, AMT) from the IANA registry when implementing; do not hand-key them.
2. Add a deployment-supplied block list. New env `EGRESS_EXTRA_BLOCKED_CIDRS` (comma-separated CIDRs, v4 or v6), parsed in `config.ts` next to the other SSRF knobs (`config.ts:208-212` shows the existing boot-refusal pattern for dev flags). `main.bicep` sets it to `vnetAddressPrefix` (so a non-RFC 1918 VNet is covered) plus the ACA platform-reserved range. Invalid CIDR refuses to start; empty is allowed. The set is parsed once at load into the same numeric form the built-in lists use.
3. Thread the extra list into `makeValidatingConnector(allowPrivate, timeoutMs)` and `isBlockedAddress` as an explicit parameter, not a module global, so tests can vary it. The caller at `proxy.ts:272` is verified; `ssrf.ts:212-216` says the exchange `customFetch` adapter and the provider client build on the same connector (`exchangeTransport.ts`, `providerClient.ts`), so each must receive the same list. The change is compile-checked: a missing caller fails typecheck once the parameter is required.
4. `EGRESS_ALLOW_PRIVATE` keeps its production boot refusal (ADR-0005 hardening note, `config.ts`). `allowPrivate` must bypass the extra list too, and the production refusal must keep covering that.

### Layer 2: subnet NSGs

New file `infra/azure/modules/nsg.bicep`, one NSG per subnet that gets one, referenced from the inline subnet definitions in `network.bicep` (`networkSecurityGroup: { id: ... }` next to `routeTable`). The NSGs are created before the VNet, the same way the route tables are (`routing.bicep:1-8`).

**What ACA requires (read this before enforcing).** I did not read Microsoft's current Container Apps networking page and I made no network calls, so the following is **Hypothesis**, from memory of the documented requirements: a workload-profiles environment needs outbound access within its own subnet and to the Microsoft Container Registry, Azure Front Door (first-party), Entra ID (managed identity), Azure Monitor, and its own platform ranges; inbound from the Azure load balancer; and for a VNet-injected internal environment, inbound from clients on the ILB ports. Before enforcement, an operator must read the current page and fix the list in the table below; this work cannot test it in Azure, so every row marked Hypothesis ships **unverified in Azure**. The template therefore has `egressNsgEnforce` with two modes: deny-list-only (only the **explicit deny rules for the forbidden destinations** are active, leaving the default allow-internet behaviour) and enforce (adds the closing deny-all). The operator moves from the first to the second only after the probe passes on their install (see Rollout).

Proposed `snet-egress` outbound rules (lower number first). Rows 100-140 are allows; 200-240 are the deny list; 300 is the internet allow; 4000 closes.

| Pri | Dir | Rule | Why | Status |
|---|---|---|---|---|
| 100 | Out | Allow `10.0.4.0/23` (own subnet), any | ACA replicas, ILB, sidecars talk inside the subnet | Hypothesis |
| 110 | Out | Allow `10.0.6.0/24` TCP 5432 | Postgres (`snet-postgres`) | Known need (`EGRESS_DATABASE_URL`, `main.bicep` egress env block) |
| 120 | Out | Allow the `kv-connections` and `kv-delegated` private-endpoint IPs, TCP 443 | Egress reads/writes both (`AZURE_KEY_VAULT_URL`, `AZURE_DELEGATED_KEY_VAULT_URL`, egress env block in `main.bicep`) | Known need; fixed PE IPs (N2), see below |
| 130 | Out | Allow `168.63.129.16/32` UDP+TCP 53 | Azure DNS; egress resolves every target itself (`ssrf.ts:183`) | Hypothesis that DNS goes to this address from a Container Apps replica |
| 140 | Out | Allow service tags the platform needs (MCR, Front Door first-party, Entra, Azure Monitor), TCP 443 | ACA platform | Hypothesis; fix against current docs |
| 200 | Out | Deny `168.63.129.16/32`, any (all ports other than 53 by priority) | Wire server, health probe VIP | Hypothesis that the wire server answers from the workload; the deny is safe either way |
| 210 | Out | Deny `169.254.0.0/16`, any | IMDS and link-local | Safe: managed identity uses the local `IDENTITY_ENDPOINT` (`managedIdentity.ts` in egress; not opened), not 169.254 |
| 220 | Out | Deny the VNet prefix, any (placed after 100-130) | Apps subnet, `kv-platform` and blob PEs, the firewall subnet, anything else in the VNet | The core rule |
| 230 | Out | Deny `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Peered or on-prem ranges, a customer VNet not in `10.0.0.0/16` | Safe |
| 240 | Out | Deny `100.64.0.0/10`, any | RFC 6598; ACA draws ingress pod addresses from here (`main.bicep:438-451` comment, measured 2026-09-03) | **Hypothesis: may break ACA platform traffic.** Test last; if it breaks, scope it to exclude `100.100.0.0/17`. |
| 300 | Out | Allow Internet TCP 80, 443 (port list is a parameter) | Vendors, providers, approved origins | Matches the firewall rule's ports (`firewall.bicep:109-112`) |
| 4000 | Out | Deny any | The default `AllowInternetOutBound` would otherwise let egress dial any port on the internet | Active only when `egressNsgEnforce` = enforce |

Inbound on `snet-egress`: allow `10.0.2.0/23` (the apps subnet: edge and portal both call egress) on the ILB ports, allow the Azure load balancer, allow own subnet, and deny the remainder of the VNet. **Hypothesis:** the NSG sees the edge's subnet address as the source; if the environment's outbound proxying changes the source, the allow rule must name that range instead. The probe's positive control (edge-to-egress works) catches this.

**Private-endpoint IPs.** NSG rules need destination addresses; private endpoints get dynamic ones today (`private-endpoint.bicep:25-42` sets none). N2 is decided: add an optional `privateIpAddress` to `private-endpoint.bicep` (`ipConfigurations` on the endpoint) and fixed values for the vault endpoints. **Hypothesis:** the property is supported on the current API version; `just infra build` proves the template compiles, not that Azure accepts it (**unverified in Azure**). Changing the address of an existing endpoint is a one-time endpoint update for an operator (see Rollout). Without fixed addresses, rule 120 would have to be the whole `snet-pe` `/24`, which lets an SSRF bug reach `kv-platform` and blob.

**The shared-subnet limit.** Edge, portal, dev-gateway, certbot, migrate and the apps collector all sit on `snet-apps`, because they share `appsEnv` (`main.bicep:752-762`). An NSG on that subnet cannot treat them differently: edge (internet-facing, untrusted traffic) and portal (privileged) share every rule, so a lateral-movement NSG there cannot separate them, and the database role split (ADR-0002) stays the only separator. Egress is the opposite: it is alone in its subnet apart from its own OTel collector, so an NSG there is exactly an egress NSG. This is why layer 2 is specified for `snet-egress` first. An NSG on `snet-apps` is an optional second step: deny outbound to `snet-egress` except the ILB ports, deny to `snet-pe` except what edge needs. It cannot deny general Internet because image pulls from GHCR need FQDN rules that NSGs cannot express (`infra/azure/README.md:99-101`). It is not required to close Problem 3; N5 defers it.

**Private endpoint subnet.** `snet-pe` has `privateEndpointNetworkPolicies: 'Disabled'` (`network.bicep:113`), so an NSG there would not filter traffic to the endpoints. **Hypothesis:** this is the documented behaviour. The egress-side outbound rules above are therefore the control, not an NSG on `snet-pe`.

**Postgres and vaults remain reachable.** Say this in the ADR: with rules 110 and 120, an SSRF bug that dials the Postgres IP or a vault PE IP is not stopped by layer 2. What limits it there is that a bare HTTP request carries no credential (egress adds none except the connection's own secret for the instruction's origin; the request header safelist is in `proxy.ts`, not re-read for this design) and that Postgres is not an HTTP service. That is a reason for the application list, not a gap the NSG can close.

### Layer 3: firewall (only when `deployFirewall`)

**3a. Threat intelligence.** Replace `threatIntelMode: 'Alert'` (`firewall.bicep:84`) with a parameter `threatIntelMode`, default `'Deny'`. **Hypothesis:** Standard supports Deny and Basic does not; check the SKU table before documenting. Cost: a known-bad destination is dropped instead of logged. A false positive on a vendor IP is possible; the diagnostic logs (3d) are how it is found.

**3b. Replace `targetFqdns: ['*']`.** Split the egress rule (`firewall.bicep:103-113`) into two:

- A platform rule for `snet-egress`: the OTel exporter host (`*.in.applicationinsights.azure.com`, already in `acaPlatformFqdns`), the Key Vault reference resolution tags and Entra hosts (`infra/azure/README.md:269-273`), MCR/ACA hosts. This overlaps `acaPlatformFqdns`; split that list per source (`appsPlatformFqdns`, `egressPlatformFqdns`) so the egress subnet no longer inherits GHCR, the blob wildcard, Graph or ACME. **Hypothesis:** ACA image pulls are initiated from the environment's infrastructure through the subnet's route, so the egress subnet still needs MCR and GHCR; confirm with the probe and a revision restart.
- A product rule: LLM vendor hosts, connection-provider hosts, approved fetch origins.

**3c. How the product list is derived.** Sources and where each lives:

| Source | Where it lives | Static or dynamic |
|---|---|---|
| LLM vendor hosts | `EDGE_LLM_ENDPOINT`, `EDGE_LLM_OPENAI_ENDPOINT` on the edge (`apps/edge/src/config.ts:755, 760`, defaults `api.anthropic.com`, `api.openai.com`); Foundry hosts via `EGRESS_MANAGED_IDENTITY_CONNECTIONS` host suffixes (`apps/egress/src/config.ts:140-165`) | Static per install, known at deploy time from Bicep params |
| Connection-provider hosts | `connection_providers.authorizeEndpoint`, `tokenEndpoint`, `apiOrigins` (`apps/portal/prisma/schema.prisma:590-602`) | Dynamic: portal admin creates providers at runtime |
| Approved fetch origins per app | `capabilities.fetch.origins[].origin` (`packages/shared/src/manifest.ts:151-205`), effective after the ADR-0016 approval (a new proxied origin is an elevated delta needing admin approval, `docs/adr/0016-*.md:18`) | Dynamic: changes on every approval |
| Platform dependencies | Key Vault references (ACA-side), Entra login, App Insights, ACME, ARM (apps subnet only), Graph (apps subnet only) | Static per install |

Decision N3: the list is a static Bicep array `egressAllowedFqdns` (defaulting to the vendor hosts and the platform list) plus drift tooling. The operator edits the array. A new approved origin or provider does nothing until the operator changes the parameter and redeploys, so the approval flow has a second step the approver cannot see. To make that step visible:

- `just infra egress-hosts` prints the dynamic hosts (approved fetch origins, provider hosts) from the database, and marks which are missing from the deployed list.
- The probe (layer 4) fails if an approved origin's host is not in the firewall list when `deployFirewall = true` and the mode is `allowlist`.
- The approval screen note ("pending network" when the install runs the firewall allow-list) is not part of this work; it is a portal change and is left to a follow-up decision.

Keep `egressFqdnMode` as an install parameter: `any` (today's behaviour, kept so existing firewall installs do not change on upgrade) and `allowlist`. Default for new installs: `allowlist`. Existing firewall installs stay on `any` until their operator flips it.

**3d. Visibility.** Add a diagnostic setting on the firewall to the apps environment's Log Analytics workspace (`aca-environment.bicep:78-79` exposes its id), and an alert on application-rule denials from the egress subnet, following the pattern in `modules/alerts-infra.bicep` (not read for this design; confirm the pattern first). This is OPS-9's recommendation and is what makes a missing entry visible instead of silent (compare the OTel entry story at `firewall.bicep:50-56`).

**3e. Known leaks that stay open under any allow-list.** `*.blob.core.windows.net` (any storage account, so attacker-owned storage), `login.microsoftonline.com` (any tenant), and every approved origin. Narrow where the platform allows (a specific account host instead of the wildcard if the image-pull path does not need it; **Hypothesis** that MCR layer pulls need the wildcard).

### Layer 4: verification

**A Container Apps Job in the egress environment**, scheduled daily and runnable on demand, named `<prefix>-netprobe`. It must run on `snet-egress` so it exercises the same NSG and route table as egress; a job in `appsEnv` would prove nothing about egress.

- **Image:** the egress image with a `command` override (`containerapp.bicep:69` has the pattern for apps; `migrate-job.bicep` is the job precedent, not opened), running a small entry point that uses only `node:net` and `node:dns`. No new dependency, no new image.
- **Identity:** a dedicated user-assigned identity with no role assignments. The probe must not hold egress's secrets, so its compromise is worthless.
- **Inputs from Bicep, one source of truth:** `PROBE_EXPECT_FIREWALL` (from `deployFirewall`), `PROBE_EXPECT_FQDN_ALLOWLIST`, `PROBE_EXPECT_NSG`, the apps environment's static IP (`aca-environment.bicep:77`), the three vault PE IPs, the Postgres FQDN, and a canary FQDN that is deliberately not in any list.
- **Checks.** For each, the result is `blocked`, `reachable`, or `unresolved`; blocked means a connect **timeout** only, because a TCP reset means the packet reached something and the control is not what stopped it.

| Check | Expected (NSG on) | Expected (NSG off) |
|---|---|---|
| `168.63.129.16:80` and `:32526` (wire-server ports; **Hypothesis**, confirm) | blocked | informational: record whether it answers; this settles SEC-7's open question |
| `169.254.169.254:80` | blocked | informational |
| Apps environment ILB or edge IP, TCP 443 | reachable only if the inbound rule is meant to allow edge-to-egress; the probe checks the egress to apps direction: blocked | informational |
| `kv-platform` PE IP :443 and blob PE IP :443 | blocked | informational |
| `kv-connections` PE IP :443 and `kv-delegated` PE IP :443 | reachable (positive control) | reachable |
| Postgres :5432 | reachable (positive control) | reachable |
| A public host on 443 that is on the allow-list | reachable | reachable |
| A public host on 443, not on any allow-list | blocked if `PROBE_EXPECT_FQDN_ALLOWLIST`, reachable otherwise | reachable |
| A public host on 25, 22 or 8443 | blocked | informational |
| DNS resolution of a public name | resolves (positive control) | resolves |

- **Output:** one JSON line per check with `event: "netprobe"`, expected, actual, and an overall exit code. The job's execution status is the CI-visible result. Wire a scheduled-query alert on failure in the apps alert module family. The recipes go in the existing `.justfiles/infra.just` module (which today has only `build`): `just infra net-verify` starts the job in Azure and prints its result (an operator step, **unverified in Azure** by this work), `just infra net-sim` runs the same probe against the local Docker simulation, and `just infra egress-hosts` prints the drift list. Per N4 the probe is an alert plus an explicit `net-verify` step in the operator runbook, not a deploy gate.
- **Recorded posture:** a `netControls` object output from `main.bicep` (firewall on/off, FQDN mode, NSG on/off, probe expectations). The README and the ADR-0005 accepted-risk record stop restating this in prose and point at the output plus the last probe result. That is the replacement for "the firewall state is only recorded in prose".

### Local simulation (V4)

What runs locally: a Docker network layout that mirrors the subnets, and the NSG rule table applied as packet filters. The rule table is one data file (for example `infra/azure/nsg-egress-rules.json`) that `nsg.bicep` loads with `loadJsonContent` and the simulator reads, so the Bicep and the simulation cannot drift apart.

- **Networks.** Four user-defined Docker networks stand in for `snet-egress`, `snet-apps`, `snet-postgres` and `snet-pe`, plus a "public" network. Target containers sit on them: a stand-in for the apps ILB (listening on 443), Postgres, three vault stand-ins at fixed addresses, a stand-in for `168.63.129.16` (answering DNS on 53 and HTTP on 80 and 32526), a stand-in for `169.254.169.254`, a public HTTPS host on the allow-list, a public host not on it, and listeners on 25, 22 and 8443.
- **Enforcement.** The probe container runs on the egress network with `NET_ADMIN`. A setup step translates the rule table into iptables rules on its OUTPUT chain, one rule per row in priority order, first match wins, with `DROP` for deny rows so a blocked connect times out (matching Azure's NSG behavior of dropping, not resetting). Service tags have no local equivalent and are replaced by named placeholder CIDRs.
- **Run.** `just infra net-sim` builds the probe, applies the table, runs the same probe entry point as the Azure job, and compares the JSON lines to the expected column. It also runs with the table disabled (the "NSG off" column) and with a deliberately broken table (for example rule 130 removed), and requires the probe to fail in that case.

What this proves: the rule ordering and logic (first match, the DNS allow above the wire-server deny, the VNet deny placed after the Postgres and vault allows, the closing deny), that the probe's "blocked means timeout" rule separates a drop from a reset, that the positive controls survive the deny rules, that the probe fails when a rule is wrong or missing, and the probe's own code paths.

What stays **unverified in Azure**:

- Whether an NSG can be attached to a populated Container Apps subnet as an update, or only at environment creation (`network.bicep:10-11` shows the route-table version of this restriction). Docker cannot model subnet association.
- Which flows the Container Apps platform needs (MCR, Front Door, Entra, Azure Monitor, inbound from the platform load balancer), and whether the 100.64.0.0/10 deny in rule 240 breaks ingress pod addressing.
- Whether Azure NSG semantics match the iptables translation: statefulness, the default rules, augmented rules, and service-tag membership.
- The behavior of `168.63.129.16` from a Container Apps replica: whether the wire server answers there, whether DNS goes to it, and which ports. The local stand-in answers because the simulation says it does; it proves the rules, not the address.
- The source address the NSG sees for edge-to-egress traffic through the internal environment's ILB.
- Fixed private-endpoint addresses being accepted by the current API version, and the firewall's runtime behavior (SNI-only matching, threat-intel Deny by SKU, rule collection limits).

## Change by file

| File | Change | Notes |
|---|---|---|
| `apps/egress/src/ssrf.ts` | Add `168.63.129.16/32`, `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `192.88.99.0/24` to `V4_BLOCKED`; `3fff::/20`, `5f00::/16`, IPv4-translated extraction to the v6 path; accept an extra-CIDR list in `isBlockedAddress`, `resolveAndValidate`, `makeValidatingConnector`, `makePinnedDispatcher` | Parameter must be explicit, no module global |
| `apps/egress/src/config.ts` | Parse `EGRESS_EXTRA_BLOCKED_CIDRS`; refuse to start on a bad CIDR | Follow the dev-flag refusal pattern at `config.ts:203-212` |
| `apps/egress/src/proxy.ts`, `exchangeTransport.ts`, `providerClient.ts` | Pass the extra list to the connector | `proxy.ts:272` verified; the other two named in `ssrf.ts:212-216` |
| `apps/egress/src/ssrf.test.ts`, `adversarial.test.ts`, `config.test.ts` | Tests below | |
| `infra/azure/modules/nsg.bicep` (new) | NSG definitions for `snet-egress`, optionally `snet-apps` | Parameters: VNet prefix, subnet prefixes, PE IPs, allowed ports, `egressNsgEnforce` mode; rules loaded from `nsg-egress-rules.json` |
| `infra/azure/modules/network.bicep` | Attach NSG ids to the subnets; PE subnet unchanged | `network.bicep:10-11` caveat on late association |
| `infra/azure/modules/private-endpoint.bicep` | Optional fixed `privateIpAddress` | Needed for rule 120 (N2) |
| `infra/azure/modules/firewall.bicep` | `threatIntelMode` param (default `Deny`); split the egress rule; per-subnet platform lists; add the missing platform FQDNs for `snet-apps` (Graph, ACME, ARM, Key Vault tag, `login.microsoft.com`); diagnostic setting | `firewall.bicep:37-64, 84, 100-136` |
| `infra/azure/modules/netprobe-job.bicep` (new) | Job, identity, schedule, inputs | Pattern from `migrate-job.bicep`, not opened |
| `apps/egress/src/netprobe.ts` (new) and its test | Probe entry point using `node:net` and `node:dns`, check table, JSON output | Run by the job via `command` override and by the local simulation |
| `infra/azure/nsg-egress-rules.json` (new), `infra/netsim/` (new) | Single rule table; Docker network layout and iptables translation | Shared by Bicep and the local simulation |
| `infra/azure/modules/alerts-infra.bicep` | Probe-failure and firewall-denial alerts | Not read; confirm pattern |
| `infra/azure/main.bicep` | New params (`egressFqdnMode`, `egressAllowedFqdns`, `egressAllowedPorts`, `threatIntelMode`, `egressNsgEnforce`); set `EGRESS_EXTRA_BLOCKED_CIDRS` on the egress app; `netControls` output; wire modules | Egress env block near `main.bicep:1071-1100`; module wiring near `main.bicep:411-440, 507-517` |
| `infra/azure/README.md` | Correct "(to any FQDN)" (`infra/azure/README.md:65`) and the "primary" wording; add the layers and the probe; rewrite the "Verifying it" section with the new job | |
| `docs/adr/0005-ssrf-egress-controls.md` | Amendment, see ADR impact | |
| `docs/platform-architecture.md` | State the condition on "no outbound internet route" (S11); not opened by me | |
| `docs/features/` | A short page or section on the network controls and the probe | Not opened; follow `docs/README.md` placement |
| `.justfiles/infra.just` | `net-verify`, `net-sim`, `egress-hosts` recipes next to the existing `build` | Existing module; recipes follow its header comment (deployment steps stay in the README) |

## Failure paths

- **A bad `EGRESS_EXTRA_BLOCKED_CIDRS` value:** egress refuses to boot. Under `activeRevisionsMode: 'Single'` the old revision keeps serving; the deploy shows an unhealthy new revision. Empty is valid.
- **NSG rule missing a required ACA flow:** the new revision does not start or health probes fail. Mitigation: `egressNsgEnforce` deny-list-only mode first; the probe runs before the closing deny; roll the NSG association back by parameter. **Hypothesis, unverified in Azure** that a bad NSG on a populated ACA subnet can leave the environment unhealthy; the operator tests it on a scratch copy first (N1).
- **NSG blocks DNS:** every target fails to resolve and egress returns blocked or errors for all calls. The probe's DNS positive control detects it. This is why rule 130 is placed above the deny of `168.63.129.16`.
- **Required allow rule too narrow:** a vendor on a non-standard port breaks. The port list is a parameter and the failure appears as a connect timeout to egress. Not silent: the app sees a 502 class error and the firewall/NSG logs show the drop.
- **Firewall allow-list missing a host:** the firewall drops it; egress sees a connect or TLS failure. Silent at the app (a generic upstream error). Mitigation: denial alert (3d), and the probe's drift check for approved origins.
- **Probe job unreachable or fails to start:** the alert is on missing recent success too, not only on failure, so a disabled schedule shows up.
- **Probe false negative:** timeout is the only accepted "blocked" result, so a reset cannot hide a path.
- **Rollback:** each NSG and firewall change is a parameter; reverting the parameter restores the earlier posture. The application-layer change rolls back with the image.

## Tests

All of these run locally; none needs Azure.

- `apps/egress/src/ssrf.test.ts`:
  - `it.each` boundary tests for every new IPv4 range: first and last address block, one address outside on each side allows. For `168.63.129.16/32` that means `168.63.129.15` and `168.63.129.17` are allowed.
  - Each new range through the three embedding forms: v4-mapped hex (`::ffff:a83f:8110`), NAT64 (`64:ff9b::a83f:8110`), compat (`::a83f:8110`), and the IPv4-translated form.
  - `3fff::/20` and `5f00::/16`, first, last, outside.
  - Extra-CIDR parameter: an address in an extra range is blocked, one just outside is allowed, an IPv6 extra range works, an empty list changes nothing.
  - `resolveAndValidate` with the mocked `lookup` returning `168.63.129.16` for a name, and a dual-record name where one address is the platform VIP: the whole host is refused (same shape as the existing dual-record test at `ssrf.test.ts:147`).
- `apps/egress/src/adversarial.test.ts`: an end-to-end `/proxy` case whose origin resolves to `168.63.129.16` returns 403 `blocked` and the connector never dials. Extend the existing "egress SSRF hardening" suite (`adversarial.test.ts:139`).
- `apps/egress/src/config.test.ts`: valid, empty, malformed CIDR (refuse), and `allowPrivate` in production (still refuses, and the extra list does not become a bypass).
- A completeness test against a snapshot of the IANA special-purpose registry, embedded in the test file with its retrieval date, asserting that every non-forwardable, non-global entry is either in the block list or in an explicit allowed-exceptions list. The snapshot must come from the registry itself, not from memory.
- `apps/egress/src/netprobe.test.ts`: the check table against a local listener set: a listener that accepts is `reachable`, a closed port (reset) is not counted as `blocked`, a dropped connect is `blocked` only on timeout, unresolved names are reported, and any mismatch gives a non-zero exit code.
- Bicep: `just infra build` for the new and changed modules and parameter files. This proves the templates compile. It does not prove Azure accepts them (**unverified in Azure**).
- NSG rule logic: `just infra net-sim` as described under "Local simulation", including the negative run with a broken rule table.
- Smoke runner: `node .claude/skills/run-helix/smoke.mjs` (`just dev smoke`) after the application-layer changes, to confirm a proxied fetch and an LLM call still work with the new block list and an empty and a non-empty `EGRESS_EXTRA_BLOCKED_CIDRS`.
- Gate: `./check-and-lint.sh` (or `just check`) in the dev container for every change.
- **Unverified in Azure:** `just infra net-verify` against a real install. It is the only test that proves the Hypothesis rows; an operator runs it and records the results in the ADR amendment.

## Telemetry

- No new seam in edge, portal or egress is added by layers 2-4. Layer 1 adds no span; the blocked outcome is already a 403 `blocked` in `proxy.ts` (`proxy.ts:697-699`). **Optional:** a bounded `ssrf.reason` class attribute (`platform`, `private`, `documentation`, `extra`) for alerting on platform-address attempts. If added: constants in `packages/shared/src/telemetry.ts`, the egress attribute allowlist in `apps/egress/src/spanAttributes.ts`, and `apps/egress/src/spanAttributes.test.ts` extended (the adversarial suite named in the repo rules). It must never carry the address or host.
- The probe job logs one structured line per check (`event: "netprobe"`) under the logging convention in `docs/design/logging.md` (not opened). No whole URLs, no secrets.
- Alerts: probe failure or no recent success; firewall application-rule denials from the egress subnet. Add them to the infra alert modules and list them in `docs/features/observability.md`.
- Suites to extend: `apps/egress/src/spanAttributes.test.ts` only if the optional attribute is added. `apps/edge/src/spanRedaction.test.ts` and `traceBoundary.test.ts` are unaffected.

## Rollout and migration

Nothing is rolled out to the live installs by this work. The person doing the work has no access to them or to their deployments repo. What this work delivers is the code, the templates, the local proof, and the notes below.

**New installs built from the fork:** layers 1, 2 and 4 from the first deploy; layer 3 if `deployFirewall`. Order: network and NSG, then environments, then apps, then the probe job, then `just infra net-verify`. Defaults: `egressNsgEnforce` = enforce and `egressFqdnMode` = `allowlist` (the latter only matters when the firewall is on). These are unverified in Azure until someone deploys them.

### Operator rollout notes

For an operator of an existing install (including the two live ones, firewall off). Do these in order:

1. **Test NSG attachment on a scratch copy first (N1).** In a scratch resource group with the same shape, deploy the new template with the NSG and run `just infra net-verify`. Resolve the Hypothesis rows: the ACA required rules, the DNS path, whether `168.63.129.16` answers, whether a populated Container Apps subnet accepts an NSG as an update, and the source address the ILB sees. Do not continue until the results are recorded.
2. **Ship the application layer with the next image.** No infrastructure change. The built-in block list carries the new ranges even if the template is not applied. Set `EGRESS_EXTRA_BLOCKED_CIDRS` (the template sets it from `vnetAddressPrefix`).
3. **Check live manifests for approved origins on ports other than 80 and 443.** They stop working when the closing deny is enforced.
4. **Apply the template with fixed private-endpoint addresses (N2).** This is a one-time endpoint update for the vaults; confirm the addresses the NSG rules name match.
5. **Apply the NSG with `egressNsgEnforce` in deny-list-only mode.** Check `/health`, a proxied fetch, an LLM call, a connection-secret read, and `just infra net-verify`.
6. **Move to enforce** once the probe is green on that install. Do the second install after the first.
7. **If a populated subnet cannot take an NSG as a plain update** (**Hypothesis**), the fallback is recreating the egress environment, a disruption the operator must schedule.
8. **Update the accepted-risk record** in the operator's deployments repo to point at the `netControls` output and the last probe result.

**Existing firewall installs:** `egressFqdnMode` stays `any` on upgrade; threat intel Deny on upgrade is low risk and can ship. Flipping to `allowlist` is an explicit step after the operator runs `just infra egress-hosts` and adds the printed hosts. Before turning the firewall on for an install that did not run it, add the apps-subnet platform hosts (Graph, ACME, ARM, Key Vault tag), or certificate issuance and the portal's directory calls fail (review, cross-design dependency 1).

**Compatibility breaks:** approved origins on ports other than 80 and 443 stop working once rule 300 and 4000 are enforced. Vendor IPs inside a newly blocked documentation range are not a real case.

## ADR impact

- **ADR-0005:** add an amendment (and fix S10). Say: (1) the application filter and a subnet NSG are the baseline control for every install; (2) the firewall FQDN allow-list is the stronger, optional tier, and the old text that calls the firewall the "primary" control describes the reference posture only; (3) the accepted-risk record names what the exception actually is: firewall off, NSG on, trusted single-tenant, with the probe as the evidence; mark the NSG rows that remain unverified in Azure until an operator records probe results; (4) list the new ranges and `EGRESS_EXTRA_BLOCKED_CIDRS`. Do not rewrite the 2026-09-22 record; append.
- **ADR-0028:** one line that the allow-list and the NSG enforce mode are per-install configuration, not platform constants. The containment design also amends this ADR; write one amendment (review, dependency 2).
- **ADR-0046:** the Foundry host suffix must appear in the allow-list when `allowlist` mode is on; a private-endpoint Foundry stays unsupported because the filter blocks private addresses.
- `docs/platform-architecture.md` line about "no outbound internet route": state the `deployFirewall` condition (S11).

## Open questions

The decisions (D3, N1 to N5, V1, V4) answered the questions the first draft carried. What remains open:

1. **Should existing firewall installs default to `allowlist` on a template update?** This design keeps them on `any` so an upgrade cannot break them; only the operator of such an install can judge whether to flip it.
2. **Should the portal approval screen tell the approver that a new origin needs an operator step on firewall installs?** It is a portal change outside this work. Without it the second step is invisible to the approver (see 3c).
3. **Is the optional `ssrf.reason` span attribute worth adding?** Not in the breakdown. Decide after the block list lands and there is a use for alerting on platform-address attempts.

## Work breakdown

Order: SSRF block-list fixes and their boundary tests, then the NSG Bicep, then the firewall allow-list tier, then the reachability probe and `just infra net-verify`. Every change is gated by `./check-and-lint.sh` (or `just check`) in the dev container. Nothing is deployed to Azure.

### EG-1 Block-list additions and boundary tests
- **Depends on:** none
- **Files:** `apps/egress/src/ssrf.ts`, `apps/egress/src/ssrf.test.ts`, `apps/egress/src/adversarial.test.ts`
- **Done when:** `168.63.129.16/32`, `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `192.88.99.0/24`, `3fff::/20` and `5f00::/16` are blocked; the IPv4-translated `::ffff:0:0:0/96` form extracts its embedded IPv4; the three embedding forms of `168.63.129.16` are blocked; first and last address of each new range block and the address just outside each side allows; a name resolving to `168.63.129.16` (alone or in a dual-record set) is refused; an end-to-end `/proxy` request to such an origin returns 403 `blocked` and never dials.
- **Evidence:** the `ssrf.test.ts` tables and the `adversarial.test.ts` case pass in `./check-and-lint.sh`; the smoke runner's proxied fetch and LLM call still pass. Whether `168.63.129.16` is reachable from a Container Apps replica stays unverified in Azure (the block is safe either way).

### EG-2 Deployment-supplied extra block list
- **Depends on:** EG-1
- **Files:** `apps/egress/src/ssrf.ts`, `apps/egress/src/config.ts`, `apps/egress/src/proxy.ts`, `apps/egress/src/exchangeTransport.ts`, `apps/egress/src/providerClient.ts`, `apps/egress/src/config.test.ts`, `apps/egress/src/ssrf.test.ts`
- **Done when:** `EGRESS_EXTRA_BLOCKED_CIDRS` (comma-separated v4 or v6 CIDRs, empty allowed) is parsed once at load; a malformed CIDR refuses to start; the list is an explicit parameter of `isBlockedAddress`, `resolveAndValidate`, `makeValidatingConnector` and `makePinnedDispatcher` (no module global) and every caller passes it, so a missing caller fails typecheck; an address in an extra range is blocked and one just outside allows; `allowPrivate` in production still refuses to boot and the extra list is not a bypass.
- **Evidence:** the config and SSRF tests above; typecheck in `./check-and-lint.sh`; the smoke runner passes with the variable empty and with it set to the dev VNet-like range. The setting is per install; empty is the relaxed behavior.

### EG-3 Special-purpose registry completeness test
- **Depends on:** EG-1, EG-2
- **Files:** `apps/egress/src/ssrf.test.ts` (or a new `ssrfRegistry.test.ts`), an embedded registry snapshot with its retrieval date
- **Done when:** every non-forwardable, non-global entry of the IANA IPv4 and IPv6 special-purpose registries is either blocked by the built-in list or named in an explicit allowed-exceptions list with a reason; any further entries the registry lists (AS112, AMT and others) are added to the block list or the exceptions.
- **Evidence:** the test fails when a range is removed from the list (check by deleting one locally) and passes otherwise. The snapshot comes from the registry, not memory.

### EG-4 Fixed private-endpoint addresses
- **Depends on:** none
- **Files:** `infra/azure/modules/private-endpoint.bicep`, `infra/azure/main.bicep`, `infra/azure/modules/network.bicep` if address layout needs it
- **Done when:** the module takes an optional `privateIpAddress` and `main.bicep` passes fixed addresses for `kv-connections` and `kv-delegated` (and the `kv-platform` and blob endpoints so the deny rules can name them); omitting the parameter keeps today's dynamic behavior.
- **Evidence:** `just infra build`. Azure accepting the property, and the one-time endpoint update on an existing install, stay unverified in Azure.

### EG-5 NSG module and subnet attachment
- **Depends on:** EG-2, EG-4
- **Files:** `infra/azure/modules/nsg.bicep` (new), `infra/azure/nsg-egress-rules.json` (new), `infra/azure/modules/network.bicep`, `infra/azure/main.bicep`, `infra/azure/main.bicepparam`
- **Done when:** an NSG for `snet-egress` carries the outbound rules in the table (allows 100-140, denies 200-240, internet allow 300, closing deny 4000) and the inbound rules, loaded from `nsg-egress-rules.json`; it is created before the VNet and referenced from the inline subnet definition; `egressNsgEnforce` has deny-list-only and enforce modes (4000 is active only in enforce); `egressAllowedPorts` is a parameter; `main.bicep` sets `EGRESS_EXTRA_BLOCKED_CIDRS` on the egress app from `vnetAddressPrefix` plus the platform-reserved range; `snet-pe` and `snet-apps` get no NSG (N5).
- **Evidence:** `just infra build` including the parameter files. Unverified in Azure: attachment to a populated Container Apps subnet, the platform flows in rows 100 and 140, the 100.64.0.0/10 deny in row 240, and the ILB source address. Rule logic is proven in EG-10.

### EG-6 Firewall platform lists and threat intelligence
- **Depends on:** EG-5
- **Files:** `infra/azure/modules/firewall.bicep`, `infra/azure/main.bicep`, `infra/azure/README.md`
- **Done when:** `threatIntelMode` is a parameter defaulting to `Deny`; `acaPlatformFqdns` is split into `appsPlatformFqdns` and `egressPlatformFqdns` so the egress subnet no longer inherits GHCR, Graph or ACME; the apps list gains Graph, ACME, ARM, the Key Vault tag and `login.microsoft.com`; `README.md:65` and the "primary" wording are corrected.
- **Evidence:** `just infra build`. Whether Basic supports threat-intel Deny, whether the egress subnet still needs MCR and GHCR through the route, and the runtime effect of every host list are unverified in Azure.

### EG-7 Firewall allow-list tier and drift tooling
- **Depends on:** EG-6
- **Files:** `infra/azure/modules/firewall.bicep`, `infra/azure/main.bicep`, `infra/azure/modules/alerts-infra.bicep`, `.justfiles/infra.just`, a small database-reading script or portal CLI subcommand
- **Done when:** `egressFqdnMode` (`any` or `allowlist`) and `egressAllowedFqdns` exist; in `allowlist` mode the `targetFqdns: ['*']` rule is replaced by a platform rule and a product rule (vendor hosts, provider hosts, approved origins); `any` keeps today's behavior and is the value for existing installs; a diagnostic setting sends firewall logs to the Log Analytics workspace and an alert fires on application-rule denials from the egress subnet; `just infra egress-hosts` prints approved fetch origins and provider hosts from the database and marks those missing from the deployed list; the list is not generated from approvals (N3).
- **Evidence:** `just infra build`; a test for the host-extraction logic of `egress-hosts` against a local database in the dev container. Firewall runtime behavior, SNI-only matching and rule collection limits stay unverified in Azure.

### EG-8 Probe entry point
- **Depends on:** EG-1, EG-5
- **Files:** `apps/egress/src/netprobe.ts` (new), `apps/egress/src/netprobe.test.ts` (new)
- **Done when:** the probe, using only `node:net` and `node:dns`, runs the check table from its environment inputs, classifies each as `blocked` (connect timeout only), `reachable` or `unresolved`, prints one JSON line per check with `event: "netprobe"`, expected and actual, and exits non-zero on any mismatch; no URL, secret or credential appears in the output.
- **Evidence:** `netprobe.test.ts` against local listeners (accept, reset, dropped connect, unresolved name, mismatch exit code); `./check-and-lint.sh`.

### EG-9 Probe job, posture output and alerts
- **Depends on:** EG-7, EG-8
- **Files:** `infra/azure/modules/netprobe-job.bicep` (new), `infra/azure/modules/alerts-infra.bicep`, `infra/azure/main.bicep`
- **Done when:** a scheduled and on-demand Container Apps Job `<prefix>-netprobe` runs in the egress environment from the egress image with a `command` override and a dedicated user-assigned identity with no role assignments; Bicep passes `PROBE_EXPECT_FIREWALL`, `PROBE_EXPECT_FQDN_ALLOWLIST`, `PROBE_EXPECT_NSG`, the apps environment address, the vault endpoint addresses, the Postgres name and a canary FQDN; `main.bicep` has a `netControls` output (firewall, FQDN mode, NSG mode, probe expectations); an alert fires on probe failure and on no recent success.
- **Evidence:** `just infra build`. The job running in Azure and the alert firing are unverified in Azure.

### EG-10 Local simulation and `just infra net-verify`
- **Depends on:** EG-5, EG-8, EG-9
- **Files:** `infra/netsim/` (Docker network layout, rule-table-to-iptables translation, expected columns), `.justfiles/infra.just`
- **Done when:** `just infra net-sim` builds the networks and target containers, applies `nsg-egress-rules.json` as iptables rules with `DROP` on the probe container, runs the probe, and passes for both the "NSG on" and "NSG off" columns; it fails when the rule table is deliberately broken (for example rule 130 removed, or the VNet deny placed before the Postgres allow); `just infra net-verify` starts the Azure job and prints its result, with a header comment in the recipe saying it is an operator step.
- **Evidence:** `just infra net-sim` run in the dev container, positive and negative. This proves rule ordering and logic, drop versus reset handling and the probe's failure behavior. It does not prove Azure NSG semantics, NSG attachment to an in-use Container Apps subnet, or the behavior of `168.63.129.16`; those stay unverified in Azure and are what `net-verify` run by an operator settles.

### EG-11 Documentation and ADR amendments
- **Depends on:** EG-10
- **Files:** `docs/adr/0005-ssrf-egress-controls.md`, `docs/adr/0028-*.md`, `docs/adr/0046-*.md`, `docs/platform-architecture.md`, `infra/azure/README.md` ("Verifying it" section), `docs/features/` network-controls page, `docs/features/observability.md`
- **Done when:** the ADR-0005 amendment, the ADR-0028 line, the ADR-0046 note and the S11 condition on "no outbound internet route" are written; the README and ADR stop restating the firewall state in prose and point at `netControls` and the last probe result; the operator rollout notes above are in the features page or README; rows marked unverified in Azure are listed as such.
- **Evidence:** docs review; `./check-and-lint.sh` for any docs lint it runs. Claims about Azure behavior carry the unverified label.
