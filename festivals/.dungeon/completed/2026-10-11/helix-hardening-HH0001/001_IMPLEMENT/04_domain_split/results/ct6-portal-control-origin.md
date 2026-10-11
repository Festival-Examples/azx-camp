# CT-6 result: portal control origin

**Result: done.** `CONTROL_PUBLIC_BASE` (optional; unset or blank defaults to `APP_PUBLIC_BASE`, today's behavior) drives one thing: `connectionsCallbackUrl()` becomes `<scheme>//auth.<control host>/connections/callback`. Its three consumers pick it up through the function, unchanged: the code exchange's `redirectUri` in `connections/completion.ts`, the callback hint administrators register in `routes/providers.ts`, and the nonce redemption in `routes/connectionsPages.ts`. App URLs, `GET /api/v1/config` (`appPublicBase`), the catalogue's `appsHost` and the dashboard keep reading `APP_PUBLIC_BASE`. The SPA is untouched, and the config payload gains no control field.

**Boot validation** (`resolveControlPublicBase`, called from `assertDeploymentConfig`) mirrors the edge's `resolveControlDomain`, with parallel messages. It throws, naming the variable, when:
- the value is not a valid URL;
- the scheme or port differs from `APP_PUBLIC_BASE` (one edge listener);
- the control host is a subdomain of the apps host;
- the apps host is on or under `auth.`, `portal.` or `dev-api.` of the control host.

A parent control domain is allowed (the delegated case).

**The "derived, never configured" comment is replaced:** the control base is configured, it must agree with the edge's `EDGE_CONTROL_DOMAIN`, the two come from one Bicep parameter (CT-9), and a mismatch fails at the vendor's redirect-URI check.

**Mismatch, stated honestly.** The portal cannot see the edge's environment, so it cannot fail at boot when only one of `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE` is set. A callback URL on the wrong host fails closed: the vendor rejects the redirect URI, and the edge answers 404 for `auth.<apps>` (CT-5 Test 10). The operator check, that the `callbackUrl` in `GET /api/v1/providers` equals `https://auth.<EDGE_CONTROL_DOMAIN>/connections/callback`, is written in CT-10.

## Evidence (coordinator)

- **Tests:**
  - `deployment.test.ts`: the resolver's legacy, split, invalid, scheme or port mismatch, subdomain, delegated and reserved-label cases; the split callback URL with the app URL unchanged; and `assertDeploymentConfig`.
  - Route tests in split env: `config.test.ts` (`appPublicBase` on the apps host, no control host in the body), `apps.test.ts` (the created app's `url` on the apps host) and `providers.test.ts` (`callbackUrl` on `auth.<control>`).
- **Gate:** `./check-and-lint.sh`, 241 of 241 test files, 3648 tests.
- **Smoke:** the real-browser smoke ran twice, 37 of 37 both times. The agent's first-run SPA serve failure did not recur.
- **Lane:** connections lane, 10 of 10 (`ct6-gate.txt`).

## Unverified in Azure

An operator setting only one of the two variables, a real vendor's redirect-URI rejection, and the Bicep wiring (CT-9 and CT-10).

## Executor

cursor-agent, `composer-2.5`, 33 tool calls.
