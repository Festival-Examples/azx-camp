# PR #3 review fix (obey-agent, changes requested)

One bug was reported on pull request #3 (network egress controls). It was confirmed against the code before fixing.

## Finding: a green probe did not prove the NSG

**Confirmed.** In the default configuration (`deny-list-only`, unpinned private endpoints) every scored check expected `reachable`, so `ok: true` and a zero exit from `just infra net-verify` said nothing about whether the NSG was attached. Two earlier changes in this sequence produced that: the host-node checks became informational (Azure exempts them), and unpinned installs dropped the endpoint checks. In `enforce` without pinning, the only scored denies were ports 25, 22 and 8443 on `mcr.microsoft.com`. Those ports time out from any client, and the firewall drops them first when deployed.

## Fix

- **`denyProven` in the summary line.** It is true only when the NSG expectation is not `off` and a scored `blocked` check against an in-VNet target ran and matched. That target is the pinned Blob endpoint (`blob-pe-443`): `deny-vnet` drops it, it travels the VNet system route and not the firewall route, and it accepts a handshake when no NSG is in the way. `ok` and the exit codes are unchanged, so the scheduled job and its alerts do not start failing on default installs.
- **The port checks on the allowed host are informational in every mode.** They cannot discriminate.
- **An optional target that can prove the closing deny.** `PROBE_CLOSING_DENY_TARGET` (`host:port`; Bicep `netprobeClosingDenyTarget`, default empty) adds a `closing-deny` check. It is scored `blocked` only under `enforce` with the firewall off, and informational otherwise. The summary carries `closingDenyProven`.
- **`just infra net-verify`:**
  - exits 1 when `ok` is not true;
  - exits **3** when the NSG is on and `denyProven` is not true, with a message telling the operator to pin the private-endpoint addresses;
  - warns when `enforce` is on and the closing deny was not proven.

  It parses the result line with `infra/azure/scripts/parse-netprobe-log.mjs`.
- **`netControls.probe.denyProvable`:** true when the NSG mode is not `off` and endpoints are pinned.
- **Simulation:**
  - `PROBE_CLOSING_DENY_TARGET` is set, so `broken-closing-deny` fails on `closing-deny`.
  - The runner asserts `denyProven` per scenario.
  - A new negative scenario `nsg-detached` applies no rules while the probe expects a pinned `deny-list-only` install, and requires exit 1 with `blob-pe-443` `reachable`.
- **Docs:** the feature page, the README, the network section of `updates.md`, the ADR-0005 amendment, the `PROBE_*` table, the logging table, `configuration.md` and the alert descriptions say what a green probe proves and does not prove.

## What this cannot fix, stated plainly

On an unpinned install there is no in-VNet target the NSG must block: the fallback row allows the whole endpoint subnet, and the template does not know the endpoint addresses. The probe therefore reports `denyProven: false` there, and `net-verify` exits 3. Proving the NSG requires pinning, which the rollout notes already place before the NSG step. Feeding the endpoints' assigned addresses into the NSG at deploy time would make unpinned installs provable too. That is a larger template change with no way to verify it here, so it is left as a follow-up.

## Also on this branch: the merge of the PR #2 fix (`955af5e`)

Merging `hardening/01-spend-controls` produced two textual conflicts (`apps/egress/src/proxy.ts`, `updates.md`) and one silent hazard. The PR #2 fix added a second egress dispatcher for LLM calls. It was written before this sequence added `EGRESS_EXTRA_BLOCKED_CIDRS` to the validating connector, so the merged LLM dispatcher would have skipped the extra block list. It now carries it, and `adversarial.test.ts` has a test that fails without it (checked by mutation).

## Evidence (coordinator)

- `./check-and-lint.sh`: 242 of 242 test files, 3526 tests. `just infra build` passes. Translator tests: 21 of 21.
- `just infra net-sim` on the host: 8 of 8 scenarios PASS, including `nsg-detached` (exit 1) and `broken-closing-deny` (exit 1).
- Real-browser smoke: 34 of 34. `just --dry-run infra net-verify rg-test` renders.
- The recipe's decision logic, replayed on sample logs for seven cases: the default unpinned install exits 3; pinned and proven exits 0; a mismatch exits 1 (`pr3-review-fixes-gate.txt`).
- The merge commit's first gate run hit the known timing flake `apps/portal/src/deploy/diagnose.test.ts` under host load (load average about 19). It passed 3 of 3 alone, and the full gate passed on rerun.

## Unverified in Azure

`net-verify` end to end, the job's log shape, and that the pinned Blob endpoint completes a handshake from the egress subnet when no NSG is attached.

## Executor

cursor-agent, `composer-2.5`. The coordinator did the merge resolution and the dispatcher fix.
