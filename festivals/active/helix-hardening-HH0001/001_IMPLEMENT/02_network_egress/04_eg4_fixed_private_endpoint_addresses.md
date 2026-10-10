---
fest_type: task
fest_id: 04_eg4_fixed_private_endpoint_addresses.md
fest_name: eg4 fixed private endpoint addresses
fest_parent: 02_network_egress
fest_order: 4
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.024514-06:00
fest_updated: 2026-10-10T02:06:29.572181-06:00
fest_tracking: true
---


# Task: eg4 fixed private endpoint addresses

## Objective

Give the four private endpoints in `snet-pe` (the three Key Vaults and Blob) fixed, parameterized IP addresses, so a later NSG rule can name the two vaults egress needs instead of the whole endpoint subnet. Implements EG-4 from 03-egress-network-control.md.

## Requirements

- [ ] No prerequisite task. `05_eg5_nsg_module_and_subnet_attachment.md` and `09_eg9_probe_job_posture_output_and_alerts.md` use the addresses this task defines.
- [ ] `infra/azure/modules/private-endpoint.bicep` takes an optional `privateIpAddress`. When it is empty, the endpoint is declared exactly as today (dynamic address). When it is set, the endpoint carries a static IP configuration.
- [ ] `infra/azure/modules/keyvault.bicep` and `infra/azure/modules/storage.bicep` pass the address through. The design lists only `private-endpoint.bicep`, `main.bicep` and `network.bicep`, but these two modules are the only callers of the private-endpoint module (`keyvault.bicep:88, 100, 112`; `storage.bicep:60`), so they must change too.
- [ ] `main.bicep` computes one fixed address per endpoint from the private-endpoint subnet prefix: `kv-platform`, `kv-connections`, `kv-delegated` and Blob. The `kv-platform` and Blob addresses are fixed too so the NSG can deny them by name.
- [ ] An operator can override any address with one parameter, `privateEndpointAddresses`, because on an existing install Azure has already handed some of these addresses to the endpoints in their current order, and a template that names one already taken by a different endpoint fails the deployment.
- [ ] The six subnet and VNet address constants move from `network.bicep` into `main.bicep` and are passed down, because `05_eg5_nsg_module_and_subnet_attachment.md` needs them in a module created before the VNet (`nsg.bicep` cannot read `network.outputs`). The subnet layout itself does not change.
- [ ] Failure path. An address outside the endpoint subnet, a duplicate, or one of Azure's reserved first four and last addresses of a subnet is rejected at compile time with a `fail()` message naming the parameter, in the style of the existing guards in `main.bicep` (the `edgeTrustProxy` check at lines 487-499 is the model).
- [ ] Failure path. Applying fixed addresses to an existing install changes the address of an existing endpoint. That is a one-time endpoint update and a short window where the old address is gone; it goes in the operator rollout notes written by `11_eg11_docs_and_adr_amendments.md`. Record it in `results/` now.
- [ ] No application code changes. The vault URLs egress uses resolve by name through the private DNS zone, so the new addresses are invisible to it.
- [ ] Unverified in Azure: that the current API version accepts the static IP configuration for these four endpoints, and the values of `groupId` and `memberName` in it.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-4-fixed-private-endpoint-addresses`.

2. Read these first: `infra/azure/modules/private-endpoint.bicep` (the whole file, 59 lines), `infra/azure/modules/network.bicep` (lines 26-36 for the constants, 38-118 for the VNet, 143-151 for the outputs), and the four call sites: `infra/azure/modules/keyvault.bicep:88-122`, `infra/azure/modules/storage.bicep:60-70`.

3. `private-endpoint.bicep`. Add two parameters after `privateDnsZoneId` (line 23) and set `ipConfigurations` on the endpoint (the properties block is at lines 28-41):

```bicep
@description('Static private IP for the endpoint NIC, inside the endpoint subnet. Empty keeps today\'s behavior: Azure picks one. The NSG on snet-egress names the Key Vault endpoints by address, so the callers that matter pass one.')
param privateIpAddress string = ''

@description('memberName for the static IP configuration. Defaults to groupId; the Key Vault endpoint uses "default". Only read when privateIpAddress is set.')
param memberName string = groupId
```

   and, inside `properties`:

```bicep
    ipConfigurations: empty(privateIpAddress) ? null : [
      {
        name: 'ipconfig-${name}'
        properties: {
          groupId: groupId
          memberName: memberName
          privateIpAddress: privateIpAddress
        }
      }
    ]
```

   `null` omits the property, so an empty address is byte-identical to today's template. **Hypothesis:** the `memberName` for Blob is `blob` and for a Key Vault `default`; confirm both against the ARM reference for `Microsoft.Network/privateEndpoints` at API version 2024-05-01 (use Context7 or the Microsoft Learn page for assigning a static IP to a private endpoint) before choosing the defaults, and record what you found in `results/`. If you cannot confirm, ship them labeled unverified in the parameter description and in the rollout notes.

4. `keyvault.bicep`: add `param platformPrivateIp string = ''`, `param connectionsPrivateIp string = ''`, `param delegatedPrivateIp string = ''` next to the other params (after line 40), and pass `privateIpAddress: platformPrivateIp` (and `memberName: 'default'` if step 3 confirmed it) to the three module calls at lines 88-122. `storage.bicep`: add `param privateIpAddress string = ''` and pass it to the module call at line 60 with `memberName: 'blob'`. Empty defaults keep any other caller unchanged.

5. Lift the address constants. In `network.bicep`, replace the `var` constants at lines 32-36 with parameters of the same names and no defaults, and keep `vnetAddressPrefix` (line 27) as a parameter:

```bicep
@description('AzureFirewallSubnet prefix. Must be /26 or larger.')
param firewallSubnetPrefix string
@description('snet-apps prefix (/23 minimum for a workload-profile environment).')
param appsSubnetPrefix string
param egressSubnetPrefix string
param postgresSubnetPrefix string
param privateEndpointSubnetPrefix string
```

   The two outputs at lines 150-151 (`appsSubnetPrefix`, `egressSubnetPrefix`) and the firewall module's inputs keep working; add `output privateEndpointSubnetPrefix string = privateEndpointSubnetPrefix` and `output vnetAddressPrefix string = vnetAddressPrefix` beside them. Fix the comment at `network.bicep:109` while you are in the file: it says the subnet holds endpoints "for blob, both key vaults, and ACR", but there are three vaults and no registry (`main.bicep:1-14`).

   In `main.bicep`, add (near the other infrastructure parameters, after `appsDomain` at line 55) the VNet address space as a parameter and the subnet layout as variables, with the existing values:

```bicep
@description('Address space of the VNet. The subnet prefixes below are fixed inside the 10.0.0.0/16 default; changing this to a range that does not contain them fails the deployment.')
param vnetAddressPrefix string = '10.0.0.0/16'

var firewallSubnetPrefix = '10.0.0.0/26'
var appsSubnetPrefix = '10.0.2.0/23'
var egressSubnetPrefix = '10.0.4.0/23'
var postgresSubnetPrefix = '10.0.6.0/24'
var privateEndpointSubnetPrefix = '10.0.7.0/24'
```

   and pass all six to `module network` (`main.bicep:419-427`). Note for the record: the subnets were never derived from `vnetAddressPrefix`, so the parameter is only meaningful for a VNet that already contains `10.0.x.x`. Do not try to fix that here.

6. Compute and validate the addresses in `main.bicep`, next to the `network` module. Use Bicep's `cidrHost(prefix, index)`; index 0 is the subnet's first usable address, so index 3 is `.4` (Azure reserves `.0` to `.3` and the last address of every subnet). If the installed Bicep rejects `cidrHost`, build the string from `split(privateEndpointSubnetPrefix, '.')` instead and say so in `results/`:

```bicep
@description('Override the fixed addresses of the four private endpoints in snet-pe. Keys: kvPlatform, kvConnections, kvDelegated, blob. Omitted keys use the defaults (.4, .5, .6, .7 of the endpoint subnet). On an install that already has endpoints, read the addresses Azure assigned (az network private-endpoint list) and pick values no other endpoint holds, or the apply fails on the address clash.')
param privateEndpointAddresses object = {}

var peDefaults = {
  kvPlatform: cidrHost(privateEndpointSubnetPrefix, 3)
  kvConnections: cidrHost(privateEndpointSubnetPrefix, 4)
  kvDelegated: cidrHost(privateEndpointSubnetPrefix, 5)
  blob: cidrHost(privateEndpointSubnetPrefix, 6)
}
var peIps = union(peDefaults, privateEndpointAddresses)
```

   Add the guard: every value in `peIps` must differ from the others and sit inside `privateEndpointSubnetPrefix`. Bicep has no CIDR containment function and cannot order dotted addresses as strings, so build the subnet's first three octets with `join(take(split(privateEndpointSubnetPrefix, '.'), 3), '.')`, require `startsWith(ip, '${thatPrefix}.')` and `int(last(split(ip, '.')))` between 4 and 254 (Azure reserves `.0` to `.3` and `.255` in every subnet; this guard assumes the /24 the template uses), and check for duplicates with `length(union([a], [b], [c], [d])) == 4`. Express each failure with `fail('privateEndpointAddresses.kvConnections must be ...')` in a ternary on one `var`, referenced once so Bicep evaluates it (follow the pattern at `main.bicep:487-499`). Keep it simple; a wrong-but-valid address is the operator's to catch with the rollout notes.

7. Wire the addresses into the modules: `module storage` (`main.bicep:532-541`) gets `privateIpAddress: peIps.blob`; `module keyvault` (`main.bicep:543-553`) gets `platformPrivateIp: peIps.kvPlatform`, `connectionsPrivateIp: peIps.kvConnections`, `delegatedPrivateIp: peIps.kvDelegated`.

8. Parameter files. Add a commented example to `infra/azure/main.bicepparam` and `infra/azure/main.bootstrap.bicepparam` in the style of the commented `foundryAccountName` lines (`main.bicepparam` has them after `param deployFoundry = false`): `// param privateEndpointAddresses = { kvConnections: '10.0.7.20' }  // fixed IPs of the snet-pe endpoints; defaults are .4-.7`.

9. Docs. `apps/docs/src/deploy/configuration.md`: add a `privateEndpointAddresses` row to the parameter table that holds the networking parameters (the `deployFirewall` row is at line 85; add the row in the same table). Put a short paragraph in `infra/azure/README.md` in the "What it provisions" area (heading at line 13) saying the four endpoints have fixed addresses and why. The long-form rollout text belongs to `11_eg11_docs_and_adr_amendments.md`.

10. Run `just infra build` from the dev container. This is the only Azure check available here: it proves the templates and both parameter files compile. It does not prove Azure accepts the static IP configuration (NSG and endpoint behavior are unverified in Azure by decision V4).

11. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `just infra build` passes for `main.bicep`, `main.bicepparam` and `main.bootstrap.bicepparam`. Output saved under `results/`. A deliberate bad override (for example two endpoints with the same address) fails to compile with the `fail()` message; save that output too.
- [ ] With `privateEndpointAddresses` omitted and the module's `privateIpAddress` empty, `az bicep build` output for the endpoints has no `ipConfigurations` property. Confirm by building `private-endpoint.bicep` standalone with an empty address and checking the JSON.
- [ ] `./check-and-lint.sh` passes in the dev container (the Bicep files do not run in it, but the docs build and format steps cover the markdown you touched). Output saved under `results/`.
- [ ] `just dev smoke` is not required: no edge, portal or egress code changes.
- [ ] Committed with `fest commit -m "EG-4: fixed private-endpoint addresses for the vaults and Blob"`.
- [ ] Unverified in Azure: that API version 2024-05-01 accepts the static IP configuration for these endpoint types, the `memberName` values, and the one-time endpoint update on an existing install (including the address-clash case). Say so in the parameter description, in `results/`, and in the rollout notes.