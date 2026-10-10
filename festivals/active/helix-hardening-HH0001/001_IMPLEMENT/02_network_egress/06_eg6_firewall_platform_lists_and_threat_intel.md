---
fest_type: task
fest_id: 06_eg6_firewall_platform_lists_and_threat_intel.md
fest_name: eg6 firewall platform lists and threat intel
fest_parent: 02_network_egress
fest_order: 6
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.025112-06:00
fest_updated: 2026-10-10T02:39:51.52614-06:00
fest_tracking: true
---


# Task: eg6 firewall platform lists and threat intel

## Objective

On installs that run the Azure Firewall, make threat intelligence a parameter that defaults to `Deny`, split the shared platform host list into one list per subnet, and add the hosts the apps subnet needs today but is missing (Microsoft Graph, the ACME server, Azure Resource Manager, the Key Vault service tag, `login.microsoft.com`). Implements EG-6 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `05_eg5_nsg_module_and_subnet_attachment.md` (same `main.bicep` regions, and the parameter files). `07_eg7_firewall_allow_list_tier_and_drift_tooling.md` builds on the split lists, and `04_domain_split` (CT-9, in another sequence) needs the apps-subnet additions on any install that runs the firewall.
- [ ] `infra/azure/modules/firewall.bicep` takes `threatIntelMode` (allowed `Alert`, `Deny`, `Off`), default `Deny`. `main.bicep` exposes it as a parameter of the same name and passes it through.
- [ ] The single `acaPlatformFqdns` array (`firewall.bicep:37-64`) becomes `appsPlatformFqdns` and `egressPlatformFqdns`, and the platform rule collection (`firewall.bicep:116-137`) becomes two rules, one per source subnet.
- [ ] The apps list gains: `graph.microsoft.com` (the portal's directory client, `packages/directory/src/entra.ts:29-31`), the ACME server host derived from the `acmeServer` parameter (certbot, `apps/certbot/issue-and-bind.sh:27`), `management.azure.com` (certbot's `az` calls, `issue-and-bind.sh:40-42`), and `login.microsoft.com`. The Key Vault reference path needs the `AzureKeyVault` service tag; that is a network rule, in a separate collection.
- [ ] The egress list does **not** inherit the new apps-only hosts (Graph, ACME, ARM). It keeps the hosts egress needs today: the MCR hosts, GHCR (egress's own image is `ghcr.io/azx-pbc-oss/helix-egress`, `main.bicep` `image:` line of `module egressApp`), the telemetry hosts, and the Entra hosts.
- [ ] Failure path: the design disagrees with itself here and the task resolves it conservatively. Its "Done when" says the egress subnet should no longer inherit GHCR, but its own hypothesis in the layer 3b text says image pulls run through the subnet route and so need MCR and GHCR. Keep GHCR and the blob wildcard on the egress list in this task, because removing a host an image pull needs breaks a revision start silently (a dropped pull looks like a stuck deploy). Record the disagreement in `results/`. `just infra net-verify` after a revision restart is what settles it, and that is **unverified in Azure**.
- [ ] Failure path: a host missing from the apps list drops silently at the application layer (`snet-apps` is deny-by-default; the comment at `firewall.bicep:50-56` describes the same trap for telemetry). The task lists every host with the code that needs it, in comments, so a reviewer can check each.
- [ ] `threatIntelMode: 'Deny'` can drop a vendor IP on a false positive. Say so in the parameter text and point at the firewall logs (`07_eg7_firewall_allow_list_tier_and_drift_tooling.md` adds them). Whether Basic tier supports `Deny` is **unverified in Azure** (the module sets `tier: 'Standard'` at `firewall.bicep:82`; `main.bicep` has no tier parameter).
- [ ] The "primary control" wording in the infra files stops claiming the firewall is the only primary control: the application filter plus the NSG is the baseline for every install, and the firewall FQDN filter is the stronger optional tier. Files for this task: `main.bicep:371`, `main.bicepparam:42`, `main.bootstrap.bicepparam:56`, `infra/azure/README.md:66-71` and `:82`. Do **not** change README line 65 ("to any FQDN"): it stays true until `07_...` adds the allow-list mode, and that task rewrites it. The docs outside `infra/` (`apps/docs/src/deploy/getting-started.md:56`, `configuration.md:85`, ADR-0005) are `11_eg11_docs_and_adr_amendments.md`.
- [ ] Defaults keep an existing firewall install working: with `deployFirewall = false` (the live installs) nothing here deploys. With the firewall on, the egress subnet's internet rule is untouched in this task (`targetFqdns: ['*']`), so no existing flow is narrowed.
- [ ] Everything about firewall runtime behavior is **unverified in Azure**: the effect of every host list, whether service tags are accepted in a network rule's destination, and Basic-tier threat-intel support.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-6-firewall-platform-lists`.

2. Trace the outbound hosts before editing, because the design admits it did not. For each of these, open the code and write the host into `results/`:
   - Portal: `packages/directory/src/entra.ts` (Graph base and scope at lines 29 and 31; the token comes from the managed identity through `DefaultAzureCredential`, which talks to Entra); `apps/portal/src/auth/` (JWKS and OIDC discovery against the Entra issuer, `login.microsoftonline.com`). Grep for other `fetch(` targets: `grep -rn "fetch(" apps/portal/src packages/directory/src | grep -v test`.
   - Certbot: `apps/certbot/issue-and-bind.sh` (read the whole file): ACME server (line 27, from `HELIX_ACME_SERVER`), `az login --identity` (lines 40-41), `az containerapp ... certificate upload`, `hostname add/bind`, and `az network dns record-set txt add-record` (line 160) all go to Azure Resource Manager; `certbot-dns-azure` (lines 102-115) also calls ARM. The Dockerfile's `az extension add` (build time, not runtime) is not a runtime host.
   - Edge: OIDC discovery against the Entra issuer.
   If the trace finds a host not in the list below, add it and say why in `results/`.

3. `firewall.bicep`. Replace the parameter at lines 37-64 with two arrays. Keep every existing entry and comment; the split is:

```bicep
@description('FQDNs the apps-subnet workloads need: ACA platform plumbing (MCR, GHCR, monitoring, App Insights), Entra for tokens and OIDC, Microsoft Graph (portal directory client), Azure Resource Manager (certbot) and the ACME directory host. Review against current ACA networking docs before deploying.')
param appsPlatformFqdns array = [ /* the old acaPlatformFqdns entries, plus: */
  'graph.microsoft.com' // packages/directory/src/entra.ts: group and user lookups
  #disable-next-line no-hardcoded-env-urls
  'management.azure.com' // certbot: az login, certificate upload, hostname bind, DNS TXT writes
  #disable-next-line no-hardcoded-env-urls
  'login.microsoft.com' // managed-identity token issuance for Key Vault references
]

@description('ACME directory host (from the acmeServer parameter). Added to the apps list: certbot runs in the apps environment.')
param acmeServerHost string

@description('FQDNs the egress subnet needs for the platform itself: MCR, GHCR (egress image pulls), monitoring and App Insights, Entra. NOT Graph, ACME or Resource Manager, which only the apps subnet uses.')
param egressPlatformFqdns array = [ /* the old entries, minus nothing in this task */ ]
```

   In the `aca-platform` collection (lines 116-137) make two application rules, `aca-required-fqdns-apps` (source `appsSubnetPrefix`, targets `concat(appsPlatformFqdns, [acmeServerHost])`) and `aca-required-fqdns-egress` (source `egressSubnetPrefix`, targets `egressPlatformFqdns`), same protocols as today (`Https` 443, `Http` 80). Add a third collection for the Key Vault tag, after `aca-platform` (priority 300 inside the group):

```bicep
      {
        // Key Vault reference resolution is not an FQDN rule: it needs the AzureKeyVault service tag.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'aca-platform-network'
        priority: 300
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'key-vault-reference-resolution'
            ipProtocols: ['TCP']
            sourceAddresses: [appsSubnetPrefix, egressSubnetPrefix]
            destinationAddresses: ['AzureKeyVault']
            destinationPorts: ['443']
          }
        ]
      }
```

   **Hypothesis, unverified in Azure:** that a service tag is accepted in `destinationAddresses` of a firewall-policy network rule at API version 2024-05-01. If `just infra build` or the Bicep type definition shows otherwise, fix the property and say so in `results/`.

   Replace `threatIntelMode: 'Alert'` (line 84) with the parameter: `@allowed(['Alert', 'Deny', 'Off']) param threatIntelMode string = 'Deny'`, described as above.

   Keep the egress subnet's internet rule exactly as it is (lines 94-115) in this task.

4. `main.bicep` and the parameter files: add `@allowed(['Alert', 'Deny', 'Off']) param threatIntelMode string = 'Deny'` next to `deployFirewall` (line 372) with a description covering the false-positive risk and the unverified Basic-tier question. Add a commented example (`// param threatIntelMode = 'Alert'  // 'Deny' drops known-bad destinations; use 'Alert' to log only`) beside `deployFirewall` in `infra/azure/main.bicepparam` and `infra/azure/main.bootstrap.bicepparam`. In `module firewall` (lines 507-517) pass `threatIntelMode: threatIntelMode` and `acmeServerHost: acmeServerHost`, defining `acmeServerHost` as a variable next to the module:

```bicep
// The ACME directory's host, for the apps-subnet firewall list. acmeServer is a full URL.
var acmeServerHost = split(replace(replace(acmeServer, 'https://', ''), 'http://', ''), '/')[0]
```

5. Wording. Reword the "primary" claims in `main.bicep:371`, `main.bicepparam:42` and `main.bootstrap.bicepparam:56` to say the firewall is the stronger optional tier (an FQDN-filtering control), and that the baseline for every install is the application filter in `apps/egress/src/ssrf.ts` plus the NSG on `snet-egress` (`egressNsgEnforce`). Keep each file's existing structure and the cost sentence. In `infra/azure/README.md` rewrite lines 66-71 ("allow-list is the **primary** SSRF/egress control; the egress app's own `ssrf.ts` ... _defense-in-depth_") and line 82 ("the primary egress control is gone") the same way; keep ADR links. Update the Key Vault paragraph at lines 269-273 ("Neither install runs the firewall today; add these before it comes back"): the template now carries the `AzureKeyVault` tag and `login.microsoft.com` for firewall installs, labeled unverified in Azure. Add Graph, ACME and Resource Manager to that paragraph, naming the code that needs each.

6. Cross-sequence note, in `results/` and in the commit body: `04_domain_split` (CT-9) adds a second certbot instance for the apps domain. It reuses `management.azure.com`, the ACME host and Entra, all added here, so on an install that runs the firewall this task must be applied first. If CT-9 introduces a different ACME server per domain, `acmeServerHost` must become a list.

7. Run `just infra build` from the dev container (the only Azure check available). Also compile `firewall.bicep` standalone and read the JSON to confirm the egress rule's targets do not contain `graph.microsoft.com`, `management.azure.com` or the ACME host, and the apps rule's targets do. Save both in `results/`.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `just infra build` passes; it is the only Azure check available here, and firewall behavior stays unverified in Azure (decision V4). The standalone compile shows the split: Graph, Resource Manager and the ACME host only in the apps rule. Output saved under `results/`.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` is not required: no edge, portal or egress code changes.
- [ ] `grep -rn "PRIMARY\|primary" infra/azure/main.bicep infra/azure/main.bicepparam infra/azure/main.bootstrap.bicepparam infra/azure/README.md` shows no claim that the firewall is the sole primary control.
- [ ] The design disagreement about GHCR is recorded in `results/`.
- [ ] Committed with `fest commit -m "EG-6: per-subnet firewall platform lists and threat intelligence Deny"`.
- [ ] Unverified in Azure, stated in the parameter text and `results/`: whether Basic tier supports threat-intel `Deny`; whether the egress subnet still needs MCR and GHCR through the route (and so keeps them); the runtime effect of every host list; whether a service tag is accepted in a network rule's destination; whether the apps subnet needs any host this trace did not find. Nothing here has run on a firewall install.