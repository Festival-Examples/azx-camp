# IT-7: rollout notes and docs

Doc and parameter-file fixes from `review-02-network-egress.md`, written against the IT-6 rule table.

| Finding | Change |
| --- | --- |
| R-3 | New `## Upgrading to the network controls` in `apps/docs/src/deploy/updates.md`, after the spend-control section. Step 0: hold `egressNsgEnforce = 'off'` before any full apply until the scratch copy and `net-verify` pass, and decide `deployNetprobe`. The section lists what any full apply changes even with the NSG off: the probe job and alerts, threat-intel `Deny`, `login.microsoft.com`, the canary exclusion and `EGRESS_EXTRA_BLOCKED_CIDRS`. The coordinator rewrote that paragraph, because the agent's version implied these arrive only when the NSG is turned on. The spend section's step 6 points at step 0. Step 2 now rolls the image with a scoped `az containerapp update`. Both parameter files carry a commented hold-off line for `egressNsgEnforce`. |
| R-1 docs | Inbound-port row in the ADR-0005 probe table and the feature page's unverified list. The README check is triggered by any change to `egressNsgEnforce` or the rule table. The feature page and README say the probe is outbound-only. |
| G-1 | `just infra net-verify` prints the README's edge-to-egress `/health` command and an outbound-only reminder after the probe lines. Executed from a dry run, the printed command matches the README byte for byte. |
| R-2, R-4 docs | ADR-0005, the feature page and the README say `ssrf.ts` is the only control on `168.63.129.16` (citing Microsoft's Container Apps page). The host-node sentence is split: WireServer is exempt unconditionally, and `AzurePlatformDNS` applies to DNS only. kv-platform joins the honest limit, with the vault-wide grant explained. The probe expectation tables show `kv-platform-443` as reachable and Blob as blocked. `TODO.md` defers narrowing egress's kv-platform grant. |
| S-1 docs | Lists of what `deny-list-only` contains drop `deny-cgnat` and `deny-vnet-in`, both enforce-only. |
| S-3 | "Safe on upgrade" claims are rephrased as intent with the unverified label (`configuration.md`, the feature page, ADR-0028). The `egressNsgEnforce` description has no duplicate, and says `off` detaches the NSG while the resource can remain. The `nsg.bicep` header says late association is documented for route tables and unverified for NSGs. |
| S-4 | `egressFqdnMode = 'allowlist'` is commented out in both parameter files, with the new-installs note. |
| S-5 | N1-N5 and "network egress plan" removed from `nsg.bicep`, `netprobe-job.bicep`, the feature page and `TODO.md`. A whole-word grep of `infra`, `.justfiles`, `apps/docs/src`, `TODO.md`, the feature page and ADR-0005 finds none. |
| G-6 | The `EGRESS_EXTRA_BLOCKED_CIDRS` row says the template's subnets are fixed inside 10.0.0.0/16. |
| G-7 | The garbled parenthetical in `fetch-proxy.md` is fixed. |
| Carried | `TODO.md` defers the `AzurePlatformIMDS` service-tag decision. |

## Evidence (coordinator)

- ADR-0005 lines 1-89 are identical to the sequence start (`ecdc5b3`), so the 2026-09-22 record is unchanged.
- `just infra build` passes (both parameter files). `./check-and-lint.sh`: 241 of 241 test files, docs build and format included (`it7-gate.txt`).
- Consistency counts after IT-7 (agent's run): `egressNsgEnforce` 17, `egressAllowedPorts` 2, `egressFqdnMode` 12, `egressAllowedFqdns` 12, `threatIntelMode` 7, `privateEndpointAddresses` 6, `deployNetprobe` 7, `netControls` 12, `EGRESS_EXTRA_BLOCKED_CIDRS` 12, `net-sim` 5, `net-verify` 20, `egress-hosts` 9, `egress.netprobe_result` 15.

## Executor

cursor-agent, `composer-2.5`, 100 tool calls. The coordinator rewrote the "any full apply changes more than the NSG" paragraph.
