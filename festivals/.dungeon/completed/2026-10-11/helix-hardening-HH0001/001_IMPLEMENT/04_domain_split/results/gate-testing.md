# Testing gate: sequence 04 (domain split)

Run on `main` = `5c56761` (CT-4 to CT-10), inside the dev container, every command with `ulimit -c 0`. Logs are the `gate-testing-*` files in this folder.

| Check | Result |
| --- | --- |
| `./check-and-lint.sh`, run 1 | All steps passed, 242 of 242 test files. |
| `./check-and-lint.sh`, run 2 | All steps passed, 242 of 242 test files. |
| Adversarial telemetry suites with `OTEL_SDK_DISABLED=1` (`spanRedaction`, `traceBoundary`, egress `spanAttributes`, gateway `telemetry`) | 4 files, 50 tests passed (CT-8 added legacy-redirect cases). |
| `just infra build` | Passed. |
| `just dev smoke`, single-domain | 32 passed, 0 failed, 1 skipped (the browser group needs `HELIX_SMOKE_CHROME`). |
| `just dev smoke`, single-domain, real browser (Chromium 1248) | 37 passed, 0 failed, 0 skipped. |
| `just dev smoke`, split `HELIX_APPS_DOMAIN=helix-apps.localhost`, real browser | 47 passed, 0 failed, 0 skipped: cross-domain login, `Sec-Fetch-Site` (app → control `cross-site`), cookie scope, silent refresh, legacy 307. |
| `just dev smoke`, same-site pair `HELIX_APPS_DOMAIN=apps.local.helix.azxlabs.io`, real browser | 47 passed, 0 failed, 0 skipped (app → control `same-site`; the `Domain=<control>` cookie reaches `auth.<control>`, the expected negative control). |
| `just check lane`, single-domain | 10 passed. |
| `just check lane`, split | 10 passed. |
| Repository after all runs | Clean. |

New telemetry this sequence: `helix.edge.legacy_app_redirects` and the `helix.edge.legacy_app_redirect` span (CT-8). Both are asserted in `legacyRedirect.test.ts` and covered by the redaction and trace-boundary suites. Also the `boot.serving` log fields `controlDomain`, `split` and `legacyAppRedirect`.

## Unverified

- **In Azure:** the two-domain topology (two wildcard bindings on one Container App, the second certbot job, the two DNS zones, the two-binding TLS canary) and the environment pass-through.
- **In browsers:** Safari ITP, Firefox ETP and Chrome bounce-tracking on real domains, and a real Public Suffix List entry. Only Chromium was measured, locally.
