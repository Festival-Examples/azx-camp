---
fest_type: task
fest_id: 07_eg7_firewall_allow_list_tier_and_drift_tooling.md
fest_name: eg7 firewall allow list tier and drift tooling
fest_parent: 02_network_egress
fest_order: 7
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.025406-06:00
fest_updated: 2026-10-10T02:56:48.105153-06:00
fest_tracking: true
---



# Task: eg7 firewall allow list tier and drift tooling

## Objective

Add the opt-in FQDN allow-list tier for installs that run the Azure Firewall (`egressFqdnMode` and `egressAllowedFqdns`), send firewall logs to Log Analytics with an alert on application-rule denials from the egress subnet, and add `just infra egress-hosts`, which prints the hosts that approved apps and connection providers need and marks the ones the deployed list is missing. Implements EG-7 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `06_eg6_firewall_platform_lists_and_threat_intel.md` (the per-subnet platform lists and the firewall module's new shape). `09_eg9_probe_job_posture_output_and_alerts.md` depends on this task.
- [ ] `egressFqdnMode` has two values: `any` (today's behavior: the `targetFqdns: ['*']` rule) and `allowlist`. The Bicep parameter default is `any`, so an existing firewall install that takes a template update does not change. The reference parameter files (`main.bicepparam`, `main.bootstrap.bicepparam`) set `allowlist`, which is what a new install copies. This is how "default `allowlist` for new installs, existing installs stay on `any`" is met without changing the behavior of an install whose own parameter file never mentions the setting.
- [ ] In `allowlist` mode the `['*']` rule is replaced by a product rule whose targets are the LLM vendor hosts (derived from the template's own LLM parameters), plus `egressAllowedFqdns` (the operator's additions: connection-provider hosts and approved-origin hosts). The egress platform rule from `06_...` already covers the platform hosts. An empty product list is refused at compile time (it would leave egress with no internet at all).
- [ ] The list is **not** generated from approvals (decision N3). A new approved origin or provider does nothing until the operator adds its host to `egressAllowedFqdns` and applies the template.
- [ ] `any` mode is byte-identical in behavior to today: one rule, `['*']`, ports 80 and 443.
- [ ] A diagnostic setting sends the firewall's application-rule, network-rule and threat-intelligence logs to the apps environment's Log Analytics workspace, resource-specific tables.
- [ ] An alert fires on application-rule denials whose source is the egress subnet. It uses the log-alert shape of `registryNeverLoadedRule` in `infra/azure/modules/alerts.bicep:104-136`.
- [ ] `just infra egress-hosts` prints the approved fetch-proxy origins' hosts (from `apps.capabilities`, archived apps skipped) and the connection providers' token-endpoint and API-origin hosts (from `connection_providers`), and marks each as listed or MISSING against a deployed list the operator passes in.
- [ ] Failure path. A host missing from the allow-list fails silently at the app (a generic upstream error). Mitigations in this task: the denial alert, and the drift command. The probe's drift check is `08_...`/`09_...`.
- [ ] Failure path. A manifest that no longer parses does not crash the command: it is reported by app slug and skipped.
- [ ] Failure path. Postgres is private-endpoint-only, so the command cannot run from an operator laptop. The documented Azure path runs it inside the portal replica (the portal image already ships `pnpm`, `tsx` and the scripts; the migrate job runs from it). This path is **unverified in Azure**.
- [ ] Whitelisting is by FQDN: `any` and `allowlist` both stay on ports 80 and 443 only. A host on another port is blocked in both modes (and by the NSG from `05_...`).
- [ ] Unverified in Azure: firewall runtime behavior, SNI-only matching for application rules without TLS inspection (a client that dials an arbitrary IP with an allowed SNI would pass; this is a hypothesis), rule-collection limits, and the diagnostic table and column names the alert reads.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-7-firewall-allowlist-tier`.

2. `firewall.bicep`. Add the parameters and switch the internet rule. The existing collection is `egress-internet` (lines 94-115) with the rule `egress-to-any-https` at lines 103-113.

```bicep
@allowed(['any', 'allowlist'])
@description('any = snet-egress may reach every FQDN on 80/443 (the behavior before the allow-list existed). allowlist = only the platform hosts and egressProductFqdns.')
param egressFqdnMode string = 'any'

@description('Hosts the egress app legitimately calls beyond the platform: the LLM vendor hosts and the operator additions (connection providers, approved fetch origins). Used only in allowlist mode.')
param egressProductFqdns array = []

var internetRule = egressFqdnMode == 'any'
  ? {
      ruleType: 'ApplicationRule'
      name: 'egress-to-any-https'
      sourceAddresses: [egressSubnetPrefix]
      targetFqdns: ['*']
      protocols: [
        { protocolType: 'Https', port: 443 }
        { protocolType: 'Http', port: 80 }
      ]
    }
  : {
      ruleType: 'ApplicationRule'
      name: 'egress-to-product-fqdns'
      sourceAddresses: [egressSubnetPrefix]
      targetFqdns: empty(egressProductFqdns)
        ? fail('egressFqdnMode is allowlist but the product host list is empty; egress would have no internet access. Set egressAllowedFqdns or the LLM endpoints.')
        : egressProductFqdns
      protocols: [
        { protocolType: 'Https', port: 443 }
        { protocolType: 'Http', port: 80 }
      ]
    }
```

   and use `rules: [internetRule]` in the `egress-internet` collection. Update the comment above the collection (lines 95-96) for the two modes. Leave the `aca-platform` collection and the Key Vault network collection from `06_...` alone.

3. `main.bicep`. Next to `deployFirewall` (line 372) add `egressFqdnMode` (`@allowed(['any','allowlist'])`, default `'any'`) and `egressAllowedFqdns` (`array`, default `[]`), with descriptions that state: strict value is `allowlist`; existing firewall installs stay `any` until the operator runs `just infra egress-hosts` and adds what it prints; the cost is an operator step per new approved origin. Derive the vendor hosts in `main.bicep`, near the `llm` variable (lines 637-644). Strip scheme, path and port; for a BYO Foundry install also take the host suffixes from `egressManagedIdentityConnections` (the `connection=host` pairs, `main.bicep:650-652`), because ADR-0046 requires the Foundry host in the list:

```bicep
func hostOf(url string) string => split(split(replace(replace(url, 'https://', ''), 'http://', ''), '/')[0], ':')[0]
var vendorHosts = union(
  [hostOf(llm.anthropicEndpoint), hostOf(llm.openaiEndpoint)],
  empty(egressManagedIdentityConnections)
    ? []
    : map(split(egressManagedIdentityConnections, ','), p => split(trim(p), '=')[1])
)
var egressProductFqdns = union(vendorHosts, egressAllowedFqdns)
```

   (`func` is a Bicep user-defined function; it sees only its own arguments, which is all this one needs. If the installed Bicep rejects it, inline the expression with `map`.) Pass `egressFqdnMode` and `egressProductFqdns` to `module firewall` (lines 507-517). Add an output `egressAllowedFqdnsEffective` (array) returning `egressProductFqdns`, with a description that this is the list the firewall enforces in `allowlist` mode; `09_...` folds it into `netControls`.

4. `main.bicepparam` and `main.bootstrap.bicepparam`: set `param egressFqdnMode = 'allowlist'` with a comment (what it does, that it only matters when `deployFirewall` is true, that an install with its own parameter file keeps `any` unless it sets this) and a commented `// param egressAllowedFqdns = ['api.vendor.example']` line. Both files already carry `deployFirewall` (lines 42-48 and 56-61).

5. Firewall logs and the denial alert, in a new module, because the diagnostic setting needs the apps workspace, and the apps environment depends on the firewall (`main.bicep:760`, `dependsOn: [firewall]`): putting the setting inside `firewall.bicep` would create a cycle. Create `infra/azure/modules/firewall-diagnostics.bicep`:

```bicep
param location string
param namePrefix string
@description('Name of the firewall resource (<namePrefix>-fw).')
param firewallName string
@description('Log Analytics workspace id the logs and the alert use (the apps environment workspace).')
param workspaceId string
param egressSubnetPrefix string
@description('Action group id, or empty (the rule then notifies nobody; see alerts.bicep).')
param actionGroupId string = ''
param includeDenialAlert bool = true

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' existing = {
  name: firewallName
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${namePrefix}-fw-logs'
  scope: firewall
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'AZFWApplicationRule', enabled: true }
      { category: 'AZFWNetworkRule', enabled: true }
      { category: 'AZFWThreatIntel', enabled: true }
    ]
  }
}
```

   Add the alert after it, copying the structure of `registryNeverLoadedRule` (`alerts.bicep:104-136`: `Microsoft.Insights/scheduledQueryRules@2022-06-15`, `kind: 'LogAlert'`, `scopes: [workspaceId]`, `criteria.allOf` with `timeAggregation: 'Count'`, `failingPeriods`, `autoMitigate`, `actions.actionGroups`). Keep the KQL on one line, as that file does, with the subnet from a parameter:

```bicep
var deniedQuery = 'AZFWApplicationRule | where Action == "Deny" | where ipv4_is_in_range(SourceIp, "${egressSubnetPrefix}") | project TimeGenerated, SourceIp, Fqdn'
```

   Severity 2, `evaluationFrequency: 'PT5M'`, `windowSize: 'PT15M'`, threshold `GreaterThan 0`, the description telling the reader that a denial from the egress subnet usually means an approved origin or provider host is not in `egressAllowedFqdns` and pointing at `just infra egress-hosts`. **Confirm the table and column names** (`AZFWApplicationRule`, `Action`, `SourceIp`, `Fqdn`) against the Azure Monitor table reference before committing; they are from memory and **unverified in Azure**. Wire it in `main.bicep` after the environments and `actionGroup` (the action group variable is `actionGroupId`, `main.bicep:865`):

```bicep
module firewallDiagnostics 'modules/firewall-diagnostics.bicep' = if (deployFirewall) {
  name: 'firewall-diagnostics'
  params: {
    location: location
    namePrefix: namePrefix
    firewallName: '${namePrefix}-fw'
    workspaceId: appsEnv.outputs.logAnalyticsWorkspaceId
    egressSubnetPrefix: egressSubnetPrefix
    actionGroupId: actionGroupId
    includeDenialAlert: deployInfraAlerts
  }
  dependsOn: [firewall]
}
```

   (`appsEnv.outputs.logAnalyticsWorkspaceId` is `aca-environment.bicep:78-79`.) Guard the alert resource with `if (includeDenialAlert)`. The probe's rules in `09_...` scope the **egress** environment's workspace instead, because each environment has its own workspace (`aca-environment.bicep:27-36`).

6. The drift command. Put the logic where the database tooling already lives, in the portal. Precedent: `apps/portal/scripts/backfill-app-owners.ts` (a `tsx` script using `createPrismaClient` from `apps/portal/src/db/client.ts`) with a package script (`apps/portal/package.json` lines 11-19).
   - `apps/portal/src/netControls/egressHosts.ts` (new, pure): `hostsFromApps(rows)` takes `{ slug, capabilities }`, parses `capabilities` with the shared `CapabilitiesSchema` (`safeParse`; a failure becomes an `unparseable` entry, never a throw), and returns `{ host, source: "app:<slug>" }` for each `capabilities.fetch.origins[].origin` (`FetchConnectionSchema.origin`, `packages/shared/src/manifest.ts:171`; the list is `origins` at line 201). `hostsFromProviders(rows)` takes `{ ref, tokenEndpoint, apiOrigins }` and returns the token endpoint host and each API origin host with `source: "provider:<ref>"`. The `authorizeEndpoint` is a browser redirect target, not an egress call, so it is not needed in the firewall list; say so in a comment. Hosts come from `new URL(x).hostname`, lowercased, port dropped (the firewall rules in this task are 80/443). `matchesFqdn(host, pattern)`: case-insensitive exact match, or a `*.suffix` pattern matching any host that ends in `.suffix` with at least one extra label. `diffHosts(needed, deployed)` returns each host with its sources and `listed` true or false.
   - `apps/portal/scripts/egress-hosts.ts` (new): flags `--deployed <comma-separated list>` and `--deployed-file <path>` (a JSON array of strings, or `-` for stdin), `--json`, and `--check` (exit 1 when any host is missing). Reads the dev or portal database through `createPrismaClient()`: `prisma.app.findMany({ where: { archivedAt: null }, select: { slug: true, capabilities: true } })` and `prisma.connectionProvider.findMany({ where: { env: "prod" }, select: { ref: true, tokenEndpoint: true, apiOrigins: true } })` (fields in `apps/portal/prisma/schema.prisma`, model `ConnectionProvider` at line 590). Prints a table: host, sources, listed or MISSING. Disconnects the client in `finally`.
   - `apps/portal/package.json`: add `"egress:hosts": "tsx scripts/egress-hosts.ts"` beside `seed:llm` (line 16).
   - `.justfiles/infra.just`: add the recipe next to `build`. The module header says deployment steps stay in the README, so keep the recipe a thin local wrapper and document the Azure invocation in the README (step 8):

```just
# Print the hosts approved apps and connection providers need and mark those missing from a deployed allow-list; arguments go to the script, e.g. --deployed a.example.com,b.example.com
[positional-arguments]
egress-hosts *args:
    pnpm --filter @azx-pbc/portal egress:hosts -- "$@"
```

7. Tests.
   - `apps/portal/src/netControls/egressHosts.test.ts` (pure, no database): origins with and without ports and uppercase; two apps sharing a host merge into one row with two sources; a provider contributes its token-endpoint host and each API origin; the authorize endpoint host is not included; an unparseable manifest is reported and skipped; `matchesFqdn` cases (`*.example.com` matches `a.example.com` and `a.b.example.com`, does not match `example.com` or `badexample.com`; exact match is case-insensitive); `diffHosts` marks listed and missing.
   - `apps/portal/src/netControls/egressHosts.integration.test.ts`: the design asks for a check against a local database. Use `createTestPrisma()` and `uniqueSlug()` from `apps/portal/src/test/harness.ts` (lines 28 and 64). Insert an app with an approved fetch origin and one archived app, and a provider, following `apps/portal/src/connections/consent.test.ts:114-130` for the row shapes; call the function the script uses to read and combine (factor it as `collectNeededHosts(prisma)` in `egressHosts.ts` so the script and the test share it); assert the archived app's host is absent and the others present with the right sources; delete the rows in `afterAll`.
   - Bicep: compile with `just infra build`. Also build `firewall.bicep` standalone once per mode and read the JSON: in `any` mode the rule is `egress-to-any-https` with `*`; in `allowlist` mode it is `egress-to-product-fqdns` with the derived hosts; with an empty list the build fails with the `fail()` message. Save outputs in `results/`.

8. Docs. `infra/azure/README.md`: rewrite the firewall section (lines 61-103) so it describes the two modes and rewrite the phrase "(to any FQDN)" at line 65 to name `egressFqdnMode`; add the "when a new origin is approved on a firewall install" step (run the command, add the printed hosts to `egressAllowedFqdns`, apply) and the Azure invocation of the command through `az containerapp exec` into the portal replica, labeled unverified in Azure; add `firewall-diagnostics.bicep` to the Layout block (lines 496-515). `apps/docs/src/deploy/configuration.md`: rows for `egressFqdnMode` and `egressAllowedFqdns` near `deployFirewall` (line 85). `docs/features/observability.md`: add the firewall-denial rule to the alert-module table at lines 321-324 (a row for `firewall-diagnostics.bicep`) and the log tables it reads. The ADR text is `11_...`.

9. Run the focused tests (`pnpm vitest run apps/portal/src/netControls`), `just infra build`, and the gate.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The pure and integration tests pass; the standalone Bicep builds show the correct rule per mode and the compile-time refusal for an empty list. Outputs saved under `results/`.
- [ ] `just infra build` passes for `main.bicep`, both parameter files and the new module. Output saved under `results/`.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (the portal gains `apps/portal/src/netControls/`, a portal change). Output saved under `results/`.
- [ ] `just infra build` is the only Azure check available here (decision V4); firewall and alert behavior are unverified in Azure.
- [ ] `just infra egress-hosts` runs against the dev database and prints a table (paste the output into `results/`).
- [ ] Committed with `fest commit -m "EG-7: firewall FQDN allow-list tier, firewall logs and egress-hosts drift command"`.
- [ ] Unverified in Azure: firewall runtime behavior in `allowlist` mode, SNI-only application-rule matching, rule-collection limits, the diagnostic setting and the table and column names the alert queries, and running the drift command inside the portal replica.