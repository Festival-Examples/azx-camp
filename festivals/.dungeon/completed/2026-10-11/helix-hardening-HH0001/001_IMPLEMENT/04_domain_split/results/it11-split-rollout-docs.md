# IT-11: domain-split rollout notes and docs

Doc fixes from `review-04-domain-split.md`, written against the IT-10 template.

| Finding | Change |
| --- | --- |
| R-1 | `updates.md` Part 1 for an existing install is now four steps: (1) **provision** (`hostedAppsDomain` with `hostedAppsLive = false`, delegate from `hostedDnsNameServers`, firewall lists first, run the second certbot job, `hostedAppsTlsBound`, the `edge-health-apps` probe); (2) **verify** on a separate staging install with `hostedAppsLive = true`, because the edge moves all apps or none; (3) **cut over** (`hostedAppsLive` plus `legacyAppRedirect` in one apply); (4) **sunset**. A new install sets `hostedAppsLive = true` from the start. |
| R-2 | The containment section opens with a step 0 for all three parts: `imgSrcReportOnly = true` and `egressNsgEnforce = 'off'` before any edge roll or full apply. Part 3 follows step 0. Part 2 says "measurement mode". "Roll the apps" points at step 0. |
| S-4 | `authentication.md` states the boot rules the code enforces. `connection-providers.md` and the `consent.ts` comment say the callback comes from `CONTROL_PUBLIC_BASE`. The infra README qualifies the TLS-gate order as new-install only. The network step 0 wording is fixed. |
| S-5 | The operator check, `GET /api/v1/providers` `callbackUrl` equals `https://auth.<EDGE_CONTROL_DOMAIN>/connections/callback`, is added after cutover, in "After any update" and in `connection-providers.md`. |
| G-3 | One unverified-in-Azure sentence on binding `*.<control>` without a control `*` record. |
| G-4 | A rollback paragraph: setting `hostedAppsLive` false and applying reverts the variables; the zone and job stay; sessions on new hosts are lost; the 307 is `no-store`. |
| G-5 | `README.md`: recreate the dev container without `HELIX_APPS_DOMAIN` for single-domain smoke and the lane. |
| Parameters | `hostedAppsLive` and `hostedDnsNameServers` are documented in `configuration.md`, `getting-started.md` and the infra README. |

**Coordinator fixes:**
- Existing-install step 2 told operators to check that `www.<hostedAppsDomain>/health` "returns `tls=0`". There is no such field; it now says the host must answer over HTTPS with a valid certificate.
- New-install step 1 said to "create and delegate both zones" before the deploy that creates them. It now delegates each zone from the `dnsNameServers` and `hostedDnsNameServers` outputs after step 2.

## Evidence (coordinator)

- `./check-and-lint.sh` twice, both 242 of 242 test files, 3669 tests (docs build and format included).
- The agent saw `apps/edge/src/gateway/usage.rls.integration.test.ts` fail once (a `prodAfterDev` assertion), which is not a known flaky test. Three isolated reruns and two full gates passed. This is recorded as a rare flake (`it11-gate.txt`).
- The agent's runs: single-domain smoke 37 of 37 with Chromium; lane 10 of 10.

## Executor

cursor-agent, `composer-2.5`, 50 tool calls. Coordinator fixes as listed.
