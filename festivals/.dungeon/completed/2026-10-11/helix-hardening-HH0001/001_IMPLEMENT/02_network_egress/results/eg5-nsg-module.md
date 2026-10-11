# EG-5 result: NSG module and subnet attachment

**Result: done, with a changed default.** Every install gets a network security group on `snet-egress`. The rules live in one shared table, `infra/azure/nsg-egress-rules.json` (EG-10's local simulation reads the same table), loaded and filtered by the new `infra/azure/modules/nsg.bicep`; `network.bicep` attaches it. The Key Vault allow rule names the pinned endpoint addresses when `pinPrivateEndpointAddresses` is on (EG-4) and falls back to the whole `snet-pe` prefix when off (the weaker rule, documented). Parameters: `egressNsgEnforce` (`off`, `deny-list-only`, `enforce`) and `egressAllowedPorts` (default 80 and 443). The egress container now gets `EGRESS_EXTRA_BLOCKED_CIDRS` set to the VNet prefix plus the Container Apps infrastructure slice, so an install whose VNet is outside RFC 1918 is still blocked at the application layer (EG-2).

## Change made in review

The agent defaulted `egressNsgEnforce` to `enforce`, a closing deny-all on outbound internet built on platform-flow rules that are unverified in Azure (own subnet, MCR, Front Door, Entra, Monitor, DNS via `168.63.129.16`, the inbound ILB source). One missing rule would cut egress on an existing install's next deploy. The default is now `deny-list-only`, which still creates the NSG on every install (D3) and still denies private ranges, platform addresses, and other subnets. `enforce` is recommended for new installs and for existing ones after `just infra net-verify` (EG-10) passes. Parameter description, `apps/docs/src/deploy/configuration.md`, `infra/azure/README.md`, and the commented examples updated. Recorded in `decisions.md`.

## Evidence

- `just infra build` passed (after the default change too). The agent checked the rule table's structure once (unique priorities per active path, token references, modes present).
- Gate: all test files passed (`eg5-gate.txt`).

## Unverified in Azure

Attaching an NSG to an existing, populated Container Apps subnet (the operator rollout notes, EG-11, start with N1's scratch-copy test); every platform-flow allow rule; the `100.64.0.0/10` deny; the inbound ILB source rule for edge to egress; service-tag membership. The per-mode output for `enforce` was not re-checked after the CLI refused `--parameters` on a module build.

## Executor

cursor-agent, `composer-2.5`, 49 tool calls; coordinator edits for the default.
