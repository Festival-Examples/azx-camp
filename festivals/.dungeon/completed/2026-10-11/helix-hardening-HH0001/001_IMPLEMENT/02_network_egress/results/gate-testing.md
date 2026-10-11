# Testing gate: sequence 02 (network egress)

Run on `main` = `96e54b3` (all of EG-1 to EG-11). Dev-container commands ran with `ulimit -c 0`; the network simulation ran on the macOS host's Docker daemon (server 28.4.0, Ubuntu 24.04 VM, aarch64), since the dev container has no Docker socket. Logs are the `gate-testing-*` files in this folder.

| Check | Result |
| --- | --- |
| `./check-and-lint.sh`, run 1 | All steps passed, 241 of 241 test files, 3491 tests (1 skipped). |
| `./check-and-lint.sh`, run 2 | All steps passed, 241 of 241 test files. |
| Adversarial telemetry suites with `OTEL_SDK_DISABLED=1` (`spanRedaction`, `traceBoundary`, egress `spanAttributes`, gateway `telemetry`) | 4 files, 46 tests passed. |
| `just infra build` | Passed (`main.bicep`, both parameter files, the entra stack). |
| `just dev smoke` | 31 passed, 0 failed, 1 skipped (real-browser render needs `HELIX_SMOKE_CHROME`). |
| `just check lane` (connections browser lane) | 10 passed. |
| `just infra net-sim` (host) | All 7 scenarios PASS: `off`, `deny-list-only`, `enforce`, `deny-list-only-unpinned` exit 0; `break-kv`, `break-order`, `broken-closing-deny` exit 1 on their named check lines. |
| Repository after the gate | Clean. |

The translator tests (`node --test infra/netsim/translate.test.mjs`, 18 of 18) run inside `net-sim`'s static stage; they were also run per change in EG-10 and EG-11.

## Coverage by change

- EG-1 to EG-3: `ssrf.test.ts` boundary tables, `adversarial.test.ts`, and `ssrfRegistry.test.ts` run in the full gate.
- EG-4 to EG-7, EG-9: Bicep compile only (`just infra build`), plus `egressHosts.test.ts` and `egressHosts.integration.test.ts` for the drift tool.
- EG-8: `netprobe.test.ts` (43 tests, now with the pinned and dynamic matrices) in the full gate, and the real probe inside `net-sim`.
- EG-10: `net-sim` above.
- EG-11: docs build and format in the full gate.

No new spans or metrics in this sequence: the probe's telemetry is its log lines (`egress.netprobe_check` and `egress.netprobe_result`, registered in `docs/design/logging.md`), so there is no `startRecordingTelemetry` assertion to add. The adversarial suites still pass.

## Unverified in Azure

Everything the template declares but only Azure can prove:
- NSG attachment to a populated Container Apps subnet, the platform flows, the `100.64.0.0/10` deny, and the edge-to-egress source address.
- Replica behavior at `168.63.129.16` and `169.254.169.254`.
- Static private-endpoint addresses.
- Firewall runtime behavior: threat intelligence, SNI matching, rule-collection limits, the post-handshake drop.
- The diagnostic and console-log tables the alerts read, the `PT36H` window, and Count-below-1 on zero rows.
- The probe job's schedule and manual start, and `just infra net-verify` itself.

These are listed in `docs/features/network-controls.md` and the ADR-0005 probe-results table.
