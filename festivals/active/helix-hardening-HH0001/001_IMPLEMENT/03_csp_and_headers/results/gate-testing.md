# Testing gate: sequence 03 (CSP and headers)

Run on `main` = `19f4ca7` (CT-1 to CT-3), inside the dev container, every command with `ulimit -c 0`. Logs are the `gate-testing-*` files in this folder.

| Check | Result |
| --- | --- |
| `./check-and-lint.sh`, run 1 | All steps passed, 241 of 241 test files. |
| `./check-and-lint.sh`, run 2 | All steps passed, 241 of 241 test files. |
| Adversarial telemetry suites with `OTEL_SDK_DISABLED=1` (`spanRedaction`, `traceBoundary`, egress `spanAttributes`, gateway `telemetry`) | 4 files, 48 tests passed (up from 46: CT-2 added two `/_csp-report` cases). |
| `just infra build` | Passed (`imgSrcExtra`, `imgSrcReportOnly`, `imgSrcAllowAll`). |
| `just dev smoke` | 32 passed, 0 failed, 1 skipped (the browser group needs `HELIX_SMOKE_CHROME`). |
| `just dev smoke` with `HELIX_SMOKE_CHROME` (Chromium 1248, real browser) | 37 passed, 0 failed, 0 skipped. The enforced CSP blocks the remote image and records the violation (`disposition="enforce"`), the `data:` image loads, and a granted origin appears in the header. |
| `just check lane` (connections browser lane, consent popup journeys) | 10 passed. |
| Repository after the gate | Clean. |

New telemetry: `helix.edge.csp_reports` (CT-2), asserted with `startRecordingTelemetry` in `cspReport.test.ts` and covered by the `/_csp-report` cases in `spanRedaction.test.ts` and `traceBoundary.test.ts`.

## Unverified

- **In Azure:** that Container Apps passes `EDGE_IMG_SRC_EXTRA`, `EDGE_IMG_SRC_REPORT_ONLY` and `EDGE_IMG_SRC_ALLOW_ALL` through as set, and the image-policy rollout on a live install.
- **Untested anywhere:** WebRTC ICE and DNS prefetch or preconnect under the policy, and Firefox and Safari image blocking and report delivery.
