---
fest_type: task
fest_id: 09_eg9_probe_job_posture_output_and_alerts.md
fest_name: eg9 probe job posture output and alerts
fest_parent: 02_network_egress
fest_order: 9
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.025992-06:00
fest_updated: 2026-10-10T03:33:37.450727-06:00
fest_tracking: true
---


# Task: eg9 probe job posture output and alerts

## Objective

Run the probe from `08_eg8_probe_entry_point.md` as a scheduled, on-demand Container Apps Job named `<prefix>-netprobe` inside the egress environment, publish the install's network posture as a `netControls` output of `main.bicep`, and alert when the probe fails or has not succeeded recently. Implements EG-9 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `07_eg7_firewall_allow_list_tier_and_drift_tooling.md` (`egressFqdnMode`, the effective allow-list, and the `egressAllowedFqdnsEffective` output this task folds in), `08_eg8_probe_entry_point.md` (the `probe` script and the `PROBE_*` inputs), and, through them, `04_eg4_fixed_private_endpoint_addresses.md` (the vault and Blob addresses the probe checks) and `05_eg5_nsg_module_and_subnet_attachment.md` (the NSG modes). `10_eg10_local_network_simulation_and_net_verify.md` starts this job.
- [ ] New `infra/azure/modules/netprobe-job.bicep`: a Container Apps Job with a schedule trigger (daily) that can also be started by hand, in the **egress** environment (`egressEnv`, not `appsEnv`): the probe must travel through the same subnet, NSG and route table as egress, and a job in the apps environment would prove nothing about egress.
- [ ] The job runs the egress image (`${imageRegistry}/helix-egress:${imageTag}`) with `command: ['pnpm']` and `args: ['--filter', '@azx-pbc/egress', 'probe']`. No new image, no new dependency.
- [ ] A dedicated user-assigned identity (`<prefix>-netprobe-id`) with **no role assignments**. The probe holds none of egress's secrets and calls no Azure API, so its compromise is worth nothing. Unlike `migrate-job.bicep`, which creates a vault role, this module creates none.
- [ ] `main.bicep` passes the probe's inputs from the template's own values, one source of truth: `PROBE_EXPECT_FIREWALL` from `deployFirewall`, `PROBE_EXPECT_FQDN_ALLOWLIST` from `deployFirewall && egressFqdnMode == 'allowlist'`, `PROBE_EXPECT_NSG` from `egressNsgEnforce`, `PROBE_APPS_IP` from `appsEnv.outputs.staticIp`, the four endpoint addresses from `peIps`, `PROBE_POSTGRES_HOST` from the Postgres FQDN, and `PROBE_ALLOWED_HOST` and `PROBE_CANARY_HOST` from two new parameters.
- [ ] `PROBE_ALLOWED_HOST` defaults to `mcr.microsoft.com`, which is on the egress platform list in every mode (`06_...`), so it is reachable with the firewall off, on in `any` mode, and on in `allowlist` mode. `PROBE_CANARY_HOST` defaults to `example.net`, a real public host that is on no list. An operator who removes MCR from the platform list must change the allowed host.
- [ ] `main.bicep` gains a `netControls` object output: firewall on or off, FQDN mode, threat-intel mode, NSG mode, the allowed ports, the effective allow-list, the endpoint addresses, the extra blocked CIDRs, and the probe's job name and expectations. No secret appears in it. The README and the accepted-risk record in ADR-0005 stop restating the posture in prose and point at this output plus the last probe result (that wording is written in `11_...`).
- [ ] Alerts, in a new `infra/azure/modules/alerts-netprobe.bicep`: one fires when a probe execution reports a failure, one fires when no probe execution has reported success recently. Both read the **egress** environment's Log Analytics workspace (`egressEnv.outputs.logAnalyticsWorkspaceId`), because each environment has its own (`aca-environment.bicep:27-36`) and the job's console output lands in the egress one. This differs from the firewall-denial alert in `07_...`, which reads the apps workspace.
- [ ] Failure path. A job that cannot start (image tag without the `probe` script, bad env, schedule disabled) produces no failure line, so the "no recent success" alert is what catches it. Do not write a failure-only alert.
- [ ] Failure path. A probe false negative: the probe accepts only a timeout as `blocked` (`08_...`), so a reset cannot hide a path. Nothing to build here; note it in the alert descriptions.
- [ ] Per decision N4 the probe is an alert plus an explicit `just infra net-verify` step in the operator runbook (`10_...`), not a deploy gate. The job does not block, order or gate any other deployment.
- [ ] `deployNetprobe` (default `true`) turns the job and its alerts off for an install that cannot run them yet; the job and alerts need `deployApps`.
- [ ] Unverified in Azure: that the job runs, that the alert queries match the real log shape, that a Count-below-threshold alert fires when the log table has no matching rows at all, and that the schedule and manual start both work.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-9-netprobe-job`.

2. Read before writing: `infra/azure/modules/migrate-job.bicep` (the whole file; it is the job precedent: lines 86-138 for the resource, 115-116 for `command`/`args`, 65-68 for the identity), `infra/azure/modules/certbot.bicep:159-164` (the `Schedule` trigger shape: `triggerType`, `replicaTimeout`, `replicaRetryLimit`, `scheduleTriggerConfig` with `cronExpression` and `parallelism`), `infra/azure/modules/alerts.bicep:104-136` (the log-alert shape), and the `module migrateJob` call in `main.bicep` (line 1522).

3. Create `infra/azure/modules/netprobe-job.bicep`:

```bicep
@description('Azure region.')
param location string
@description('Resource name prefix.')
param namePrefix string
@description('Egress ACA environment resource id. The probe must run on snet-egress to exercise the same NSG and route table as egress.')
param acaEnvId string
@description('Egress image (the probe is a script inside it), e.g. ghcr.io/azx-pbc-oss/helix-egress:sha-xxxx. The tag must contain the probe script.')
param image string
@description('Cron for the scheduled run. Default daily 04:00 UTC. The job can also be started on demand.')
param cronExpression string = '0 4 * * *'
@description('Seconds before a stuck run is killed. 15 checks times a 5 s timeout is about 75 s; this leaves room for slow DNS.')
param replicaTimeout int = 300
@description('PROBE_* environment, built in main.bicep from the template\'s own values. Non-secret by construction.')
param probeEnv array

resource probeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-netprobe-id'
  location: location
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-netprobe'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${probeIdentity.id}': {} }
  }
  properties: {
    environmentId: acaEnvId
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: replicaTimeout
      replicaRetryLimit: 0
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        parallelism: 1
        replicaCompletionCount: 1
      }
    }
    template: {
      containers: [
        {
          name: 'netprobe'
          image: image
          command: ['pnpm']
          args: ['--filter', '@azx-pbc/egress', 'probe']
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: probeEnv
        }
      ]
    }
  }
}

output jobName string = job.name
output jobId string = job.id
output identityPrincipalId string = probeIdentity.properties.principalId
```

   Add a header comment in the style of `migrate-job.bicep` (why a job, why in the egress environment, why the identity has no roles, that it never runs as a deploy gate). `replicaRetryLimit: 0` because a failed probe is a result to read, not something to retry into a pass.

4. Create `infra/azure/modules/alerts-netprobe.bicep` using the `registryNeverLoadedRule` structure (`scheduledQueryRules@2022-06-15`, `kind: 'LogAlert'`). Parameters: `location`, `namePrefix`, `workspaceId`, `actionGroupId` (default empty, then `actionGroupIds` as in `alerts.bicep:45`), `severity` (default 2), `noSuccessWindow` (default `'PT36H'`, the daily schedule plus slack). Two rules, queries on one line:

```bicep
var failedQuery = 'ContainerAppConsoleLogs_CL | extend p = parse_json(Log_s) | where tostring(p.event) == "egress.netprobe_result" | where tobool(p.ok) == false | project TimeGenerated, Failed = toint(p.failed)'
var successQuery = 'ContainerAppConsoleLogs_CL | extend p = parse_json(Log_s) | where tostring(p.event) == "egress.netprobe_result" | where tobool(p.ok) == true | project TimeGenerated'
```

   Failure rule: `timeAggregation: 'Count'`, `operator: 'GreaterThan'`, `threshold: 0`, `evaluationFrequency: 'PT1H'`, `windowSize: 'PT1H'`. Success-absence rule: `operator: 'LessThan'`, `threshold: 1`, `evaluationFrequency: 'PT1H'`, `windowSize: noSuccessWindow`. Describe in each rule what to do: read the failing check lines in the egress workspace, then run `just infra net-verify`; for the absence rule check that the job exists, its schedule is enabled and its image tag contains the probe. Mention in the failure rule that a reset is not counted as blocked, so a failure is real. **Confirm** the table name `ContainerAppConsoleLogs_CL`, the column `Log_s`, and that a job's stdout lands there (the rules in `alerts.bicep` read the same table for the apps; a job is a different resource kind), and say so as unverified in Azure in the module header.

5. `main.bicep`:
   - Parameters (near `egressNsgEnforce`): `deployNetprobe` (bool, default `true`), `netprobeAllowedHost` (string, default `'mcr.microsoft.com'`), `netprobeCanaryHost` (string, default `'example.net'`), each with a description.
   - The job module, after `module migrateJob` (line 1522), gated `if (deployApps && deployNetprobe)`:

```bicep
module netprobeJob 'modules/netprobe-job.bicep' = if (deployApps && deployNetprobe) {
  name: 'netprobe-job'
  params: {
    location: location
    namePrefix: namePrefix
    acaEnvId: egressEnv.outputs.environmentId
    image: '${imageRegistry}/helix-egress:${imageTag}'
    probeEnv: [
      { name: 'PROBE_EXPECT_FIREWALL', value: deployFirewall ? 'true' : 'false' }
      { name: 'PROBE_EXPECT_FQDN_ALLOWLIST', value: deployFirewall && egressFqdnMode == 'allowlist' ? 'true' : 'false' }
      { name: 'PROBE_EXPECT_NSG', value: egressNsgEnforce }
      { name: 'PROBE_APPS_IP', value: appsEnv.outputs.staticIp }
      { name: 'PROBE_KV_PLATFORM_IP', value: peIps.kvPlatform }
      { name: 'PROBE_BLOB_PE_IP', value: peIps.blob }
      { name: 'PROBE_KV_CONNECTIONS_IP', value: peIps.kvConnections }
      { name: 'PROBE_KV_DELEGATED_IP', value: peIps.kvDelegated }
      { name: 'PROBE_POSTGRES_HOST', value: pgFqdn }
      { name: 'PROBE_ALLOWED_HOST', value: netprobeAllowedHost }
      { name: 'PROBE_CANARY_HOST', value: netprobeCanaryHost }
    ]
  }
  dependsOn: [egressApp]
}
```

     (Booleans are written as a `? 'true' : 'false'` ternary, the form `main.bicep` already uses for `EDGE_ALLOW_PUBLIC_APPS` at line 1221, because ARM's `string()` on a boolean renders `True` or `False` and the probe's parser accepts only lowercase `true` and `false`. `pgFqdn` is the existing variable at line 668.) `dependsOn: [egressApp]` is only to order the first start after egress exists; drop it if Bicep reports the dependency is implied.
   - The alerts module, after `module infraAlerts` (line 937), gated `if (deployInfraAlerts && deployApps && deployNetprobe)`, with `workspaceId: egressEnv.outputs.logAnalyticsWorkspaceId` and `actionGroupId: actionGroupId`.
   - The output, next to the other posture outputs (after `llmBudgetUsd`, line 1569). Fold in the output `07_...` added (`egressAllowedFqdnsEffective`; keep it, it is the machine-readable list the drift command compares against):

```bicep
@description('The network controls this deployment declares, in one object, so nobody restates them in prose: firewall, FQDN mode, threat intelligence, NSG mode, allowed ports, the effective allow-list, the fixed private-endpoint addresses, the extra blocked CIDRs, and the probe job with its expectations. Read it next to the last probe result (`just infra net-verify`). Declared posture, not proof: the probe is the proof.')
output netControls object = {
  deployFirewall: deployFirewall
  egressFqdnMode: deployFirewall ? egressFqdnMode : 'n/a'
  threatIntelMode: deployFirewall ? threatIntelMode : 'n/a'
  egressNsgEnforce: egressNsgEnforce
  egressAllowedPorts: egressAllowedPorts
  egressAllowedFqdns: deployFirewall && egressFqdnMode == 'allowlist' ? egressProductFqdns : []
  privateEndpointAddresses: peIps
  extraBlockedCidrs: '${vnetAddressPrefix},100.100.0.0/17'
  probe: {
    deployed: deployApps && deployNetprobe
    jobName: '${namePrefix}-netprobe'
    expectFirewall: deployFirewall
    expectFqdnAllowlist: deployFirewall && egressFqdnMode == 'allowlist'
    expectNsg: egressNsgEnforce
  }
}
```

     Use the variable that holds the extra-CIDR string from `05_...` rather than repeating it, if that task introduced one; if it wrote the string inline, introduce a `var egressExtraBlockedCidrs` now and use it in both places.
   - `main.bicepparam` and `main.bootstrap.bicepparam`: commented lines for the three new parameters (`deployNetprobe`, `netprobeAllowedHost`, `netprobeCanaryHost`).

6. Docs. `apps/docs/src/deploy/configuration.md`: rows for the three parameters (networking or observability table, next to `deployInfraAlerts`). `docs/features/observability.md`: add `alerts-netprobe.bicep` to the module table (lines 321-324) with what it reads (the probe's `egress.netprobe_result` line in the egress workspace) and what it covers, and mention that it is the one alert module that reads the egress workspace. `infra/azure/README.md`: add the two modules to the Layout block (lines 496-515) and a short "Network probe" paragraph (what the job checks, how to read `netControls`, where the log lines are); the verification procedure rewrite is `11_...`. `docs/design/logging.md` already lists the events (`08_...`).

7. Run `just infra build`; also compile `netprobe-job.bicep` and `alerts-netprobe.bicep` standalone and confirm in the JSON that the job has no `roleAssignments` anywhere in the module and that both alert queries are on one line. Save the output in `results/`.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `just infra build` passes for `main.bicep`, both parameter files and both new modules. Output saved under `results/`. The `netControls` output appears in the built template with the fields above and no secret value.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` is not required: no edge, portal or egress code changes in this task.
- [ ] `just infra build` is the only Azure check available here; the job, the schedule and the alerts are unverified in Azure (decision V4).
- [ ] Committed with `fest commit -m "EG-9: scheduled network probe job, netControls output and probe alerts"`.
- [ ] Unverified in Azure, stated in the module headers and `results/`: that the job runs and the image tag carries the probe script, that the schedule and a manual start both work, that the alert queries match the real log table and columns, that a Count-below-1 alert fires when no matching row exists, and that each probe expectation holds on a real install. The `net-verify` run by an operator is what settles these.