# IT-10: separate provisioning from cutover; guards, probe, smoke and tests

Fixes from `review-04-domain-split.md`. Docs come in IT-11.

| Finding | Change |
| --- | --- |
| R-1 | `hostedAppsLive` (default false) and `hostedCutover = hostedSplit && hostedAppsLive`. Cutover expressions use `hostedCutover`: `appHostsDomain`, `splitEdgeEnv`, `splitPortalEnv`, `splitDevGatewayEnv`, and the control zone's `hostsWildcard`. Provisioning stays on `hostedSplit`: `dnsHosted`, `certbotHosted`, `declarativeHostedTls` and the second `customDomains` entry. With `hostedAppsDomain` set and `hostedAppsLive` false, the apps zone, the second certbot job and its binding exist while `EDGE_BASE_DOMAIN` and `APP_PUBLIC_BASE` stay on `appsDomain`. Before cutover the edge classifies apps-domain hosts as `platform`, so the binding is harmless. Both parameter files carry a commented `hostedAppsLive`. |
| S-1 | Availability target `edge-health-apps` → `https://www.<hostedAppsDomain>/health`, gated on `declarativeHostedTls`. `www` is reserved, so it is a platform host that answers `/health` before and after cutover. |
| S-2 | Output `hostedDnsNameServers` (empty without a split). |
| S-3 | `fail()` when the two certificate names collide. |
| G-1 | The domains are lowercased and trimmed (`appsDomainLc`, `hostedAppsDomainLc`). `fail()` for the control domain under the apps domain, and for the apps domain on or under `auth.`, `portal.` or `dev-api.` of the control domain (mirrors the edge's `resolveControlDomain`). |
| S-6, G-6 | Smoke `split` group: the control-host cookie check requires a captured `/health` request with `sec-fetch-site`. The login and silent-refresh landing checks require `/` or `/index*`, not `/_auth/complete`. `/_api/me` is recorded, not asserted (same-origin by construction). |
| G-2 | `legacyRedirect.test.ts` pins `/%2F_api/me` and `/%2f_auth/complete?token=x` as `refused_path` through `decideLegacyRedirect`. These pass the raw `/_` check and are refused only by the normalized first-segment check. |

**Wiring the coordinator checked.** The guards (`splitDomainValidation`) are evaluated through the edge's `EDGE_IMG_SRC_*` env expressions, the same pattern as `imgSrcFlagsValidation`. The chain's passing branch returns `true`, so the image flags are unchanged. A side effect: before cutover, `EDGE_BASE_DOMAIN` uses the lowercased, trimmed `appsDomain`. That is identical for any lowercase value, and the edge lowercases it anyway.

## Evidence (coordinator)

- **Bicep:** `az bicep build-params` with `hostedAppsDomain` set, `hostedAppsTlsBound = true`, and `hostedAppsLive` false or true: both compile. `just infra build` passes.
- **Gate:** `./check-and-lint.sh`, 242 of 242 test files, 3669 tests.
- **Smoke with a real browser:** single-domain 37 of 37; split 47 of 47, with the stricter control-host cookie check passing (control `cross-site`, no probe or session cookie).
- **Connections lane, split:** 10 of 10 (`it10-gate.txt`).
- **The agent's compile diff at defaults:** the only new parameter is `hostedAppsLive`. New variables and guards are added, the cutover expressions are re-texted with today's unset values, the availability list gains an entry that is empty when the gate is off, and there is a new output.

## Unverified in Azure

`fail()` firing at deploy, the staged provisioning on a live install, the new availability target, and the `www.<hosted>` probe before cutover.

## Executor

cursor-agent, `composer-2.5`, 60 tool calls.
