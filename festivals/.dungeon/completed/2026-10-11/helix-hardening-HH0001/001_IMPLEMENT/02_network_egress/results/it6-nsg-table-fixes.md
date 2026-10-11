# IT-6: rule table, Bicep, probe and simulation fixes

Fixes from `review-02-network-egress.md` (including the coordinator addendum). Docs come in IT-7.

| Finding | Change |
| --- | --- |
| R-1 | `allow-apps-subnet` allows inbound 80, 443, 31080 and 31443. The two higher ports are the Container Apps environment's edge proxy behind the internal load balancer, per [Securing a Virtual Network in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration). `deny-vnet-in` is enforce-only, so `deny-list-only` changes nothing inbound and Azure's default `AllowVnetInBound` applies. The coordinator restored the note that the source address the NSG sees is unverified. |
| R-2 | `deny-wire-server` deleted; Microsoft says not to deny `168.63.129.16` on a Container Apps subnet. `allow-azure-dns` kept (Microsoft's documented outbound rule). The `nsg.bicep` header says `ssrf.ts` is the only control on that address. |
| R-4 | `allow-key-vault-endpoints` (pinned) now also allows `$kvPlatformIp`. `nsg.bicep` gains `kvPlatformIp`, wired from `peKvPlatformIp`. In pinned mode the probe's `kv-platform-443` expects `reachable`, a positive control for egress's own Key Vault references. `blob-pe-443` stays `blocked` with the NSG on. |
| S-1 | `deny-cgnat` (100.64.0.0/10) is enforce-only; `ssrf.ts` already blocks the range for proxied traffic. |
| S-2 | `firewall-diagnostics.bicep` takes `netprobeCanaryHost` and excludes it from the denial query (`| where Fqdn != "<canary>"`). The description says so. |
| S-6 | `login.microsoft.com` added to the egress firewall platform list (Microsoft: Key Vault references behind Azure Firewall need it). |
| G-7 (keys) | `privateEndpointAddresses` is a `@sealed()` user-defined type with four optional keys. A misspelled key fails parameter validation before deployment, which is stronger than the requested deploy-time `fail()`. |

Simulation: `networks.json` gains `$kvPlatformIp`. `translate.test.mjs` asserts the ILB ports, enforce-only `deny-vnet-in` and `deny-cgnat`, no `deny-wire-server`, and the three pinned vault addresses. The old `allow-azure-dns`-before-`deny-wire-server` invariant is gone. The test count went from 18 to 21.

## Evidence (coordinator)

- Negative test: a parameter file with `privateEndpointAddresses = { kvConnection: '10.0.7.20' }` fails `az bicep build-params` with `BCP089: The property "kvConnection" is not allowed ... Did you mean "kvConnections"?`. The temporary file was removed.
- `node --test infra/netsim/translate.test.mjs`: 21 of 21. `just infra build`: passes.
- The built denial query is single-line: `format('AZFWApplicationRule | where Action == "Deny" | where ipv4_is_in_range(SourceIp, "{0}") | where Fqdn != "{1}" | project ...')`.
- `./check-and-lint.sh`: 241 of 241 test files.
- `just infra net-sim` (host): all 7 scenarios PASS. In the `enforce` run:
  - `kv-platform-443` and `kv-connections-443` are `reachable`.
  - `blob-pe-443` is `blocked`.
  - Ports 25, 22 and 8443 are `blocked`.
  - Result: 15 checks, 0 failed.
- Output: `it6-gate.txt`.

## Still unverified in Azure

- Whether the NSG sees the apps subnet as the source of ILB-forwarded traffic.
- Whether ports 31080 and 31443 are the only backend ports in use. Microsoft documents them; this install has not been measured.
- Where Key Vault reference retrieval originates. That egress uses `snet-egress` is inferred from kv-platform being private-endpoint-only on working installs.

The simulation does not model inbound rules; the static tests on the inbound rows stand in for that.

## Executor

cursor-agent, `composer-2.5`, 74 tool calls. The coordinator restored the source-address caveat in the `allow-apps-subnet` note.
