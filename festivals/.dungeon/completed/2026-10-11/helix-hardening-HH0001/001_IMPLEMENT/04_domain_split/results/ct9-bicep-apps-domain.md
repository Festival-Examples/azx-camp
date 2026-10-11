# CT-9 result: Bicep, DNS and certbot for the apps domain

**Result: done, compile-checked only (decision V4). Nothing is deployed.**

New parameters, all off by default, so existing `.bicepparam` files stay valid:
- `hostedAppsDomain` (default `''`, meaning the single-domain layout). When it is set, `appsDomain` becomes the control domain. The parameter description notes that the name reads backwards; CT-10 explains it.
- `hostedAppsTlsBound` (default `false`), the ADR-0044-style gate for the second wildcard binding.
- `legacyAppRedirect` (default `false`), which sets `EDGE_LEGACY_APP_REDIRECT` for CT-8 and keeps the control zone's `*` record while on. **This is a design gap:** the design's file list omits it, but its rollout notes set the edge variable through Bicep. The same kind of addition as `imgSrcExtra` and `imgSrcAllowAll`.

## With the parameters set

These are read from the compiled expressions. `build-params` with all three set compiles.
- **Edge:** `EDGE_BASE_DOMAIN = hostedAppsDomain`, `EDGE_CONTROL_DOMAIN = appsDomain`, and `EDGE_LEGACY_APP_REDIRECT`. The dev-gateway gets the same domains.
- **Portal:** `APP_PUBLIC_BASE = https://<hostedAppsDomain>` and `CONTROL_PUBLIC_BASE = https://<appsDomain>`. `DEV_API_PUBLIC_BASE` is unchanged.
- **Edge `customDomains`:** `*.<appsDomain>` with the control certificate and `*.<hostedAppsDomain>` with the apps certificate, each gated by its own flag. Each certificate name is computed once and passed to both its certbot instance and its binding (ADR-0044). The control name stays `wildcard-<appsDomain>`.
- **`dns.bicep`, two instances:**
  - The control zone keeps `auth`, `portal`, `dev-api` and `asuid`, plus `*` only while `legacyAppRedirect` is on or there is no split.
  - The apps zone has only `*` and `asuid` (`hostsControlPlane: false`).
- **Certbot, two instances** (the module is not edited). The second uses `namePrefix` `<prefix>-ap`, so its identity and job names do not collide; role-assignment names follow the identity. It runs on the cron `30 3 * * *` with empty portal and dev-gateway bind names, so it binds `*.<hostedAppsDomain>` on the edge only.
- **Split-only env:** `EDGE_CONTROL_DOMAIN`, `CONTROL_PUBLIC_BASE`, `EDGE_LEGACY_APP_REDIRECT` and the second `customDomains` entry are emitted only when the split is configured, so a single-domain install sees no environment or revision churn.
- **Unchanged on purpose:** the availability probe (`https://auth.${appsDomain}/health`), `apps/certbot/issue-and-bind.sh` and `infra/entra`.
- **Firewall installs:** EG-6's apps-subnet list already carries `management.azure.com`, the Entra login hosts and `acmeServerHost`, derived from the one `acmeServer` parameter both instances use. The second certbot job needs no new firewall rule.

## Unset means unchanged: the compile diff, `main` against the branch, `templateHash` stripped

| Category | Hunks |
| --- | --- |
| (a) new parameter with default | `hostedAppsDomain` (`''`), `hostedAppsTlsBound` (`false`), `legacyAppRedirect` (`false`) |
| (b) new variable | `hostedSplit`, `appHostsDomain`, `hostedCertName`, `hostedCertId`, `certbotEnabled`, `declarativeHostedTls`, `splitEdgeEnv`, `splitPortalEnv`, `splitDevGatewayEnv` |
| (c) condition true when unset | the DNS records gated by `hostsWildcard` and `hostsControlPlane` (both default `true`); the control `dns` module's `hostsWildcard: or(not(hostedSplit), legacyAppRedirect)` is `true` when unset |
| (d) new resource, gated false when unset | the `dnsHosted` and `certbotHosted` modules (condition `hostedSplit`) |
| (e) expression whose unset branch yields the old value | `EDGE_BASE_DOMAIN` and `APP_PUBLIC_BASE` use `appHostsDomain` (= `appsDomain` when unset); `customDomains` and env lists `concat` an empty second segment when the split and TLS flags are off |

The coordinator checked `declarativeTls` by reading both versions: `main` had `deployApps && deployCertbot && !empty(acmeEmail) && wildcardTlsBound`, and the branch has `certbotEnabled && wildcardTlsBound` with `certbotEnabled = deployApps && deployCertbot && !empty(acmeEmail)`. That is identical in every configuration.

## Evidence (coordinator)

- `just infra build` passes.
- `az bicep build-params` on a copy of `main.bicepparam` with all three split parameters set compiles. The copy was deleted.
- The gate passed in the agent's run; no code changed.
- No plan IDs in `infra/azure`.

## Unverified in Azure (for the CT-10 rollout notes)

- Two wildcard custom domains on one edge Container App.
- Issuing and binding the second certificate.
- Two certbot jobs binding the same edge app; the 30-minute offset is a precaution only.
- The ADR-0044 what-if with two bindings.
- Delegating both DNS zones, and a Public Suffix List entry for a delegated-subdomain pair.
- Empty versus omitted env vars on Container Apps.
- The job-name length limit with a long `namePrefix`: `<prefix>-ap-certbot` must stay within 32 characters.

A bad domain pair (the control domain under the apps domain) is refused by the edge at boot (CT-5), not by Bicep.

## Executor

cursor-agent, `composer-2.5`, 51 tool calls.
