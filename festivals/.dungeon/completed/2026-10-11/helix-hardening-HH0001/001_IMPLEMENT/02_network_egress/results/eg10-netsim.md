# EG-10 result: local network simulation and net-verify

**Result: done.** `infra/netsim/` simulates the egress NSG rule table locally. It has a Node 24 image with legacy iptables, `iproute2` and `dnsmasq`. `networks.json` holds the layout. `listener.mjs` runs the stand-ins. `translate.mjs` turns rule rows into `OUTPUT`-chain iptables lines: priority order, `DROP` for deny rows, service tags as placeholder CIDRs, `pePinning` variants, and Azure's host-node exemption. `apply.mjs` installs the rules in the probe container and points `resolv.conf` at the WireServer stand-in. `run.mjs` is the host runner. `just infra net-sim` builds `--internal` Docker networks for the four subnets plus the platform, metadata and public networks. It runs the real `apps/egress/src/netprobe.ts` against the stand-ins in seven scenarios and tears down only `helix-netsim-*` containers and networks. `just infra net-verify <resource-group> [prefix]` is the operator recipe that starts `<prefix>-netprobe` in Azure, waits up to ten minutes, prints the probe lines and mirrors the execution status. `infra/azure/README.md` gains a "Verifying the network controls" subsection.

## Changes from the task

- **Host-node exemption modeled (coordinator note).** Before any NSG row, the translator accepts tcp and udp 53, tcp 80 and tcp 32526 to `168.63.129.16`, and everything to `169.254.169.254`. Azure documents these paths as exempt from prefix-based NSG rules (sources in `eg8-probe-entry-point.md`), so the simulation no longer shows blocks Azure would not apply.
- **`break-dns` replaced by `break-kv`.** With the exemption, removing `allow-azure-dns` cannot break DNS in Azure. The negative scenario removes `allow-key-vault-endpoints` under `enforce` and requires `kv-connections-443` to be `blocked`. The `allow-azure-dns`-before-`deny-wire-server` invariant stays in the tests; the runner header calls the row belt-and-braces.
- **Pinned and unpinned rows (from EG-4).** The translator keeps rows without `pePinning` plus the variant asked for. The uniqueness invariant holds per pinning variant. A seventh scenario, `deny-list-only-unpinned`, runs the unpinned table with `PROBE_PE_ADDRESSES=dynamic`.
- **Where it runs.** The dev container has no Docker socket and no `NET_ADMIN`, so `net-sim` runs on a Docker host (here, the macOS host). The design said to run it in the dev container. The translator tests run in both places.
- **Mutation check without editing the real file.** `run.mjs --rules <path>` mounts a copy of the rule table. While a run is active it copies the table to `infra/netsim/.docker-rules.json` so Docker Desktop can mount it, and removes it in `finally`. The coordinator added that path to `.gitignore` in case a run is interrupted.
- **Coordinator fixes after review.** `net-verify` keeps waiting while the execution is `Processing`, not only `Running` or `Unknown`; the agent's loop would have stopped early and exited 1. The recipe header no longer calls `net-sim` an operator step. `activeRulesForInvariants`, a line-for-line copy of `activeRules`, was removed. The README and the runner header named `node --test infra/netsim`, which fails on Node 24 (a directory argument is treated as a module path, so 1 test, 1 failure). They now name `node --test infra/netsim/translate.test.mjs`. The agent's report claimed 18 of 18 for the directory form; that claim was wrong.
- **Probe invocation.** The simulation runs the probe with plain `node` (Node 24 strips types), from a read-only mount of `netprobe.ts`.

## Evidence (all run by the coordinator)

- `just infra net-sim`, all seven scenarios, PASS: `off`, `deny-list-only`, `enforce` and `deny-list-only-unpinned` exit 0. `break-kv` exits 1 with `kv-connections-443` `blocked`. `break-order` exits 1 with `postgres-5432` `blocked`. `broken-closing-deny` exits 1 with `public-port-25` `reachable`. The runner checks the named line, not only the exit code (`eg10-netsim.txt`).
- `just infra net-sim --scenario break-kv` alone: PASS.
- Mutation check: a copy of the rule table with `deny-vnet` at 105, `just infra net-sim --scenario enforce --rules <copy>`: `enforce FAIL exit 1 (want 0)`, runner exit 1. The real `nsg-egress-rules.json` was not touched.
- The probe's check lines from an `enforce` run, in `eg10-netsim.txt`:
  - `kv-platform-443` and `blob-pe-443` are `blocked` (`deny-vnet`).
  - `kv-connections-443`, `kv-delegated-443` and `postgres-5432` are `reachable`.
  - Ports 25, 22 and 8443 are `blocked` (closing deny).
  - WireServer and IMDS are `reachable` through the exemption (informational).
  - Result: 15 checks, 0 failed.
- After every run, no `helix-netsim-*` container or network remained and `git status` showed only the intended changes.
- Dev container: `node --test infra/netsim/translate.test.mjs` and `just infra net-sim --static` pass 18 of 18. `just --list` shows `build`, `egress-hosts`, `net-sim` and `net-verify`. `just --dry-run infra net-verify rg-test` renders the script. `just infra build` passes. `./check-and-lint.sh` passes, 241 of 241 test files (`eg10-gate.txt`; the first pass failed format on `translate.test.mjs` and is kept there).
- The agent confirmed the `az containerapp job start`, `job execution show --job-execution-name` and `job logs show --execution --container --format text` flags in the dev container. The containerapp extension is in preview.

## Limits and unverified in Azure

The simulation proves rule ordering and first-match logic, drop-versus-reset handling, that the positive controls survive the deny rules, that the probe fails when a rule is wrong or missing, and the probe's code paths. It does not prove:
- Azure NSG semantics: statefulness, default rules, augmented rules, tag membership.
- NSG attachment to a populated Container Apps subnet.
- The platform flows the NSG must allow.
- What `168.63.129.16` and IMDS do from a replica (the stand-ins answer because the simulation says so).
- The source address of edge-to-egress traffic through the internal load balancer.
- The inbound rules, which it never exercises.

`just infra net-verify` itself has only been dry-run; an operator on a real install is the only one who can run it.

## Executor

cursor-agent, `composer-2.5`, 89 tool calls. Coordinator fixes as listed above.
