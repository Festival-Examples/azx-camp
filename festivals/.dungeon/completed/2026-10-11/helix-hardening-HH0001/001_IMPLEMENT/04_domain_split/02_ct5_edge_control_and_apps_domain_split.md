---
fest_type: task
fest_id: 02_ct5_edge_control_and_apps_domain_split.md
fest_name: ct5 edge control and apps domain split
fest_parent: 04_domain_split
fest_order: 2
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.357999-06:00
fest_updated: 2026-10-10T07:48:26.799438-06:00
fest_tracking: true
---


# Task: ct5 edge control and apps domain split

## Objective

Teach the edge a separate control domain (`EDGE_CONTROL_DOMAIN`) so the auth host can live on one registrable domain and hosted apps on another, while an install that sets nothing behaves exactly as today, and ship the adversarial tests and a dedicated review pass that this OIDC-handoff change requires. Implements CT-5 from 02-app-containment.md.

## Requirements

This is the most security-sensitive change in the festival. `projects/helix/AGENTS.md:97` says the OIDC handoff "is the most security-sensitive code in the platform and gets a dedicated review pass", and that anything touching it ships adversarial tests with it. Both are Done-When items, not follow-ups.

Behavior:

- [ ] **Unset means today.** With `EDGE_CONTROL_DOMAIN` unset, blank, or equal to `EDGE_BASE_DOMAIN`, every existing edge test passes with its assertions unchanged. The only edits to existing tests are listed under Tests: two `publicOrigin(..., "auth")` assertions move to `controlOrigin`, the full-config fixtures gain `controlDomain`, and the handoff suite is wrapped so it runs in both layouts.
- [ ] **Split semantics.** With the two domains different: `auth.<controlDomain>` is the only auth host; `auth.<baseDomain>`, `portal.<baseDomain>`, `www.<baseDomain>` and `api.<baseDomain>` classify as `platform` (never `auth`); `<slug>.<baseDomain>` is an app; `/_auth/complete` redirects land on the apps origin and `/start` redirects use the control origin.
- [ ] **Classification order.** `classifyHost(host, baseDomain, controlDomain = baseDomain)` checks the apps suffix first, then the exact host `auth.<controlDomain>`, else `platform`. The order matters when the control domain is a parent of the apps domain (see the three examples in step 3).
- [ ] **One helper for control origins.** `controlOrigin(config, "auth" | "portal" | "dev-api")` builds `<scheme>://<label>.<controlDomain>[:port]`. `publicOrigin(config, label)` throws when `label` is in `RESERVED_SUBDOMAINS` (`auth`, `portal`, `api`, `www`), so a call site that was not migrated fails at its first call, in tests, and cannot emit `auth.<appsDomain>` in production. `dev-api` is not in `RESERVED_SUBDOMAINS` today (see Design notes); do not add it here.
- [ ] **All nine auth-host call sites move to `controlOrigin`** (the design says eight; there are nine): `server.ts:131`, `auth/gate.ts:181`, `auth/routes/authHost.ts:153` and `:163`, `auth/routes/passwordLogin.ts:61`, `routing/consentStart.ts:320`, `devGateway/consentStart.ts:170` and `:211`, `serving/assets.ts:203` (only its `"auth"` half). App-origin call sites stay on `publicOrigin`: `auth/gate.ts:204`, `auth/validate.ts:88`, `auth/routes/authHost.ts:204`, `routing/consentStart.ts:246`, `serving/assets.ts:203` (its `slug` half).
- [ ] **Boot validation fails closed** (in `loadGatewayConfig`, so the dev-gateway gets it too):
  - unset, blank, or equal to the base domain: legacy single-domain mode, no error;
  - not a valid hostname (scheme, port, path, spaces, one label, leading or trailing dot, underscore): throw naming `EDGE_CONTROL_DOMAIN`;
  - equal to a subdomain of the base domain (for example base `apps.example.test`, control `ctl.apps.example.test`): throw. An app could set a `Domain=` cookie that reaches control hosts;
  - a parent of the base domain (base `apps.helix.customer.test`, control `helix.customer.test`): allowed, because ADR-0028 decision 2 describes this delegated-subdomain case. It is only a separate site if the customer lists the apps zone on the Public Suffix List, which the edge cannot check without a new dependency; the edge logs the split and docs state the requirement (CT-10).
- [ ] **Telemetry and logs.** Both `boot.serving` log events (`server.ts:311-318` and `devGateway/server.ts:207-215`) gain `controlDomain` and `split` (a log field, not a span attribute). No new metric. `apps/edge/src/auth/gateTelemetry.test.ts` is extended to prove the denial counter still uses only its bounded reasons in split mode.
- [ ] Depends on: `01_ct4_second_loopback_dev_domain.md` (the dev domains the browser tests use in CT-7; this task's own tests set `Host` headers and need no DNS). CT-3 has landed, so `EdgeConfig` already carries the CSP fields; re-open the fixtures before editing.

Failure paths from the design:

- [ ] Bad domain pair: the edge does not start; the error names the variable and the rule.
- [ ] `EDGE_CONTROL_DOMAIN` unset or blank: legacy layout. The direction of failure is "no containment gain", never "broken login".
- [ ] A request whose `Host` is `auth.<baseDomain>` in split mode never reaches an auth handler and never sets a cookie; it gets the same 404 any platform host gets.
- [ ] Edge and portal disagree on the control domain (CT-6 covers the portal half): the vendor callback URL the portal publishes points at a host the edge answers with 404, so the OAuth callback fails at the vendor and nothing leaks. The edge half of that evidence is in this task (test 10).

Design notes (where the design and the code disagree; record each in `results/` and follow the code):

1. The design says "eight" auth-host call sites; the code has nine (above).
2. The design says the pinned property is "`auth.<appsDomain>`, `portal.<appsDomain>` and `dev-api.<appsDomain>` classify as `platform`". `dev-api` is not reserved (`apps/edge/src/routing/hosts.ts:17` lists `auth`, `portal`, `api`, `www`), so `dev-api.<appsDomain>` classifies as an **app** with slug `dev-api`. That is harmless: the dev-gateway is a separate process on `dev-api.<controlDomain>`, and the edge's `classifyHost` never treats that host as an app because it ends in the control suffix. Pin the real property: `auth.<appsDomain>` is never `auth`.
3. The design puts the concurrent-redeem race in `flow.integration.test.ts`. The store-level race is already in `auth/sessions.integration.test.ts:101` (host-agnostic). This task adds the HTTP-level race to `flow.integration.test.ts`.
4. The design says existing tests pass unmodified in single-domain mode, but `config.test.ts:653` and `:666` assert `publicOrigin(..., "auth")`. Once `publicOrigin` refuses reserved labels those two lines must call `controlOrigin`.

## Implementation

Line numbers are at commit 792557a of `projects/helix`. CT-2 and CT-3 add fields to `EdgeConfig`, `config.ts` and the fixtures, and shift them; search for the named symbol and re-read the file before each edit.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-5-control-apps-domain-split`.

2. Read first, all of it: `apps/edge/src/routing/hosts.ts`; `config.ts:105-125` (`GatewayConfig`), `:723-780` (`loadGatewayConfig`; `baseDomain` is read at `:745`), `:888-902` (`publicOrigin`); `app.ts:150` (`hostClass` on the request), `:368-373` (the one place hosts are classified), `:440-495` (`/start`, `/callback`, `/connections/*`: they answer on `kind === "auth"` only); `auth/validate.ts:30-50` (`validateReturnPath`), `:79-89` (`isSameOrigin`), `:105-190` (Fetch Metadata and the `/_api` origin check); `auth/routes/authHost.ts` (all); `auth/cookies.ts`; and the whole of `auth/adversarial.test.ts` (it keys everything off the module constant `AUTH_HOST` and `buildAuthEdge()`).

3. `routing/hosts.ts`. Change the signature and the body. Keep the doc comment's two-router discipline paragraph and add the split rule.

   ```ts
   export function classifyHost(
     hostHeader: string | undefined,
     baseDomain: string,
     controlDomain: string = baseDomain,
   ): HostClass {
     if (!hostHeader || hostHeader.includes("[")) return { kind: "platform" };
     const colon = hostHeader.indexOf(":");
     const host = (colon === -1 ? hostHeader : hostHeader.slice(0, colon)).toLowerCase();

     const suffix = `.${baseDomain}`;
     if (host.endsWith(suffix)) {
       const label = host.slice(0, -suffix.length);
       // Legacy layout: the auth host shares the apps suffix (today's behavior).
       if (label === "auth" && controlDomain === baseDomain) return { kind: "auth" };
       // Split layout: `auth` here is reserved, so it falls to platform, never auth.
       if (label.includes(".") || !SLUG_PATTERN.test(label) || RESERVED_SUBDOMAINS.has(label)) {
         return { kind: "platform" };
       }
       return { kind: "app", slug: label };
     }
     if (host === `auth.${controlDomain}`) return { kind: "auth" };
     return { kind: "platform" };
   }
   ```

   Three layouts to hold in your head (and to pin in `hosts.test.ts`): identical domains (legacy); control and apps on different registrable domains (`local.helix.azxlabs.io` and `helix-apps.localhost`); control a parent of apps (`helix.customer.test` and `apps.helix.customer.test`: `auth.apps.helix.customer.test` ends in the apps suffix, label `auth` is reserved, so `platform`; `auth.helix.customer.test` is auth). Keep `RESERVED_SUBDOMAINS` exported and unchanged.

4. `config.ts`.
   - Add the field to `GatewayConfig` (`:115-116`) with a comment: the domain whose `auth.` host runs the OIDC flow; equals `baseDomain` unless split.
     ```ts
     /** Control hosts (`auth.`, `portal.`, `dev-api.`) live on this domain. Equal to `baseDomain` in the single-domain layout. */
     controlDomain: string;
     ```
   - In `loadGatewayConfig` (`:745`), compute the base once and validate the pair before returning:
     ```ts
     const baseDomain = (env.EDGE_BASE_DOMAIN ?? "local.helix.azxlabs.io").toLowerCase();
     const controlDomain = resolveControlDomain(baseDomain, env.EDGE_CONTROL_DOMAIN);
     ```
     and return both fields. Add `resolveControlDomain` above it:
     ```ts
     const HOSTNAME = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

     export function resolveControlDomain(baseDomain: string, raw: string | undefined): string {
       const control = raw?.trim().toLowerCase();
       if (!control || control === baseDomain) return baseDomain; // today's layout
       for (const [name, value] of [["EDGE_CONTROL_DOMAIN", control], ["EDGE_BASE_DOMAIN", baseDomain]] as const) {
         if (!HOSTNAME.test(value)) throw new Error(`${name} is not a valid hostname: ${value}`);
       }
       if (control.endsWith(`.${baseDomain}`)) {
         throw new Error(
           `EDGE_CONTROL_DOMAIN (${control}) must not be a subdomain of EDGE_BASE_DOMAIN (${baseDomain}): ` +
             "an app could set a Domain= cookie that reaches the control hosts. Refusing to start.",
         );
       }
       return control;
     }
     ```
     Do not validate `baseDomain` in the legacy branch; today's installs may not match this pattern and must not start failing.
   - `publicOrigin` (`:897-902`): add the guard, and add `controlOrigin` next to it. Importing `RESERVED_SUBDOMAINS` from `./routing/hosts.js` is cycle-free: `hosts.ts` imports only `@azx-pbc/shared`.
     ```ts
     export function publicOrigin(config: GatewayConfig, hostLabelOrNull: string | null): string {
       if (hostLabelOrNull !== null && RESERVED_SUBDOMAINS.has(hostLabelOrNull)) {
         throw new Error(`publicOrigin() builds app origins; "${hostLabelOrNull}" is a control host, use controlOrigin()`);
       }
       const host = hostLabelOrNull ? `${hostLabelOrNull}.${config.baseDomain}` : config.baseDomain;
       return originFor(config, host);
     }

     export type ControlLabel = "auth" | "portal" | "dev-api";
     export function controlOrigin(config: GatewayConfig, label: ControlLabel): string {
       return originFor(config, `${label}.${config.controlDomain}`);
     }

     function originFor(config: GatewayConfig, host: string): string {
       // HTTPS-only: omit the port only when it is the https default (443).
       const port = config.publicPort === 443 ? "" : `:${config.publicPort}`;
       return `${config.publicScheme}://${host}${port}`;
     }
     ```
     Update the doc comment above `publicOrigin` (`:888-896`) to say it is the app-origin builder and why it refuses control labels.

5. `app.ts:372`: `req.hostClass = classifyHost(req.headers.host, config.baseDomain, config.controlDomain);`.

6. Migrate the nine call sites (import `controlOrigin` beside or instead of `publicOrigin`; drop the `publicOrigin` import where it is no longer used, because lint flags unused imports):

   | File:line | Today | Change |
   |---|---|---|
   | `server.ts:131` | `` `${publicOrigin(config, "auth")}/callback` `` | `controlOrigin(config, "auth")` |
   | `auth/gate.ts:181` | `new URL(`${publicOrigin(deps.config, "auth")}/start`)` | `controlOrigin(deps.config, "auth")`; `:204` stays `publicOrigin(deps.config, entry.slug)` |
   | `auth/routes/authHost.ts:153` | `publicOrigin(rt.config, "auth")` (callback URL for the code exchange) | `controlOrigin(rt.config, "auth")` |
   | `auth/routes/authHost.ts:163` | silent-refresh restart `/start` | `controlOrigin(rt.config, "auth")`; `:204` stays `publicOrigin(rt.config, entry.slug)` |
   | `auth/routes/passwordLogin.ts:61` | `ssoStartUrl` | `controlOrigin(rt.config, "auth")` |
   | `routing/consentStart.ts:320` | vendor `callbackUrl` | `controlOrigin(rt.config, "auth")`; `:246` stays `publicOrigin(rt.config, slug)` |
   | `devGateway/consentStart.ts:170` | vendor `callbackUrl` | `controlOrigin(rt.config, "auth")` |
   | `devGateway/consentStart.ts:211` | popup URL base | `controlOrigin(rt.config, "auth")` |
   | `serving/assets.ts:203` | `platformOrigins: [publicOrigin(config, slug), publicOrigin(config, "auth")]` | `[publicOrigin(config, slug), controlOrigin(config, "auth")]` |

   After editing, `grep -rn "publicOrigin(" apps/edge/src --include='*.ts' | grep -v test` must show only app-origin uses: `gate.ts:204`, `validate.ts:88`, `authHost.ts:204`, `consentStart.ts:246`, `assets.ts:203`.

7. Logs. In `server.ts:311-318` and `devGateway/server.ts:207-215` add `controlDomain: config.controlDomain, split: config.controlDomain !== config.baseDomain` to the `boot.serving` object, next to `baseDomain`.

8. Fixtures. `controlDomain` is a required field, so every full config literal needs it: `test/config.ts` (`testEdgeConfig` at `:59`, `testDevGatewayConfig` at `:115`), `app.test.ts:14` and `serving/cspReport.test.ts:12` (`controlDomain: "local.helix.azxlabs.io"` beside `baseDomain`). `apps/connections-lane/src/world.ts` and `routing/connectionsJourney.integration.test.ts` build through `testEdgeConfig`, so they need nothing. `pnpm typecheck` lists any literal you miss. Add the split fixtures to `test/config.ts`:
   ```ts
   export const SPLIT_CONTROL_DOMAIN = "local.helix.azxlabs.io";
   export const SPLIT_APPS_DOMAIN = "helix-apps.localhost";
   export function splitEdgeConfig(overrides: Partial<EdgeConfig> = {}): EdgeConfig {
     return testEdgeConfig({ baseDomain: SPLIT_APPS_DOMAIN, controlDomain: SPLIT_CONTROL_DOMAIN, ...overrides });
   }
   export function splitDevGatewayConfig(overrides: Partial<DevGatewayConfig> = {}): DevGatewayConfig {
     return testDevGatewayConfig({ baseDomain: SPLIT_APPS_DOMAIN, controlDomain: SPLIT_CONTROL_DOMAIN, ...overrides });
   }
   ```
   The two domains have different registrable domains, which is the point of the layout; the tests need no DNS because they send `Host` headers.

9. Tests. Each item below is one of the design's ten named adversarial tests, with the file and what it asserts. Hosts below are written `auth.<control>` and `app.<apps>`; build them from the config, not from string literals, so a future change of the constants cannot leave a test asserting nothing.

   **Test 1, auth-host impersonation.**
   - `routing/hosts.test.ts`, new `describe("split layout")` using `classifyHost(host, APPS, CONTROL)`: `auth.<control>` is `auth`; `auth.<apps>` is `platform`; `portal.<apps>`, `www.<apps>` and `api.<apps>` are `platform`; `demo.<apps>` is `app` with slug `demo`; `demo.<control>` is `platform` (until CT-8); the bare apps and control domains are `platform`; `dev-api.<apps>` is `app` with slug `dev-api` (design note 2). Also run the three layouts from step 3 and the existing legacy cases with the third argument omitted (they already exist at `hosts.test.ts:8-65` and must pass untouched).
   - `auth/adversarial.test.ts`, split layout: `GET /start?app=appa`, `GET /callback?code=x&state=y`, `GET /connections/callback`, `GET /connections/consent/start` with `Host: auth.<apps>` and again with `portal.<apps>` return 404; the response has no `set-cookie`; `edge.oidc.authorizeRequests` stays empty; the portal provider fake records no call.

   **Test 2, lookalike hosts.** `routing/hosts.test.ts`, a table against `(APPS, CONTROL)`: `xauth.<control>`, `a.auth.<control>`, `auth.<control>.evil.example`, `auth.<control>.` (trailing dot), `evil.example:@auth.<control>` (userinfo shape: the colon cuts it to `evil.example`), `evil.example@app.<apps>` (label contains a dot after the cut), an absent Host, `[::1]:8080`, an empty string: all `platform`. And three that stay `auth` as they do today, so the behavior is pinned rather than assumed: `AUTH.<CONTROL>` (case folded), `auth.<control>:8443`, `auth.<control>:` . Then at request level in `auth/adversarial.test.ts` (split layout) send `/start?app=appa` with each of the platform shapes and assert 404 and no cookie.

   **Test 3, cross-domain handoff replay, audience confusion, fixation.**
   - Wrap the existing blocks "attack: handoff replay" (`:260`), "attack: audience confusion" (`:275`) and "attack: session fixation at /_auth/complete" (`:396`) so they run in both layouts (refactor sketch in step 10). Their bodies assert: the second redemption gets 403 and no cookie; a JWS-valid token minted for app B cannot redeem app A's row; attacker-preset cookies do not survive redemption.
   - New in the split layout: the completion URL returned by `/callback` has host `appa.<apps>:8080` (never `*.<control>`); redeeming that same token at `appa.<control>` (a host that is `platform` in this task) returns 404 and does **not** burn the token, and a following redemption at the right host succeeds exactly once.

   **Test 4, cookie scope across domains.** `auth/adversarial.test.ts`, split layout:
   - a `__Host-session` minted by redeeming on `appa.<apps>` sent to `appb.<apps>` gets the 302/401 the gate gives a stranger, never 200 (pattern: `auth/gate.test.ts:157`);
   - the same cookie sent to `auth.<control>` for `/_api/me` and for `/connections/anything` gets 404 and the body carries no identity;
   - the `__Host-oidc-flow` cookie sent to `appa.<apps>/callback` does not run the callback (the app host serves an asset or 404) and does not consume the flow;
   - every `set-cookie` issued across the whole login (start, callback, complete) starts with `__Host-`, has `Secure` and `Path=/`, and has no `Domain=`.
   - The browser leg ("an app response setting `Domain=<appsDomain>` or `Domain=<controlDomain>` never produces a cookie the control hosts receive") is CT-7.

   **Test 5, Origin and Fetch Metadata.** `auth/adversarial.test.ts`, in the gateway block that starts at `:501` (the sibling-subdomain case is at `:571`). Extend the `call` helper to take `secFetchSite`. Against `appa.<apps>`, `POST /_api/llm/chat` with a valid session is refused with 403 and `edge.provider.calls` stays empty for each of: `Origin: https://auth.<control>:8080`; `Origin: https://appb.<apps>:8080`; `Origin: https://appa.<control>:8080` (the old host); `Origin: null`; no Origin; and, with the correct `Origin`, each of `Sec-Fetch-Site: cross-site`, `same-site`, `none`. With the correct `Origin` and `same-origin` the call is allowed (a control that always refuses proves nothing). Also add the split cases to `auth/validate.test.ts` for `isSameOrigin` and `makeSameOriginCheck`.

   **Test 6, open redirect.** `auth/adversarial.test.ts`, extend "attack: open redirect via /start" (`:307`) in both layouts with: `//auth.<control>/x`, `https://<apps>/`, `/\<apps>`, `/%0d%0aSet-Cookie:x=1` and a tab-separated `/\t/evil.example` — all 400 with the IdP never contacted. Extend `auth/validate.test.ts:5` (the corpus) with the same strings. Add one positive check in the split layout: after a full login with `rd=/page?x=1`, the final `Location` the app host sends is path-only, and the `/_auth/complete` URL's origin equals `publicOrigin(config, "appa")` (config-derived, not request-derived).

   **Test 7, unmigrated call site.** `config.test.ts`, in `describe("publicOrigin")` (`:642`): for each label in `RESERVED_SUBDOMAINS`, `publicOrigin(cfg, label)` throws in both layouts; `controlOrigin(cfg, "auth")` equals `https://auth.<control>:8080` for the dev config and `https://auth.azx.helix.azxlabs.io` for the production config in the existing test; `publicOrigin(cfg, "demo")` is the apps origin. Move the existing assertions at `:653` and `:666` to `controlOrigin`; keep `:654` and `:667` as they are.

   **Test 8, boot validation.** `config.test.ts`, through `loadConfig` with the `ENV` shape used at `:643-649`: unset, blank and `"  "` give `controlDomain === baseDomain`; identical values give the same; `ctl.<base>` throws /subdomain/; `http://x.test`, `x.test:8443`, `x`, `.x.test`, `x_y.test` throw /valid hostname/; the parent-of-apps pair loads, and its config makes `classifyHost` treat `auth.<parent>` as auth; uppercase input is lowercased. The same through `loadDevGatewayConfig`.

   **Test 9, concurrent redeem race and `prompt=none` against the real dev IdP.** `auth/flow.integration.test.ts` builds one app in `beforeAll` (`:112-171`) with `REDIRECT_URI` fixed to the single-domain auth host (`:28`). Add a second instance for the split layout: start the IdP with both redirect URIs (`startDevIdp({ edgeRedirectUris: [REDIRECT_URI, SPLIT_REDIRECT_URI] })`, where the second is `https://auth.<control>:8080/callback`), build a second `OpenIdConnectClient` with that URI and a second `buildApp({ config: splitEdgeConfig({ auth, allowUnauthenticated: false }), ... })` sharing the pool, session store, registry and blob. Make `loginAs` take `{ app, authHost }` with the current values as defaults so existing callers do not change. New `describe("split layout")` cases: login lands on `rd` through `auth.<control>` then `app.<apps>`; replay gets 403; the silent refresh case (copy the one at `:291`) shows the gate's redirect has host `auth.<control>` and `silent=1`, and the callback completes on `app.<apps>`; and the HTTP-level race: fire eight `app.inject` calls for the same `/_auth/complete` URL with `Promise.all` and assert exactly one response sets `__Host-session` and the other seven are 403 with no cookie.

   **Test 10, edge and portal disagreement (edge half).** `routing/connectionsProxy.test.ts` (the proxy describe starts at `:136`; hosts are constants at `:38-39`): in the split layout `GET /connections/callback?...` on `auth.<apps>` returns 404 and the portal provider fake is never called, while the same request on `auth.<control>` is proxied. That is the "fails closed at the vendor" evidence: a callback URL registered on the wrong host never reaches the portal. The portal half is CT-6.

   **Other files.**
   - `auth/gate.test.ts`: new split describe (hosts from `splitEdgeConfig`): an unauthenticated navigation's `Location` has origin `https://auth.<control>:8080` and path `/start`, and the password-app redirect goes to `https://<slug>.<apps>:8080/_auth/login` (existing pattern at `:85-100`, `:283-290`, `:310`).
   - `auth/gateTelemetry.test.ts`: run the existing "uses only reasons from the declared set" case (`:30`) against a split config.
   - `auth/handoff.test.ts` and `auth/flow.test.ts`: read them; they test tokens and have no host input, so they do not change. Say so in `results/` instead of adding a case.
   - `routing/consentStart.test.ts` (`CALLBACK_URL` at `:51`, assertions at `:272-274`) and `devGateway/consentStart.test.ts` (`AUTH_ORIGIN` at `:37`, `:182-183`): add split cases asserting the consult request's `callbackUrl` is `https://auth.<control>:8080/connections/callback` and `openerOrigin` is the app's apps-domain origin; the dev-gateway popup URL is on `auth.<control>`.
   - `routing/connectionsJourney.integration.test.ts` (`describe` at `:903`): extend one journey so the consent completes with the opener on the apps domain and the callback on the control domain. Read its harness first; if giving it a second config is more than a few lines, assert the two origins at the consult call and leave the full browser journey to CT-7's lane run, and say so in `results/`.
   - `serving/connectHelper.test.ts`: `platformOrigins` now carries the control origin; add the split case.

10. Refactor sketch for `auth/adversarial.test.ts` (it is a 600-line file keyed on module constants). Keep every test body; change only where hosts come from.
    ```ts
    const LAYOUTS = [
      { name: "single", config: testEdgeConfig, control: "local.helix.azxlabs.io", apps: "local.helix.azxlabs.io" },
      { name: "split", config: splitEdgeConfig, control: SPLIT_CONTROL_DOMAIN, apps: SPLIT_APPS_DOMAIN },
    ] as const;
    type Layout = (typeof LAYOUTS)[number];

    interface AuthEdge { /* existing fields */ layout: Layout; authHost: { host: string }; appHost(slug: string): string }

    function buildAuthEdge(layout: Layout = LAYOUTS[0]): AuthEdge {
      // same registry and fakes; config: layout.config({ auth: testAuthConfig() })
    }
    ```
    `login()` and `redeem()` read `edge.authHost` instead of the module `AUTH_HOST`. Wrap each existing top-level `describe` with `describe.each(LAYOUTS)("[$name] ...", (layout) => ...)`. Replace the hard-coded `appa.local.helix.azxlabs.io` style hosts in the gateway block with `edge.appHost("appa")`. Run the file before adding any new case and confirm the single layout shows the same number of passing tests as before.

11. Comments. At `hosts.ts`, `config.ts` and each migrated call site, comment only constraints: why `auth` under the apps suffix is `platform` in split mode, why `publicOrigin` refuses reserved labels, why a subdomain control domain is refused. Do not cite change IDs (`CT-n`) or `workflow/` paths; ADR numbers are fine. Documentation of the new setting is CT-10.

12. Dedicated review pass. After the gate passes and before the commit, someone other than the author (a second agent or a person) reads the diff against the OIDC handoff end to end and writes `results/ct5-review.md` with: who reviewed, which files, and findings. The reviewer checks, at minimum: (a) every place a URL for the auth host or an app host is built, by `grep -rn "baseDomain\|controlDomain\|publicOrigin\|controlOrigin" apps/ packages/ --include='*.ts'`, matches the table in step 6; (b) no URL or host is taken from a request header (`Host`, `X-Forwarded-*`, `Origin`) except to classify it; (c) the `/_auth/complete` Location, the `/start` Location and the vendor callback URL each come from config; (d) `classifyHost` returns `auth` for exactly one host string in split mode; (e) cookie attributes are unchanged (`cookies.ts`); (f) the ten tests above fail when the production change they cover is reverted (revert one hunk at a time and rerun that test: classification, the `publicOrigin` guard, the call-site migration, the boot check). Findings are fixed or recorded with a reason before the commit.

13. Gate. From the dev container: `./check-and-lint.sh`. Then `just dev smoke` in single-domain mode (the edge, portal and egress change; it must pass unchanged). Split-mode smoke is CT-7; do not run `HELIX_APPS_DOMAIN` smoke here beyond a boot check that the edge starts with `EDGE_BASE_DOMAIN=helix-apps.localhost EDGE_CONTROL_DOMAIN=local.helix.azxlabs.io` and that `curl` with `--resolve` shows `auth.local.helix.azxlabs.io` answering `/start` with a 302 and `auth.helix-apps.localhost` answering 404 (put the output in `results/`).

## Done When

- [ ] All requirements met, including the four design notes recorded in `results/`.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just dev smoke` passes in single-domain mode, unchanged.
- [ ] With `EDGE_CONTROL_DOMAIN` unset every existing edge test passes with its assertions unmodified; the only edited existing assertions are the two `publicOrigin(..., "auth")` lines in `config.test.ts`, and `results/` lists every edited existing test file (fixtures, the `describe.each` wrapper in `adversarial.test.ts`, the `loginAs` parameter in `flow.integration.test.ts`).
- [ ] The ten adversarial tests exist at the files named in step 9, pass, and fail when the change they cover is reverted (the revert check is part of the review pass).
- [ ] `results/ct5-review.md` records the dedicated review pass: reviewer, files read, the checks in step 12, findings, and how each was resolved. A task that lacks this file is not done.
- [ ] No behavior beyond the task: no legacy redirect (CT-8), no portal change (CT-6), no Bicep (CT-9), no documentation beyond code comments (CT-10).
- [ ] Not verified here, and stated as such in `results/`: any browser behavior (cross-site navigation, cookie handling, `Sec-Fetch-Site` values; CT-7); Azure and ingress behavior. No Azure behavior is involved in this change.
- [ ] Committed with `fest commit -m "CT-5: edge control/apps domain split with adversarial tests"`.