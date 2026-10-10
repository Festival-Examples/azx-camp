# EG-11 result: documentation and ADR amendments

**Result: done.** New `docs/features/network-controls.md`, linked from `docs/features/README.md` and `docs/features/fetch-proxy.md`. It covers the four layers, the per-install settings with their real template defaults, the probe and the three recipes, the implementation files, what the controls do not stop, the deferred items, an unverified-in-Azure table, and the operator rollout notes in the order the task gave.

- **ADR-0005:** a `## Amendment (2026-10-10): network controls behind the SSRF filter` appended after the "Perf note". It covers the baseline layers, what the old "primary control" text means now, and the accepted-risk exception. It also has a host-node section citing Microsoft's two pages, the new ranges (including `100:0:0:1::/64`, RFC 9780, from EG-3), the honest limit on Postgres and the two vaults, and an empty probe-results table of 11 rows. The 2026-09-22 record is unchanged: the diff is one hunk of additions after line 89.
- **ADR-0028:** a network bullet under the existing `## Amendment (2026-10-09): admission controls are per-install settings`. The spend sequence (SP-13) created that section; this task extended it, and there is still one amendment section.
- **ADR-0046:** a dated note that the Foundry host must be in the allow-list when `egressFqdnMode` is `allowlist`.
- **"No outbound internet route" claims** are conditioned on `deployFirewall` in `docs/platform-architecture.md`, `docs/platform-project-plan.md` and `docs/features/fetch-proxy.md`. The "primary control" wording in `apps/docs/src/deploy/getting-started.md` and `configuration.md` now separates the baseline (application filter plus NSG) from the firewall tier.
- **Other docs:** `apps/docs/src/deploy/updates.md` gains the `just infra net-verify` step. `infra/azure/README.md` has a reworked intro and firewall context, and "Verifying the isolation (post-deploy)" is rewritten to lead with `netControls` and `net-verify`, keeping the edge-to-egress `/health` check and the data-services checks. `docs/features/observability.md` lists the probe events and alerts with the workspace each reads. `TODO.md` gains the four deferred items.
- **Rule table (from EG-8's finding):** only the `note` text of `deny-wire-server` and `deny-link-local` in `infra/azure/nsg-egress-rules.json` changed, plus the matching sentence in the `infra/azure/modules/nsg.bicep` header. Both now say the prefix denies do not filter Azure's documented host-node paths and that `ssrf.ts` is the control there. No priority, prefix, port, mode, access or status changed.

## Coordinator corrections

- The ADR-0028 bullet said the network settings have "strict defaults". They do not: `egressFqdnMode` defaults to `any` and `egressNsgEnforce` to `deny-list-only`, chosen so a template update does not break an existing install. The bullet now says so, and that the strict values are an operator's step once the probe is green.
- The feature page's settings table called the `deny-list-only` default "Strict"; it now names it the safe-on-upgrade middle setting, with `enforce` as the strict one. It also said the probe job needs `deployInfraAlerts`; only its alerts do.

## Code versus design, as documented

- Endpoint pinning is opt-in (`pinPrivateEndpointAddresses`, default false).
- The NSG default is `deny-list-only`.
- `threatIntelMode` defaults to `Deny` and `egressFqdnMode` to `any`.
- The probe treats WireServer and IMDS as informational, and gained `PROBE_PE_ADDRESSES`.
- The simulation runs on a Docker host, with `break-kv` in place of `break-dns`.

## Evidence

- Consistency check (`eg11-consistency.txt`): every name has at least one mention (`egressAllowedPorts` 2, `threatIntelMode` 5, the rest 5 to 14). `unverified in Azure` appears 4 times in the feature page and twice in ADR-0005. One ADR-0028 amendment section. ADR-0005's diff is additions after line 89 only.
- I checked the amendment's facts against the template: `egressNsgEnforce` allows `off`, `deny-list-only` and `enforce`; the firewall is the Standard tier at about $900/month (`infra/azure/README.md`); `deployFirewall` defaults to true; and RFC 9780 matches EG-3's result.
- `./check-and-lint.sh` passes (docs build and format included), 241 of 241 test files. `just infra build` passes. `node --test infra/netsim/translate.test.mjs` passes 18 of 18 (`eg11-gate.txt`).

## Unverified in Azure

Listed in the feature page and the ADR-0005 probe table: NSG attachment to a populated Container Apps subnet; the platform flows; the `100.64.0.0/10` deny; replica behavior at the host-node addresses; the edge-to-egress source address; static endpoint addresses; firewall runtime behavior; the diagnostic tables; and the operator-side steps. Nothing in this sequence was applied to Azure or to either live install.

## Executor

cursor-agent, `composer-2.5`, 92 tool calls. Coordinator corrections as listed.
