---
fest_type: task
fest_id: 05_eg5_nsg_module_and_subnet_attachment.md
fest_name: eg5 nsg module and subnet attachment
fest_parent: 02_network_egress
fest_order: 5
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.024795-06:00
fest_updated: 2026-10-10T02:39:26.421071-06:00
fest_tracking: true
---



# Task: eg5 nsg module and subnet attachment

## Objective

Put a network security group on `snet-egress` on every install, built from one shared rule table that both Bicep and the local simulation read, and set `EGRESS_EXTRA_BLOCKED_CIDRS` on the egress app from the VNet prefix. Implements EG-5 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `02_eg2_deployment_supplied_extra_block_list.md` (the variable the template now sets) and `04_eg4_fixed_private_endpoint_addresses.md` (the fixed vault addresses, `peIps`, and the subnet prefixes lifted into `main.bicep`). `06_eg6_firewall_platform_lists_and_threat_intel.md`, `08_eg8_probe_entry_point.md` and `10_eg10_local_network_simulation_and_net_verify.md` depend on this task.
- [ ] New `infra/azure/nsg-egress-rules.json` holds every rule. New `infra/azure/modules/nsg.bicep` loads it with `loadJsonContent`, and nothing about the rules is duplicated in Bicep. `10_eg10_local_network_simulation_and_net_verify.md` reads the same file, so the two cannot drift.
- [ ] Outbound rules: allows at priorities 100-143 (own subnet, Postgres 5432, the `kv-connections` and `kv-delegated` endpoint addresses on 443, Azure DNS on 53, one rule per platform service tag), the deny list at 200-240 (`168.63.129.16`, `169.254.0.0/16`, the VNet prefix, the three RFC 1918 ranges, `100.64.0.0/10`), the internet allow at 300 on `egressAllowedPorts`, and the closing deny-all at 4000.
- [ ] Inbound rules: allow the apps subnet on the ILB ports, allow the Azure load balancer, allow the egress subnet itself, deny the rest of the VNet.
- [ ] `egressNsgEnforce` has three values: `deny-list-only`, `enforce` (the default) and `off`. Every rule is active in both of the first two modes except row 4000, which is active only in `enforce`. `off` creates no NSG and attaches none. The design names two modes; `off` is the "roll the NSG association back by parameter" its failure paths promise, so it is a third value of the same parameter, not a separate switch.
- [ ] `egressAllowedPorts` is a string-array parameter, default `['80', '443']`, used by rule 300.
- [ ] The NSG is created before the VNet and referenced from the inline `snet-egress` subnet definition next to `routeTable`, the same way the route tables are (`routing.bicep:1-8`). `snet-apps` and `snet-pe` get no NSG (decision N5; `snet-pe` has `privateEndpointNetworkPolicies: 'Disabled'`, so an NSG there would not filter endpoint traffic anyway).
- [ ] `main.bicep` sets `EGRESS_EXTRA_BLOCKED_CIDRS` on the egress app to `vnetAddressPrefix` plus `100.100.0.0/17` (the ACA platform-reserved range named in the comment at `main.bicep:432-437`). Note in the parameter text that `100.64.0.0/10` is already in the built-in list (`apps/egress/src/ssrf.ts:44`), so the second entry is documentation more than control, and `10.0.0.0/8` already covers the default VNet, so the first entry matters only for a VNet outside RFC 1918.
- [ ] Failure path. Rule order: the DNS allow (130) is numbered below the wire-server deny (200), and the VNet deny (220) is numbered above the Postgres (110) and vault (120) allows. A wrong order makes every target fail to resolve, or cuts Postgres. `10_eg10_local_network_simulation_and_net_verify.md` proves the order; keep priorities unique within a direction.
- [ ] Failure path. A missing required ACA platform flow can leave a revision unable to start or health probes failing. Mitigation lives in the parameter: start at `deny-list-only`, run the probe, then move to `enforce`; roll back with `off`.
- [ ] Failure path. A wrongly tight inbound rule makes the edge unable to reach egress (`EDGE_EGRESS_URL` returns an Envoy 404 or a timeout). The probe cannot test this direction, because it runs inside the egress environment; the existing edge-to-egress check in `infra/azure/README.md` ("Verifying the isolation (post-deploy)", lines 1322-1324) is the post-apply test and goes in the rollout notes.
- [ ] Failure path. Approved origins on ports other than 80 and 443 stop working once rules 300 and 4000 are active. Say so in the parameter text and in the docs.
- [ ] Everything about the NSG that only Azure can show is labeled **unverified in Azure**: attachment to a populated Container Apps subnet, the platform flows in rows 100 and 140-143, the DNS path through `168.63.129.16`, the `100.64.0.0/10` deny (row 240), the ILB source address, and service-tag membership.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-5-nsg-module`.

2. Read before editing: `infra/azure/modules/routing.bicep` (the "created empty, before the VNet" pattern, lines 1-37), `infra/azure/modules/network.bicep` (the inline subnet for `snet-egress` is lines 72-91, the `routeTable` reference on lines 79-81), the task `04_eg4_fixed_private_endpoint_addresses.md` output in `main.bicep` (`peIps`, the lifted subnet constants), and the egress app block in `main.bicep` (the `module egressApp` starts at line 1039; its env list starts at line 1076, and `EGRESS_MANAGED_IDENTITY_CONNECTIONS` is on line 1103).

3. Create `infra/azure/nsg-egress-rules.json`. One object with a `rules` array. Each rule has `name`, `priority`, `direction` (`Outbound` or `Inbound`), `access` (`Allow` or `Deny`), `protocol` (`Tcp`, `Udp` or `*`), `sourcePrefixes`, `destinationPrefixes`, `destinationPorts`, `modes` (which `egressNsgEnforce` values include the rule), `status` (`known` or `hypothesis`) and `note`. Prefixes are literal CIDRs, Azure service tags (kept as Azure spells them), or `$`-names that the consumers resolve: `$vnet`, `$egressSubnet`, `$appsSubnet`, `$postgresSubnet`, `$kvConnectionsIp`, `$kvDelegatedIp`; the single port token `$allowedPorts` expands to the `egressAllowedPorts` list. Write it like this (the whole file):

```json
{
  "rules": [
    { "name": "allow-own-subnet", "priority": 100, "direction": "Outbound", "access": "Allow", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["$egressSubnet"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis",
      "note": "ACA replicas, the internal load balancer and sidecars talk inside the subnet" },
    { "name": "allow-postgres", "priority": 110, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["$postgresSubnet"], "destinationPorts": ["5432"],
      "modes": ["deny-list-only", "enforce"], "status": "known", "note": "EGRESS_DATABASE_URL" },
    { "name": "allow-key-vault-endpoints", "priority": 120, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["$kvConnectionsIp", "$kvDelegatedIp"], "destinationPorts": ["443"],
      "modes": ["deny-list-only", "enforce"], "status": "known",
      "note": "AZURE_KEY_VAULT_URL and AZURE_DELEGATED_KEY_VAULT_URL; fixed endpoint addresses" },
    { "name": "allow-azure-dns", "priority": 130, "direction": "Outbound", "access": "Allow", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["168.63.129.16"], "destinationPorts": ["53"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis",
      "note": "egress resolves every target itself; must sit above deny-wire-server" },
    { "name": "allow-tag-mcr", "priority": 140, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["MicrosoftContainerRegistry"], "destinationPorts": ["443"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "ACA platform; fix against current docs" },
    { "name": "allow-tag-front-door", "priority": 141, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["AzureFrontDoor.FirstParty"], "destinationPorts": ["443"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "ACA platform; fix against current docs" },
    { "name": "allow-tag-entra", "priority": 142, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["AzureActiveDirectory"], "destinationPorts": ["443"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "managed identity tokens" },
    { "name": "allow-tag-monitor", "priority": 143, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["AzureMonitor"], "destinationPorts": ["443"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "ACA platform and telemetry" },
    { "name": "deny-wire-server", "priority": 200, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["168.63.129.16"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis",
      "note": "wire server and health-probe address; safe whether or not it answers from a replica" },
    { "name": "deny-link-local", "priority": 210, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["169.254.0.0/16"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "known", "note": "IMDS and link-local" },
    { "name": "deny-vnet", "priority": 220, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["$vnet"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "known",
      "note": "the core rule: apps subnet, kv-platform and Blob endpoints, the firewall subnet" },
    { "name": "deny-private-ranges", "priority": 230, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "known", "note": "peered or on-premises ranges" },
    { "name": "deny-cgnat", "priority": 240, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["100.64.0.0/10"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis",
      "note": "ACA draws ingress pod addresses from here; may break platform traffic. If it does, exclude 100.100.0.0/17" },
    { "name": "allow-internet-web", "priority": 300, "direction": "Outbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["Internet"], "destinationPorts": ["$allowedPorts"],
      "modes": ["deny-list-only", "enforce"], "status": "known", "note": "vendors, providers, approved origins" },
    { "name": "deny-all-outbound", "priority": 4000, "direction": "Outbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["*"], "destinationPrefixes": ["*"], "destinationPorts": ["*"],
      "modes": ["enforce"], "status": "known",
      "note": "without it the default AllowInternetOutBound lets egress dial any port on the internet" },
    { "name": "allow-apps-subnet", "priority": 100, "direction": "Inbound", "access": "Allow", "protocol": "Tcp",
      "sourcePrefixes": ["$appsSubnet"], "destinationPrefixes": ["*"], "destinationPorts": ["80", "443"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis",
      "note": "edge and portal call egress through the internal load balancer; the source address the NSG sees is unverified" },
    { "name": "allow-load-balancer", "priority": 110, "direction": "Inbound", "access": "Allow", "protocol": "*",
      "sourcePrefixes": ["AzureLoadBalancer"], "destinationPrefixes": ["*"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "platform health probes" },
    { "name": "allow-own-subnet-in", "priority": 120, "direction": "Inbound", "access": "Allow", "protocol": "*",
      "sourcePrefixes": ["$egressSubnet"], "destinationPrefixes": ["*"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "hypothesis", "note": "replica to replica" },
    { "name": "deny-vnet-in", "priority": 200, "direction": "Inbound", "access": "Deny", "protocol": "*",
      "sourcePrefixes": ["$vnet"], "destinationPrefixes": ["*"], "destinationPorts": ["*"],
      "modes": ["deny-list-only", "enforce"], "status": "known", "note": "the rest of the VNet may not initiate to egress" }
  ]
}
```

   Priorities must be unique within a direction (Azure rejects a duplicate). Each service-tag allow is its own rule because Azure accepts only one service tag per rule.

4. Create `infra/azure/modules/nsg.bicep`. Parameters: `location`, `namePrefix`, `mode` (allowed `deny-list-only`, `enforce`), the CIDR and address inputs that resolve the `$`-names, and `allowedPorts`. Build the rules from the file:

```bicep
@description('Azure region.')
param location string
@description('Resource name prefix.')
param namePrefix string
@allowed(['deny-list-only', 'enforce'])
@description('deny-list-only activates every rule except the closing deny-all (row 4000); enforce activates all of them.')
param mode string
param vnetAddressPrefix string
param egressSubnetPrefix string
param appsSubnetPrefix string
param postgresSubnetPrefix string
param kvConnectionsIp string
param kvDelegatedIp string
@description('TCP destination ports the internet allow (row 300) opens, e.g. ["80", "443"].')
param allowedPorts array

var refs = {
  '$vnet': vnetAddressPrefix
  '$egressSubnet': egressSubnetPrefix
  '$appsSubnet': appsSubnetPrefix
  '$postgresSubnet': postgresSubnetPrefix
  '$kvConnectionsIp': kvConnectionsIp
  '$kvDelegatedIp': kvDelegatedIp
}
var active = filter(loadJsonContent('../nsg-egress-rules.json').rules, r => contains(r.modes, mode))
var resolved = [for r in active: {
  name: r.name
  priority: r.priority
  direction: r.direction
  access: r.access
  protocol: r.protocol
  src: map(r.sourcePrefixes, p => contains(refs, p) ? refs[p] : p)
  dst: map(r.destinationPrefixes, p => contains(refs, p) ? refs[p] : p)
  ports: flatten(map(r.destinationPorts, p => p == '$allowedPorts' ? allowedPorts : [p]))
}]

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-nsg-egress'
  location: location
  properties: {
    securityRules: [for r in resolved: {
      name: r.name
      properties: {
        priority: r.priority
        direction: r.direction
        access: r.access
        protocol: r.protocol
        sourcePortRange: '*'
        sourceAddressPrefix: length(r.src) == 1 ? r.src[0] : null
        sourceAddressPrefixes: length(r.src) > 1 ? r.src : null
        destinationAddressPrefix: length(r.dst) == 1 ? r.dst[0] : null
        destinationAddressPrefixes: length(r.dst) > 1 ? r.dst : null
        destinationPortRange: length(r.ports) == 1 ? r.ports[0] : null
        destinationPortRanges: length(r.ports) > 1 ? r.ports : null
      }
    }]
  }
}

output nsgId string = nsg.id
```

   If the compiler rejects a lambda or the `$` keys, adjust the syntax but keep the shape: one loaded file, a filter by mode, `null` to omit the singular or plural property. Add a header comment in the style of `routing.bicep`: what the NSG is for, why it is created before the VNet, that it covers `snet-egress` only and why (the shared-subnet limit: `snet-apps` holds the edge, portal, dev-gateway, certbot and migrate job together, so an NSG there cannot separate them; decision N5 defers it), and the honest limit that the NSG cannot protect Postgres or the two vaults egress legitimately talks to (only the application filter and the absence of credentials on a bare request do).

5. `network.bicep`: add `@description('Resource id of the NSG for snet-egress, or empty for none.') param egressNsgId string = ''` and, in the `snet-egress` properties (lines 77-90), add beside `routeTable`: `networkSecurityGroup: empty(egressNsgId) ? null : { id: egressNsgId }`. Update the header comment (lines 10-12), which says Azure rejects late route-table association on a populated ACA subnet: add that the same restriction may apply to the NSG and is unverified in Azure. Leave `snet-apps`, `snet-postgres` and `snet-pe` alone.

6. `main.bicep`:
   - Parameters near `deployFirewall` (line 372): `egressNsgEnforce` (`@allowed(['off', 'deny-list-only', 'enforce'])`, default `'enforce'`) and `egressAllowedPorts` (`array`, default `['80', '443']`), each with a long `@description` in the style of its neighbors that states the strict default, how to relax it, the rollout order (start `deny-list-only`, probe, then `enforce`), and the non-standard-port break.
   - Module, placed right after `module routing` (line 411) and before `module network` (line 419):

```bicep
module egressNsg 'modules/nsg.bicep' = if (egressNsgEnforce != 'off') {
  name: 'nsg-egress'
  params: {
    location: location
    namePrefix: namePrefix
    mode: egressNsgEnforce == 'enforce' ? 'enforce' : 'deny-list-only'
    vnetAddressPrefix: vnetAddressPrefix
    egressSubnetPrefix: egressSubnetPrefix
    appsSubnetPrefix: appsSubnetPrefix
    postgresSubnetPrefix: postgresSubnetPrefix
    kvConnectionsIp: peIps.kvConnections
    kvDelegatedIp: peIps.kvDelegated
    allowedPorts: egressAllowedPorts
  }
}
```

   - In `module network` (lines 419-427) add `egressNsgId: egressNsg.?outputs.nsgId ?? ''`.
   - In the egress app env list (line 1076 onward), after the `EGRESS_MANAGED_IDENTITY_CONNECTIONS` entry (line 1103), add:

```bicep
      // SSRF filter ranges beyond the built-in list (apps/egress/src/ssrf.ts): the VNet, so an
      // install on a non-RFC 1918 range is covered, and the ACA platform-reserved range.
      { name: 'EGRESS_EXTRA_BLOCKED_CIDRS', value: '${vnetAddressPrefix},100.100.0.0/17' }
```

   - Do not add a `netControls` output here; `09_eg9_probe_job_posture_output_and_alerts.md` owns it.

7. Parameter files: add commented lines for `egressNsgEnforce` and `egressAllowedPorts` to `infra/azure/main.bicepparam` and `infra/azure/main.bootstrap.bicepparam` beside `deployFirewall` (lines 42-48 in the first, 56-61 in the second), in their comment style: what the value does and that `deny-list-only` is the safe first step on an existing install.

8. Docs. `apps/docs/src/deploy/configuration.md`: rows for `egressNsgEnforce` and `egressAllowedPorts` in the networking table (the `deployFirewall` row is line 85), and finish the `EGRESS_EXTRA_BLOCKED_CIDRS` row that `02_eg2_deployment_supplied_extra_block_list.md` left half-written ("set from `vnetAddressPrefix` plus `100.100.0.0/17`"). `infra/azure/README.md`: add `nsg.bicep` and the rule file to the Layout block (lines 496-515) and one short paragraph under "What it provisions" saying every install gets an NSG on `snet-egress` and that the firewall is the optional stronger tier. The corrected firewall wording and the long rollout text are `06_...` and `11_...`.

9. Run `just infra build` from the dev container. It compiles `main.bicep`, both `.bicepparam` files and the new module, and is the only Azure check available. Also compile `nsg.bicep` once per mode through a scratch `az bicep build --file infra/azure/modules/nsg.bicep` and confirm in the JSON that `deny-all-outbound` appears only in `enforce` mode. Save the output in `results/`.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `just infra build` passes for the new module, `main.bicep` and both parameter files, and the per-mode build shows row 4000 only in `enforce`. Output saved under `results/`.
- [ ] The rule file passes a quick structural check you run once with `node -e`: unique `(direction, priority)` pairs, every `$`-name is one the Bicep resolves, every rule has `modes`.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` is not required: no edge, portal or egress code changes in this task (the variable it sets was added and smoke-tested in `02_eg2_deployment_supplied_extra_block_list.md`).
- [ ] Committed with `fest commit -m "EG-5: NSG on snet-egress from a shared rule table"`.
- [ ] Unverified in Azure, and stated so in the module header, the parameter text and `results/`: whether a populated Container Apps subnet accepts an NSG as an update (the route-table version of this limit is documented at `network.bicep:10-12`), which flows the platform needs (rows 100 and 140-143), the DNS path through `168.63.129.16`, whether row 240 breaks ingress pod addressing, the source address the NSG sees for edge-to-egress traffic, and service-tag membership. NSG and firewall behavior cannot be checked here; `just infra build` proves the templates compile and nothing more (decision V4). The rule logic is proven locally by `10_eg10_local_network_simulation_and_net_verify.md`.