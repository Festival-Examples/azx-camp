# EG-6 result: firewall platform lists and threat intelligence

**Result: done.** In `infra/azure/modules/firewall.bicep` the single platform FQDN list is split per subnet (`appsPlatformFqdns`, `egressPlatformFqdns`) with application rules for each, adding the hosts the apps subnet needs when the firewall is on (Microsoft Graph for the portal's directory client, the ACME directory for certbot via `acmeServerHost`, Azure Resource Manager, Entra) and a network rule for the `AzureKeyVault` service tag. Threat intelligence is a parameter, `threatIntelMode` (`Alert`, `Deny`, `Off`), defaulting to `Deny`. `main.bicep`, the parameter files, and `infra/azure/README.md` describe the firewall as the optional tier on top of the `ssrf.ts` filter and the NSG.

## Changes made in review

The parameter description already explained the stricter default and how to revert; the coordinator added the same to `infra/azure/README.md` ("Optional: the egress firewall"), because an install that already runs the firewall becomes stricter on its next template apply.

## Deviation from the task, accepted

The design's "Done when" for EG-6 says the egress subnet should stop inheriting GHCR. The agent kept GHCR and `*.blob.core.windows.net` on the egress list because image pulls for egress revisions may still route through the firewall; dropping them could stop a revision from starting. Revisit after `just infra net-verify` (EG-10) on a real install.

## Evidence

- `just infra build` passed. Gate: all test files passed (`eg6-gate.txt`).

## Unverified in Azure

Threat intelligence `Deny` on the Basic SKU (the template uses Standard); the runtime effect of every host list; the `AzureKeyVault` service tag in a firewall-policy network rule; whether egress still needs the registry and Blob hosts.

## Executor

cursor-agent, `composer-2.5`, 37 tool calls; coordinator README edit.
