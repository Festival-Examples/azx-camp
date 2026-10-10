# EG-8 result: probe entry point

**Result: done, with one change to the check table.** `apps/egress/src/netprobe.ts` is a standalone entry point that imports only `node:` modules. It connects to each forbidden and required destination and classifies the result as `blocked` (timeout or `ETIMEDOUT`), `reachable` (connect, refusal or reset), `unresolved` (`ENOTFOUND`, `EAI_AGAIN`) or `error` (any other code, which never matches an expectation). It prints one `egress.netprobe_check` line per check and an `egress.netprobe_result` summary. Exit codes: 0 when every non-informational check matches, 1 on any mismatch, 2 on a configuration error (stderr only). The two public-host checks use a TLS handshake with the host as the server name; a reset before the handshake counts as `blocked` (the firewall application-rule hypothesis). `PROBE_FQDN_PROTOCOL=tcp` degrades them to plain connects. `apps/egress/package.json` gains `"probe": "node --import tsx src/netprobe.ts"`.

## Change from the task: host-node checks are informational in every mode

The task (from the design's probe table) expected `wire-server-80`, `wire-server-32526` and `imds-80` to be `blocked` when the NSG mode is `deny-list-only` or `enforce`. Microsoft's documentation says an NSG cannot produce that:

- [Azure IP address 168.63.129.16 overview](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16) (ms.date 2025-07-25, updated 2026-03-12): "The virtual machine Agent requires outbound communication over ports 80/tcp and 32526/tcp with WireServer (168.63.129.16) ... The communication on these ports with 168.63.129.16 isn't subject to the configured network security groups."
- [Network security groups overview](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview), "Azure platform considerations" (ms.date 2025-07-15, updated 2025-10-23): DHCP, DNS, IMDS and health monitoring on 168.63.129.16 and 169.254.169.254 "aren't subject to the configured network security groups unless targeted by service tags specific to each service", naming `AzurePlatformDNS`, `AzurePlatformIMDS` and `AzurePlatformLKM`.

The EG-5 rule table denies these addresses by prefix (`deny-wire-server` at 200 on `168.63.129.16`, `deny-link-local` at 210 on `169.254.0.0/16`), not by service tag. On a real install the probe would therefore never see `blocked` for these three checks. Because the NSG default is `deny-list-only`, every default install would exit 1 and trip the failure alert that EG-9 wires. The three checks are now `informational` in every mode, like `apps-env-443`: they record what the replica sees, which is what the design wanted for SEC-7's open question. The application block list in `ssrf.ts` (`168.63.129.16/32` from EG-1, `169.254.0.0/16` already there) is the only control on these addresses. `netprobe.ts` carries a comment stating that, and the `buildChecks` matrix test and the mismatch test were updated (the mismatch test had assumed row 0 expected `blocked`; it now flips the first non-informational row).

Not changed here (recorded for later):

- **EG-5 rule table (iterate gate):** `deny-link-local` is marked `status: "known"` with the note "IMDS and link-local". It is known *not* to block IMDS. `deny-wire-server`'s note should say it has no effect on ports 80 and 32526. The documented way to deny IMDS is an `AzurePlatformIMDS` service-tag rule. Whether Container Apps workload-profile nodes on the subnet tolerate that rule is unverified, and blocking it could break managed identity, so no rule was added.
- **EG-11 (ADR-0005 statement):** WireServer on 80 and 32526 cannot be filtered by an NSG at all, so the application block list is its only control.

## Other recordings the task asked for

- **Wire-server ports:** confirmed as 80/tcp and 32526/tcp (first page above).
- **Apps-environment check:** the design expects `blocked`, but the apps environment is external (`internal: false`), so its static IP is a public load-balancer address and egress reaching it is an ordinary internet path. It is `informational`; the `kv-platform` and Blob endpoint checks cover lateral movement inside the VNet.
- **Event name:** the design names the line `netprobe`. The logging convention in `docs/design/logging.md` requires `<domain>.<verb>` with a registered domain, so the lines are `egress.netprobe_check` and `egress.netprobe_result`, registered in its "Currently in use" table. `docs/features/fetch-proxy.md` lists `netprobe.ts` with the egress files.
- **Local classification caveat for EG-10:** a target that answers with a refusal (for example an iptables `REJECT`, which sends ICMP port-unreachable and surfaces as `ECONNREFUSED`) classifies as `reachable`. The simulation's deny rules must `DROP` to produce `blocked`. ICMP admin-prohibited surfaces as `EHOSTUNREACH`, which is `error`.

## Evidence

- `netprobe.test.ts`, 43 tests: classify table (drop versus reset, unresolved, `EHOSTUNREACH` as `error`), `probeTcp` against real local sockets and fakes, `probeTls` fakes asserting `servername` equals the host, the `buildChecks` matrix over three NSG modes and both allow-list values, `parseConfig` errors, `main` exit codes 0, 1 and 2, informational mismatches not failing, and output hygiene (`DATABASE_URL=postgres://u:supersecret@db/x` in the env; no line contains `supersecret` or `://`).
- `./check-and-lint.sh`: 241 of 241 test files, 3486 tests (`eg8-gate.txt`). After the host-node change: `netprobe.test.ts` 43 of 43, typecheck, lint and format pass (same file).
- `just dev smoke --no-browser` in the dev container: 31 passed, 0 failed, 1 skipped (`eg8-smoke.txt`).
- Manual run in the dev container (`eg8-manual-run.txt`), loopback stand-ins: `node apps/egress/src/netprobe.ts` with no loader and NSG `off` exits 0 with 15 checks. `pnpm --filter @azx-pbc/egress probe` with NSG `enforce` exits 1 with 5 mismatches (the private-endpoint stand-ins and ports 25, 22 and 8443 answer on loopback). `PROBE_EXPECT_NSG=maybe` exits 2 with the message on stderr. A bare copy of the file in a directory with no `package.json` runs under Node 24 (type stripping, ESM detection).
- Imports: `grep -n "^import" apps/egress/src/netprobe.ts` shows only `node:dns/promises`, `node:net`, `node:tls`, `node:url`.

## Unverified in Azure

What a Container Apps replica sees for WireServer and IMDS, how a firewall application rule drops a denied connection (the TLS-handshake rule), and everything the probe will report on a real install. `just infra net-verify` (EG-9 and EG-10) exists for that.

## Executor

cursor-agent, `composer-2.5`. The coordinator changed the host-node expectations and the mismatch test after checking them against Azure's documentation.
