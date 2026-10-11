# EG-9 result: probe job, posture output and alerts

**Result: done.** `infra/azure/modules/netprobe-job.bicep` is a Container Apps Job, `<prefix>-netprobe`, in the egress environment. It runs daily at 04:00 UTC and can also be started on demand. It uses the egress image with `pnpm --filter @azx-pbc/egress probe`, `replicaRetryLimit: 0`, and a dedicated `<prefix>-netprobe-id` identity with no role assignments. `infra/azure/modules/alerts-netprobe.bicep` adds two log alerts on the egress workspace: a failed run (`egress.netprobe_result` with `ok=false`) and no successful run within `PT36H`. `main.bicep` adds `deployNetprobe` (default true; the job and alerts need `deployApps`, and the alerts also need `deployInfraAlerts`), `netprobeAllowedHost` (`mcr.microsoft.com`), `netprobeCanaryHost` (`example.net`), a `var egressExtraBlockedCidrs` shared with the egress app's env, and the `netControls` output. The parameter files carry commented lines for the three new parameters. Docs: parameter rows in `apps/docs/src/deploy/configuration.md`, a `PROBE_*` table in `docs/features/fetch-proxy.md`, the module row in `docs/features/observability.md`, and the layout entries plus a "Network probe" paragraph in `infra/azure/README.md`.

## Changes from the task

- **Endpoint addresses are optional (coordinator note).** `pinPrivateEndpointAddresses` defaults to false (EG-4), and then the four endpoint addresses are empty strings. The task's wiring would have made the probe exit 2 on every run, so the no-success alert would fire daily on every default install. The probe gained `PROBE_PE_ADDRESSES` (`pinned` or `dynamic`, required). With `dynamic`, the four endpoint variables must be unset and the four endpoint checks are omitted (11 checks instead of 15). With the NSG's unpinned fallback allowing the whole endpoint subnet, they could not be expected blocked anyway. `main.bicep` passes the four addresses only when pinning is on. `netControls.privateEndpointAddresses` is `{}` when unpinned, and `netControls.probe.peAddresses` records the mode. The summary line carries `peAddresses`.
- **No `peIps` variable.** The task named one that does not exist; the wiring uses the `pe*Ip` variables.
- **Host-node checks informational (from EG-8).** The alert descriptions and the README say that the WireServer and IMDS checks are informational and that the NSG does not filter those paths.
- **Fresh-deploy note (coordinator).** The no-success rule fires on a new deployment until the first run, because the job's first scheduled run can be up to a day away. Its description tells the operator to start one with `just infra net-verify` after deploying.

## Evidence

- `./check-and-lint.sh`: 241 of 241 test files, 3491 tests (`eg9-gate.txt`). `netprobe.test.ts` covers `parseConfig` in both endpoint modes (dynamic rejects a set endpoint address; pinned requires all four) and the `buildChecks` matrix in both modes.
- `just infra build` passes for `main.bicep`, both parameter files and the entra stack. Both new modules compile standalone. The job module's JSON has 0 `roleAssignments`. Both alert queries are single-line strings (191 and 164 characters). The built `netControls` output has the keys `deployFirewall`, `egressAllowedFqdns`, `egressAllowedPorts`, `egressFqdnMode`, `egressNsgEnforce`, `extraBlockedCidrs`, `privateEndpointAddresses`, `probe` and `threatIntelMode`, and no secret (`eg9-infra.txt`).
- The agent ran `just dev smoke --no-browser` after its gate and reports a pass. The server does not import `netprobe.ts`, and the task does not require smoke.
- The egress image ships `pnpm` and the workspace (`apps/egress/Dockerfile`, `CMD ["pnpm", "--filter", "@azx-pbc/egress", "start"]`). Images are pulled anonymously across the template (no `registries` in `main.bicep`), so the job pulls the same way the egress app does.

## Unverified in Azure

That the job starts on the schedule and on demand. That the deployed image tag carries the `probe` script. That job stdout lands in `ContainerAppConsoleLogs_CL` with JSON in `Log_s` in the egress workspace. That `PT36H` is accepted as a window size; Microsoft's page caps a log alert's time range at two days but lists no discrete values ([Create log search alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule), updated 2026-09-22). That a Count-below-1 rule fires when no row matches. And each probe expectation on a real install.

## Executor

cursor-agent, `composer-2.5`, 87 tool calls. The coordinator added the fresh-deploy sentence to the no-success alert description.
