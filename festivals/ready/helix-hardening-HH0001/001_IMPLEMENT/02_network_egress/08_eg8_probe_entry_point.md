---
fest_type: task
fest_id: 08_eg8_probe_entry_point.md
fest_name: eg8 probe entry point
fest_parent: 02_network_egress
fest_order: 8
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.025682-06:00
fest_tracking: true
---

# Task: eg8 probe entry point

## Objective

Write the network probe: a self-contained Node entry point in the egress app that tries to connect to each forbidden and each required destination, classifies the result as `blocked`, `reachable` or `unresolved`, prints one JSON line per check, and exits non-zero when anything differs from what the install's configuration says to expect. Implements EG-8 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `01_eg1_block_list_additions_and_boundary_tests.md` (the design lists it; the probe itself does not import `ssrf.ts`) and `05_eg5_nsg_module_and_subnet_attachment.md` (the NSG modes whose expectations the probe encodes). `09_eg9_probe_job_posture_output_and_alerts.md` runs it as a job and `10_eg10_local_network_simulation_and_net_verify.md` runs it in Docker.
- [ ] New file `apps/egress/src/netprobe.ts` imports only Node built-ins (`node:net`, `node:dns/promises`, `node:tls`, `node:process`, `node:url`). No new dependency, no import from the rest of the egress app, no `pino`: the file must run in a bare `node:24` container with nothing installed (the simulation in `10_...` relies on that), so keep it to syntax Node strips natively (no enums, no namespaces, no parameter properties).
- [ ] Classification, from the socket's own evidence. A completed connect is `reachable`. A connect that does not complete before the timeout, or fails with `ETIMEDOUT`, is `blocked`. A refusal or reset (`ECONNREFUSED`, `ECONNRESET`) is **`reachable`**: the packet reached something, so a control that drops traffic did not stop it. A name that does not resolve (`ENOTFOUND`, `EAI_AGAIN`) is `unresolved`. Any other error code (`EHOSTUNREACH`, `ENETUNREACH`, a certificate error) is a fourth value, `error`, which never matches an expectation, so it counts as a mismatch unless the check is informational. The design names three values; `error` exists so an unexpected failure cannot pass as `blocked`.
- [ ] Failure path. For the two public-host checks that test the firewall's FQDN filter, a plain TCP connect proves nothing: an application rule needs the TLS server name, so the firewall can accept the TCP handshake and drop the connection after the ClientHello. **Hypothesis, unverified in Azure.** Those two checks therefore attempt a TLS handshake with the host as the server name, and treat a handshake that times out or is reset as `blocked`. `PROBE_FQDN_PROTOCOL=tcp` (the simulation sets it) degrades them to plain connects. Every other check is a plain TCP connect, where a reset still means "not blocked".
- [ ] Inputs come from environment variables only, all validated at start (see step 3). Missing or malformed input exits with code 2 and a message on stderr, distinct from a failed check (exit 1).
- [ ] Output: one JSON line per check on stdout with `event: "egress.netprobe_check"`, then one summary line with `event: "egress.netprobe_result"`. The design calls the event `netprobe`; the logging convention in `docs/design/logging.md` ("The `event` convention") requires `<domain>.<verb>` with a registered domain, and `egress` is registered, so use the convention and record the deviation in `results/`. No whole URL, no secret, no credential, no header appears in any line: targets are written as `host:port` only.
- [ ] Exit code 0 when every non-informational check matches; 1 when any does not; 2 for a configuration error.
- [ ] Informational checks never cause a mismatch; they record what happened (this settles the open question about `168.63.129.16` on an install with no NSG).
- [ ] The expected values follow the install's posture. Wire-server, IMDS and `kv-platform`/Blob endpoint checks expect `blocked` when the NSG mode is `deny-list-only` or `enforce`, informational when `off`. The apps-environment check is always informational: the design expects it blocked, but the apps environment is external (`internal: false`, `infra/azure/main.bicep:752-758`; `aca-environment.bicep:5-8`), so its static IP is the public load balancer address and egress reaching it is an ordinary internet path, not lateral movement. Record the design mismatch in `results/`; lateral movement inside the VNet is covered by the `kv-platform` and Blob endpoint checks. Ports 25, 22 and 8443 on a public host expect `blocked` only in `enforce`, informational otherwise. The two vault endpoints egress uses, Postgres, the allow-listed public host, and DNS expect `reachable` in every mode. The canary host expects `blocked` when `PROBE_EXPECT_FQDN_ALLOWLIST` is true and `reachable` otherwise.
- [ ] No span or metric. The probe's telemetry is its log lines (the failure and absence alerts in `09_...` read them). The line names go in `docs/design/logging.md`'s "Currently in use" table in this change.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-8-netprobe-entry-point`.

2. Read before writing: `docs/design/logging.md` ("The `event` convention" and "Currently in use"), `apps/egress/src/ssrf.ts` lines 18-23 (the plain-class style) and `infra/azure/modules/migrate-job.bicep:115-116` (how a job overrides the image command; `09_...` uses the same shape). Note `apps/egress/tsconfig.json` extends the repo base with `rootDir: src`, so the file is type-checked by `pnpm -r typecheck`.

3. Create `apps/egress/src/netprobe.ts`. Shape (write the bodies in the style of the rest of the app: explicit types, comments only for constraints):

```ts
import { lookup } from "node:dns/promises";
import { connect as netConnect, isIP } from "node:net";
import { connect as tlsConnect } from "node:tls";
import { pathToFileURL } from "node:url";

export type Outcome = "blocked" | "reachable" | "unresolved" | "error";
export type Expectation = Outcome | "informational";
export type NsgMode = "off" | "deny-list-only" | "enforce";

export interface ProbeConfig {
  nsg: NsgMode; // PROBE_EXPECT_NSG
  firewall: boolean; // PROBE_EXPECT_FIREWALL
  fqdnAllowlist: boolean; // PROBE_EXPECT_FQDN_ALLOWLIST
  fqdnProtocol: "tls" | "tcp"; // PROBE_FQDN_PROTOCOL, default tls
  appsIp: string; // PROBE_APPS_IP
  kvPlatformIp: string; // PROBE_KV_PLATFORM_IP
  blobIp: string; // PROBE_BLOB_PE_IP
  kvConnectionsIp: string; // PROBE_KV_CONNECTIONS_IP
  kvDelegatedIp: string; // PROBE_KV_DELEGATED_IP
  postgresHost: string; // PROBE_POSTGRES_HOST
  allowedHost: string; // PROBE_ALLOWED_HOST: a public host on the platform list, e.g. mcr.microsoft.com
  canaryHost: string; // PROBE_CANARY_HOST: a public host deliberately on no list
  timeoutMs: number; // PROBE_TIMEOUT_MS, default 5000
}

export interface CheckSpec {
  id: string; // stable, e.g. "wire-server-80"
  kind: "tcp" | "tls" | "dns";
  host: string;
  port: number; // 0 for dns
  expect: Expectation;
}

export interface CheckResult {
  id: string;
  target: string; // host:port, never a URL
  expected: Expectation;
  actual: Outcome;
  ok: boolean;
}
```

   Functions to write and export:
   - `parseConfig(env: Record<string, string | undefined>): ProbeConfig`: reads the `PROBE_*` names above. Booleans accept only `"true"` or `"false"`. `PROBE_EXPECT_NSG` accepts only the three `NsgMode` values. The five address variables must satisfy `isIP`. Host variables must match `/^[a-z0-9.-]+$/i`. Timeout must be a positive integer. Reject a contradiction: `PROBE_EXPECT_FQDN_ALLOWLIST=true` with `PROBE_EXPECT_FIREWALL=false` (a firewall that is not deployed cannot filter names). Throw an `Error` whose message names the variable; `main` turns it into exit code 2.
   - `buildChecks(cfg: ProbeConfig): CheckSpec[]`: the table below, in this order. `denyOnly = cfg.nsg !== "off"`, `enforce = cfg.nsg === "enforce"`.

| id | kind | target | expect |
|---|---|---|---|
| `wire-server-80`, `wire-server-32526` | tcp | `168.63.129.16` ports 80, 32526 | `denyOnly ? "blocked" : "informational"` |
| `imds-80` | tcp | `169.254.169.254:80` | same |
| `apps-env-443` | tcp | `appsIp:443` | `informational` (always; see Requirements) |
| `kv-platform-443`, `blob-pe-443` | tcp | those IPs, 443 | same |
| `kv-connections-443`, `kv-delegated-443` | tcp | those IPs, 443 | `reachable` |
| `postgres-5432` | tcp | `postgresHost:5432` | `reachable` |
| `public-allowed-443` | `fqdnProtocol` | `allowedHost:443` | `reachable` |
| `public-canary-443` | `fqdnProtocol` | `canaryHost:443` | `fqdnAllowlist ? "blocked" : "reachable"` |
| `public-port-25`, `public-port-22`, `public-port-8443` | tcp | `allowedHost` ports 25, 22, 8443 | `enforce ? "blocked" : "informational"` |
| `dns-resolve` | dns | `allowedHost` | `reachable` |

   (The wire-server ports 80 and 32526 are from memory of the Azure platform documentation: **Hypothesis**, confirm against the current Azure virtual public IP page and record the answer in `results/`. The 25/22/8443 checks may be dropped by the Azure platform itself on any install, which is why they are informational unless the closing deny is on.)
   - `classify(error: NodeJS.ErrnoException | undefined, timedOut: boolean): Outcome`: pure, so the table of codes is directly testable.
   - `probeTcp(host, port, timeoutMs, deps?)`, `probeTls(host, port, timeoutMs, deps?)`, `probeDns(host, deps?)`: each returns an `Outcome`. They resolve a hostname with `lookup` first (a literal IP skips that step, use `isIP`), so a resolution failure is `unresolved` before any socket opens. A TCP probe uses `socket.setTimeout(timeoutMs)` (a bare `net.connect` has no timeout of its own; the OS default is minutes) and destroys the socket on every path. The TLS probe passes `servername: host` and treats `secureConnect` as `reachable`. The `deps` argument (`{ lookup, netConnect, tlsConnect }`, defaults the real ones) is the test seam.
   - `runChecks(specs, cfg, deps?)`: runs the checks (sequentially is fine; the table is small and a dropped connect costs `timeoutMs`), returns `CheckResult[]`. `ok` is `true` when `expect === "informational"` or `expect === actual`.
   - `main(env, write)`: `parseConfig`, `buildChecks`, `runChecks`, write one line per result and the summary, return the exit code. The module's last lines run it only when executed directly, so importing it in a test does nothing:

```ts
if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.env, (line) => process.stdout.write(`${line}\n`));
}
```

   Line shapes:

```json
{"event":"egress.netprobe_check","check":"wire-server-80","target":"168.63.129.16:80","expected":"blocked","actual":"blocked","ok":true}
{"event":"egress.netprobe_result","ok":true,"checks":15,"failed":0,"nsg":"enforce","firewall":false,"fqdnAllowlist":false}
```

   Include the time as `time` (ISO string) on both so the log store sorts them. A config error writes to stderr, not stdout, and returns 2.

4. Add the script that runs it in the image. `apps/egress/package.json` (the `scripts` block, lines 6-10) gets `"probe": "node --import tsx src/netprobe.ts"`, the same loader form as `start`. `09_...` runs the job with `command: ['pnpm']` and `args: ['--filter', '@azx-pbc/egress', 'probe']`.

5. Tests, `apps/egress/src/netprobe.test.ts` (style of `apps/egress/src/ssrf.test.ts`: `describe`/`it`/`it.each`, listeners from `node:net`, ephemeral ports on `127.0.0.1`):
   - `classify`: `it.each` of codes. `ETIMEDOUT` and a timeout flag give `blocked`; `ECONNREFUSED` and `ECONNRESET` give `reachable` (not `blocked`); `ENOTFOUND` and `EAI_AGAIN` give `unresolved`; `EHOSTUNREACH` gives `error`; no error and no timeout gives `reachable`.
   - `probeTcp` against real local sockets: a listening server gives `reachable`; a port that was just released gives `reachable` (a refusal is not a block); a fake `netConnect` that returns a socket that never connects, with `timeoutMs: 50`, gives `blocked` (this is the "dropped connect"); a fake that emits `ECONNRESET` gives `reachable`; a fake `lookup` that rejects with `ENOTFOUND` gives `unresolved` and the connect fake is never called.
   - `probeTls`: a local `tls.createServer` with a throwaway certificate is heavy; instead inject a `tlsConnect` fake that emits `secureConnect` (gives `reachable`), emits a reset before `secureConnect` (gives `blocked`), and never emits (gives `blocked` on timeout). Assert the fake was called with `servername` equal to the host.
   - `buildChecks`: for each of the three NSG modes and both `fqdnAllowlist` values, assert the expected column of every row in the table above (a loop over a small matrix, not a snapshot).
   - `parseConfig`: a complete env parses; each required variable missing throws an error naming it; `PROBE_EXPECT_FQDN_ALLOWLIST=true` with `PROBE_EXPECT_FIREWALL=false` throws; `PROBE_EXPECT_NSG=maybe` throws; a non-IP address variable throws.
   - `main`: with a fake `deps` where every check returns its expected value, the exit code is 0 and the last line is a result line with `ok: true`; flip one non-informational result and the exit code is 1 and that check's line has `ok: false`; an informational mismatch does not change the exit code; a config error returns 2 and writes nothing to stdout.
   - Output hygiene: run `main` with an env that also contains `DATABASE_URL=postgres://u:supersecret@db/x` and a `PROBE_*` set; join every written line and assert it contains neither `supersecret` nor `://`.

6. Docs. `docs/design/logging.md`, "Currently in use" table (after the `egress.connection_retire_failed` row): add `egress.netprobe_check` / `egress.netprobe_result` | `apps/egress/src/netprobe.ts` — the network probe's per-check and summary lines; the failure and absence alerts read the summary. `docs/features/fetch-proxy.md` lists the egress files at line 418; add `netprobe.ts` there in one clause. The operator-facing text is `11_...`.

7. Run `pnpm vitest run apps/egress/src/netprobe.test.ts`, then try the entry point by hand against local listeners to see real output: start two `node -e` listeners, set the `PROBE_*` variables to loopback addresses and `PROBE_EXPECT_NSG=off`, run `node apps/egress/src/netprobe.ts` (Node 24 strips types) and `pnpm --filter @azx-pbc/egress probe`, and paste both outputs into `results/`.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `netprobe.test.ts` passes: drop versus reset, unresolved name, informational checks, mismatch exit code, config errors and output hygiene.
- [ ] The file imports nothing but `node:` modules (`grep -n "^import" apps/egress/src/netprobe.ts`), and `node apps/egress/src/netprobe.ts` runs directly under the dev container's Node 24 with no loader and no workspace install in its way (Node strips the types).
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (egress still boots; the new file is not imported by the server). Output saved under `results/`.
- [ ] Committed with `fest commit -m "EG-8: network probe entry point for egress"`.
- [ ] Unverified in Azure: the wire-server ports, how a firewall application rule drops a connection (the TLS-handshake rule above), and everything the probe will report when it runs on a real install. Those are what `just infra net-verify` is for.
