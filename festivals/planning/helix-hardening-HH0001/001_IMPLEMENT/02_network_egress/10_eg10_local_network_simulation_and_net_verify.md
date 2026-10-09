---
fest_type: task
fest_id: 10_eg10_local_network_simulation_and_net_verify.md
fest_name: eg10 local network simulation and net verify
fest_parent: 02_network_egress
fest_order: 10
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.026345-06:00
fest_tracking: true
---

# Task: eg10 local network simulation and net verify

## Objective

Prove the NSG rule table's ordering and logic locally by applying `nsg-egress-rules.json` as `iptables` packet filters on a probe container inside Docker networks that mirror the subnets, running the real probe against stand-in targets (`just infra net-sim`), and add `just infra net-verify`, the operator recipe that starts the probe job in Azure and prints its result. Implements EG-10 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `05_eg5_nsg_module_and_subnet_attachment.md` (the rule file the simulation reads), `08_eg8_probe_entry_point.md` (the probe it runs, unchanged) and `09_eg9_probe_job_posture_output_and_alerts.md` (the job `net-verify` starts, and the inputs the simulation mirrors).
- [ ] **Where it runs.** The dev container cannot run Docker: `.devcontainer/docker-compose.yml` and `.devcontainer/devcontainer.json` mount no Docker socket and add no Docker-in-Docker feature (checked), and the container has no `NET_ADMIN`. The design says to run `just infra net-sim` in the dev container; that is not possible as the container is built today. Record this mismatch in `results/`. `net-sim` runs on a host with a Docker daemon (Docker Desktop or Linux), from the repository root, with `just` and Node 24 installed on that host. The dev container still runs the static half (the translator tests, `node --test`), and `just infra build` stays the Bicep check (`az` is installed in the dev container, not on every host). Decision V4 (local containers only) still holds.
- [ ] Layout: user-defined Docker networks stand in for `snet-egress`, `snet-apps`, `snet-postgres` and `snet-pe`, plus the platform address, the metadata address and a "public" network. Stand-in containers sit at fixed addresses: an apps-environment listener on 443, Postgres on 5432, the three vault endpoints and the Blob endpoint on 443, a wire-server stand-in at `168.63.129.16` (DNS on 53, HTTP on 80 and 32526), a metadata stand-in at `169.254.169.254`, a public allow-listed host (443, 25, 22, 8443) and a public canary host (443).
- [ ] Enforcement: the probe container is attached to every network, runs with `NET_ADMIN`, and a setup step translates `nsg-egress-rules.json` into rules on its `OUTPUT` chain, one rule per row in priority order, first match wins, `DROP` for deny rows so a blocked connect times out like Azure's NSG (a drop, not a reset). Service tags have no local meaning and map to named placeholder CIDRs; `Internet` maps to `0.0.0.0/0`.
- [ ] Failure path: DNS must go through the filter. Docker's embedded resolver (127.0.0.11) forwards from outside the container and would bypass the rules, so the setup rewrites the probe container's `/etc/resolv.conf` to `nameserver 168.63.129.16`.
- [ ] `just infra net-sim` builds the networks and stand-ins, applies the rule table, runs the probe, and passes for all three columns: `off` (no rules), `deny-list-only` and `enforce`. Each scenario's pass condition is the probe's own exit code (0), plus the runner's assertion on specific check lines.
- [ ] `just infra net-sim` also runs negative scenarios and requires the probe to fail in each: the rule `allow-azure-dns` removed (DNS dies, so names go `unresolved`), `deny-vnet` renumbered to sit above `allow-postgres` (Postgres goes `blocked`), and the closing-deny-less `deny-list-only` table checked against `enforce` expectations (ports 25, 22 and 8443 stay reachable where the probe expects `blocked`). The runner names the check line that must fail in each.
- [ ] The static half needs no Docker: `infra/netsim/translate.test.mjs` (run with `node --test`) checks the rule file's invariants and the translator's output. `just infra net-sim --static` runs only that half.
- [ ] `just infra net-verify` starts the Azure job, waits for the execution, prints the probe lines and exits non-zero when the execution fails. Its recipe comment says it is an operator step, run against a real install, not CI, and **unverified in Azure** by this work.
- [ ] The simulation's limits are written down, in the runner's header comment and in `results/`: it proves rule ordering and logic, the drop-versus-reset handling, that the positive controls survive the deny rules, that the probe fails when a rule is wrong or missing, and the probe's own code paths. It does not prove Azure NSG semantics (statefulness, default rules, augmented rules, tag membership), attachment to a populated Container Apps subnet, the platform flows, the source address of edge-to-egress traffic, or the behavior of `168.63.129.16` from a replica. The stand-in answers because the simulation says it does. Inbound rules are not exercised at all.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-10-netsim`.

2. Read before writing: `infra/azure/nsg-egress-rules.json` and the probe's check table (`apps/egress/src/netprobe.ts` from `08_...`, `buildChecks`), `.justfiles/infra.just` (a short file today: one `build` recipe under a header that says deployment steps stay in the README), and `.justfiles/db.just` for how a recipe forwards `*args` (`[positional-arguments]`, `"$@"`).

3. Create `infra/netsim/` with these files.

   **`Dockerfile`** (one image for the probe and every stand-in):

```dockerfile
FROM node:24-bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 dnsmasq \
 && update-alternatives --set iptables /usr/sbin/iptables-legacy \
 && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
 && rm -rf /var/lib/apt/lists/*
```

   (The legacy backend avoids "Failed to initialize nft" on some Docker Desktop kernels. If `update-alternatives` fails on the base image, drop those two lines and say which backend worked in `results/`.)

   **`networks.json`**: the whole layout as data, so the runner and the translator's address map share it:

```json
{
  "networks": {
    "egress":   { "subnet": "10.0.4.0/23" },
    "apps":     { "subnet": "10.0.2.0/23" },
    "postgres": { "subnet": "10.0.6.0/24" },
    "pe":       { "subnet": "10.0.7.0/24" },
    "platform": { "subnet": "168.63.129.0/24" },
    "imds":     { "subnet": "169.254.169.0/24" },
    "public":   { "subnet": "198.51.100.0/24" }
  },
  "probe": { "network": "egress", "ip": "10.0.4.10" },
  "standins": [
    { "name": "apps-ilb",       "network": "apps",     "ip": "10.0.2.10",       "listen": [443] },
    { "name": "postgres",       "network": "postgres", "ip": "10.0.6.4",        "listen": [5432] },
    { "name": "kv-platform",    "network": "pe",       "ip": "10.0.7.4",        "listen": [443] },
    { "name": "kv-connections", "network": "pe",       "ip": "10.0.7.5",        "listen": [443] },
    { "name": "kv-delegated",   "network": "pe",       "ip": "10.0.7.6",        "listen": [443] },
    { "name": "blob-pe",        "network": "pe",       "ip": "10.0.7.7",        "listen": [443] },
    { "name": "wire-server",    "network": "platform", "ip": "168.63.129.16",   "listen": [80, 32526], "dns": true },
    { "name": "imds",           "network": "imds",     "ip": "169.254.169.254", "listen": [80] },
    { "name": "public-allowed", "network": "public",   "ip": "198.51.100.10",   "listen": [443, 25, 22, 8443] },
    { "name": "public-canary",  "network": "public",   "ip": "198.51.100.11",   "listen": [443] }
  ],
  "names": { "pg.sim.test": "10.0.6.4", "allowed.sim.test": "198.51.100.10", "canary.sim.test": "198.51.100.11" },
  "refs": {
    "$vnet": "10.0.0.0/16", "$egressSubnet": "10.0.4.0/23", "$appsSubnet": "10.0.2.0/23",
    "$postgresSubnet": "10.0.6.0/24", "$kvConnectionsIp": "10.0.7.5", "$kvDelegatedIp": "10.0.7.6"
  },
  "allowedPorts": ["80", "443"],
  "tags": {
    "Internet": "0.0.0.0/0",
    "MicrosoftContainerRegistry": "192.0.2.0/28", "AzureFrontDoor.FirstParty": "192.0.2.16/28",
    "AzureActiveDirectory": "192.0.2.32/28", "AzureMonitor": "192.0.2.48/28",
    "AzureLoadBalancer": "192.0.2.64/28"
  }
}
```

   These addresses equal the template's defaults (the endpoint addresses `.4` to `.7` from `04_...`). If a Docker address pool overlaps a subnet on the host, Docker refuses the network; free the conflicting network or choose another unused range and change the matching entries consistently. If Docker refuses the link-local `imds` network, put the stand-in on the `platform` network, add `169.254.169.254/32` to its interface with `ip addr add`, and add a `/32` route in the probe via that interface; the stand-in answers ARP for its own address.

   **`listener.mjs`**: a few lines, no dependencies: for each port in `process.argv`, `net.createServer((s) => s.end()).listen(port, "0.0.0.0")`. A closed-connection listener is enough; the probe only needs the handshake to complete.

   **`translate.mjs`** (pure; used by the container-side applier and by the tests):

```js
export function loadRules(json) { /* returns json.rules */ }
export function activeRules(rules, mode) { /* mode off => []; else filter by r.modes.includes(mode) */ }
export function resolveRule(rule, { refs, tags, allowedPorts }) {
  // dst prefixes: refs[p] ?? tags[p] ?? p;  ports: "$allowedPorts" expands; "*" means any
}
export function toIptables(rules, mode, ctx) {
  // returns an array of argument arrays for `iptables`, in order:
  //   -F OUTPUT
  //   -A OUTPUT -o lo -j ACCEPT
  //   -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  //   one or more rules per outbound row, ascending priority (Allow -> ACCEPT, Deny -> DROP)
  //   -A OUTPUT -j ACCEPT        <- Azure's default AllowInternetOutBound
  // protocol "*" with specific ports emits a tcp rule and a udp rule; Tcp or Udp emit one;
  // "*" with ports "*" emits a rule with no -p. A port range "a-b" becomes --dport a:b.
}
export function applyBreak(rules, spec) {
  // spec "remove:allow-azure-dns" or "renumber:deny-vnet:105"; throws on an unknown rule name
}
```

   Outbound rows only: inbound rows are validated (unique priorities) but not translated.

   **`translate.test.mjs`** (`node:test` and `node:assert`). Cases: every `(direction, priority)` pair in the real rule file is unique; every `$`-name used in the rule file exists in `networks.json` `refs` (and `$allowedPorts` is handled); every non-literal prefix is a known tag; `allow-azure-dns` has a lower priority number than `deny-wire-server`; `deny-vnet` is numbered above (later than) `allow-own-subnet`, `allow-postgres`, `allow-key-vault-endpoints` and `allow-azure-dns`; `deny-all-outbound` appears in the `enforce` set and not in `deny-list-only`; `off` yields no rules; golden translations for `allow-postgres` (`-A OUTPUT -p tcp -d 10.0.6.0/24 --dport 5432 -j ACCEPT`), `deny-private-ranges` (three `DROP` rules), `allow-internet-web` (two ACCEPT rules, ports 80 and 443, destination `0.0.0.0/0`), `allow-azure-dns` (a tcp and a udp rule on 53) and `deny-all-outbound` (`-A OUTPUT -j DROP`); `applyBreak` removes or renumbers and rejects an unknown name.

   **`apply.mjs`** (runs inside the probe container): arguments `--mode <off|deny-list-only|enforce> [--break <spec>]`; reads the mounted rule file, `networks.json`, calls `toIptables`, runs each command with `execFileSync("iptables", args)`, rewrites `/etc/resolv.conf` to `nameserver 168.63.129.16`, then prints the number of rules installed. Mode `off` still flushes `OUTPUT` and still rewrites `resolv.conf` (DNS must work through the stand-in in every column).

   **`run.mjs`** (host side, Node built-ins only, header comment states the limits above): flags `--static` (translator tests only), `--keep` (leave containers up), `--scenario <name>`. Steps: run `node --test infra/netsim`; stop here for `--static`; check `docker info` and fail with a clear message if there is no daemon; build the image `helix-netsim`; create each network with `docker network create --internal --subnet <subnet> helix-netsim-<name>` (`--internal` so nothing reaches the real internet); start each stand-in with `docker run -d --name helix-netsim-<name> --network helix-netsim-<net> --ip <ip> helix-netsim node /sim/listener.mjs <ports>` with `infra/netsim` mounted read-only at `/sim`; start dnsmasq in the `wire-server` stand-in (`dnsmasq -k --no-resolv --no-hosts --address=/pg.sim.test/10.0.6.4 --address=/allowed.sim.test/198.51.100.10 --address=/canary.sim.test/198.51.100.11`, generated from `names`); start the probe container (`--cap-add NET_ADMIN`, fixed IP on the egress network, repo files mounted read-only: `infra/netsim` at `/sim`, `infra/azure/nsg-egress-rules.json` at `/sim/nsg-egress-rules.json`, `apps/egress/src/netprobe.ts` at `/probe/netprobe.ts`, `sleep infinity`), then `docker network connect --ip` it to the other networks. Run the scenarios in a loop with `docker exec`:

| scenario | applied table | probe `PROBE_EXPECT_NSG` | required result |
|---|---|---|---|
| `off` | none | `off` | exit 0 |
| `deny-list-only` | `deny-list-only` | `deny-list-only` | exit 0 |
| `enforce` | `enforce` | `enforce` | exit 0 |
| `break-dns` | `enforce`, `--break remove:allow-azure-dns` | `enforce` | exit 1; the `dns-resolve` line has `actual: "unresolved"` |
| `break-order` | `enforce`, `--break renumber:deny-vnet:105` | `enforce` | exit 1; the `postgres-5432` line has `actual: "blocked"` |
| `broken-closing-deny` | `deny-list-only` | `enforce` | exit 1; the `public-port-25` line has `actual: "reachable"` |

   Every scenario's probe environment: `PROBE_EXPECT_FIREWALL=false`, `PROBE_EXPECT_FQDN_ALLOWLIST=false`, `PROBE_FQDN_PROTOCOL=tcp` (there is no firewall or TLS stand-in in the simulation), `PROBE_TIMEOUT_MS=2000`, the four endpoint and apps addresses from `networks.json`, `PROBE_POSTGRES_HOST=pg.sim.test`, `PROBE_ALLOWED_HOST=allowed.sim.test`, `PROBE_CANARY_HOST=canary.sim.test`. Parse the probe's stdout lines as JSON, print one table row per scenario (pass or fail and why), tear everything down in a `finally` unless `--keep`, and exit non-zero if any scenario's requirement is not met.

4. `.justfiles/infra.just`: update the header comment (lines 1-3) to say deployment steps stay in the README except the two operator recipes below, and add:

```just
# Simulate the egress NSG rule table with Docker networks and iptables, run the probe against stand-ins (needs a Docker daemon on this host, not the dev container); --static runs only the translator tests
[positional-arguments]
net-sim *args:
    node infra/netsim/run.mjs "$@"

# OPERATOR STEP, not CI: start the network probe job in a deployed install and print its result. Unverified in Azure by the work that added it; needs `az login` and the containerapp extension.
net-verify resource-group prefix='helix-prod':
    #!/usr/bin/env bash
    set -euo pipefail
    exec_name="$(az containerapp job start -g '{{resource-group}}' -n '{{prefix}}-netprobe' --query name -o tsv)"
    echo "started execution ${exec_name}"
    # Poll until the execution leaves Running, then print its lines and mirror its status.
    #   az containerapp job execution show -g ... -n ... --job-execution-name "$exec_name" --query properties.status -o tsv
    #   az containerapp job logs show -g ... -n ... --execution "$exec_name" --container netprobe --format text
```

   Fill in the polling loop (every 10 seconds for up to 10 minutes) and the final exit code (0 for `Succeeded`, 1 otherwise). Confirm every flag against `az containerapp job start --help`, `az containerapp job execution show --help` and `az containerapp job logs show --help` in the dev container (the Azure CLI is installed there; the containerapp extension may need `az extension add --name containerapp`), and note any flag you could not confirm. Job logs reach Log Analytics with a delay; if `logs show` is empty right after the execution ends, retry for up to a few minutes before reporting no output. Confirm the recipe parses with `just --list --justfile .justfiles/infra.just` and `just --dry-run infra net-verify rg-test`.

5. Run the static half in the dev container: `node --test infra/netsim`. Then, on a Docker host: `just infra net-sim` (all six scenarios) and `just infra net-sim --scenario break-dns` once alone. Save the full output of both, plus the output of `just infra --list`, in `results/`. Run the mutation check once by hand: change the real `nsg-egress-rules.json` locally so `deny-vnet` has priority 105 and confirm `just infra net-sim --scenario enforce` fails; restore the file.

6. Docs. `infra/azure/README.md`: a short "Verifying the network controls" subsection that names the two recipes and the simulation's limits; the full rewrite of the verification section is `11_...`. Nothing else here: the simulation is dev tooling.

7. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `node --test infra/netsim` passes in the dev container. Output saved under `results/`.
- [ ] `just infra net-sim` passes all six scenarios on a Docker host: the three positive columns exit 0, the three negative runs fail on the named check lines. Output saved under `results/`. If no Docker host is available, stop and report: the evidence cannot be produced without one, and it must not be replaced by an untested claim.
- [ ] The mutation check (renumbered `deny-vnet`) fails the `enforce` scenario and the file is restored.
- [ ] `just infra build` passes (the rule file is read by `nsg.bicep`, so a change to its shape would show here). `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` is not required: no edge, portal or egress code changes.
- [ ] Committed with `fest commit -m "EG-10: local network simulation and net-verify recipe"`.
- [ ] Unverified in Azure, written into the runner header and `results/`: Azure NSG semantics versus the iptables translation (statefulness, default rules, augmented rules, tag membership); attachment of an NSG to a populated Container Apps subnet; the platform flows the NSG must allow; the behavior of `168.63.129.16` from a replica (the stand-in answers because the simulation says it does); the source address of edge-to-egress traffic through the internal load balancer; the inbound rules, which the simulation does not exercise; and `just infra net-verify` itself, which only an operator on a real install can run. That run is the only test that settles the hypothesis rows; its results go into the ADR-0005 amendment (`11_...`).
