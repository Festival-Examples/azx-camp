---
fest_type: task
fest_id: 04_ct7_smoke_runner_split_mode_and_connections_lane.md
fest_name: ct7 smoke runner split mode and connections lane
fest_parent: 04_domain_split
fest_order: 4
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.359305-06:00
fest_tracking: true
---

# Task: ct7 smoke runner split mode and connections lane

## Objective

Run the split layout end to end in a real browser inside the dev container: log in across the control and apps domains, record what `Sec-Fetch-Site` the browser sends, prove an app-set cookie does not reach the control host, exercise silent refresh, and run the connections consent popup with the opener on the apps domain, in the smoke runner and the connections lane. Implements CT-7 from 02-app-containment.md.

## Requirements

Testing is local only (decision V2 in `decisions.md`). Nothing here touches Azure, a real domain, a Public Suffix List entry, or Safari.

- [ ] **How the dev environment gets a second domain that resolves to 127.0.0.1** (built in `01_ct4_second_loopback_dev_domain.md`, used here): `HELIX_APPS_DOMAIN=helix-apps.localhost` makes apps live at `<slug>.helix-apps.localhost` while the control domain stays `local.helix.azxlabs.io` (a platform-owned DNS wildcard that points at 127.0.0.1). The apps names resolve through three paths that do not depend on a DNS server or on `getaddrinfo`: Chromium's `--host-resolver-rules` (Chromium also resolves `*.localhost` itself), a custom `lookup` in the runner's Node HTTP client, and the lane's own browser rule. One mkcert certificate (`local-helix-split.pem`) covers both domains and the fallback pair.
- [ ] **`.localhost` site classification is checked by reading `Sec-Fetch-Site`.** Whether a browser treats `helix-apps.localhost` and `local.helix.azxlabs.io` as different sites is a hypothesis (the design assumes the unlisted `localhost` TLD gets the implicit `*` public-suffix rule). The runner reads the header the browser actually sends on the handoff request (`/_auth/complete`) and on the app's own `/_api/*` calls, using Chrome DevTools Protocol `Network.requestWillBeSentExtraInfo` (the runner already enables `Network`), prints the value, and writes it to the run's output folder.
  - `cross-site` on the handoff: hypothesis confirmed for this browser engine; the cross-site checks run and count.
  - `same-site`: hypothesis refuted. The cross-site checks are reported as **SKIP, unverified**, never as passes, and the fallback from the design is used: rerun with `HELIX_APPS_DOMAIN=apps.local.helix.azxlabs.io`, the same-site pair. That pair runs the host-routing, handoff, Origin-check and boot-validation checks, and it shows the expected `same-site` result. It is also the negative control for cookie scope (below).
- [ ] **Split-mode smoke** (`HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke`) does, in addition to the existing groups:
  1. logs in across the two domains and lands on the app host: navigation to `https://<slug>.<apps>` is redirected to `https://auth.<control>/start`, then through the dev IdP, then back to `https://auth.<control>/callback`, then to `https://<slug>.<apps>/_auth/complete`, then to the page. Each `Location` is asserted against the expected origin (control for `/start` and `/callback`, apps for `/_auth/complete`);
  2. records `Sec-Fetch-Site` for the handoff request and for a `/_api/me` call made by the page, plus a sibling-app request (one app host to another app host, which is same-site by definition) and a request from the app page to the control host;
  3. completes silent refresh: the stack runs with a short `EDGE_SESSION_REFRESH_MS`, the page is reloaded after the session is due, and the chain through `auth.<control>/start?silent=1` (the dev IdP answers `prompt=none` from its browser session) lands back on the app page;
  4. proves an app-set cookie does not reach the control host: page script sets cookies with `Domain=` attributes for the apps domain, for `localhost`, and for the control domain; then top-level navigations to `https://auth.<control>/health` and to a sibling app host are logged, and the logged `Cookie` headers show (a) a positive control: the apps-domain cookie **does** reach the sibling app host (without it the negative result proves nothing), (b) no probe cookie and no `__Host-session` reaches `auth.<control>`;
  5. in the same-site fallback pair, the same cookie test is inverted and reported as the expected negative control: a `Domain=<control domain>` cookie set from the app host **does** reach `auth.<control>`, which is exactly why the operator documentation requires a Public Suffix List entry for a delegated apps subdomain;
  6. single-domain mode runs none of this and passes unchanged.
- [ ] **Connections consent popup in split mode runs in the connections lane, not in the smoke runner.** The smoke runner has no consent-popup driver at 792557a (it has no vendor fixture and no popup check); the Playwright lane (`apps/connections-lane`, `pnpm lane:connections`) is where the popup journeys live. The design's sentence "the smoke runner completes a connections consent popup" is therefore met in the lane, with the opener on the apps domain and the popup and callback on the control domain. Record this difference in `results/`.
- [ ] **Failure paths.** A missing cached Chromium, a missing split cert, or a browser that cannot resolve the names makes the browser checks SKIP with the reason; a SKIP is never counted as a pass and the task is not done on SKIPs alone (see Done When). A login that loops at `/start` (the symptom of a browser's tracking protection breaking the cross-site handoff) fails the login check with the redirect trail printed.
- [ ] Depends on: `02_ct5_edge_control_and_apps_domain_split.md` and `03_ct6_portal_control_origin.md` (the edge and portal must be split-aware), and `01_ct4_second_loopback_dev_domain.md` (cert, compose switch, resolver helpers, `split-tls` group).

## Implementation

Line numbers are at commit 792557a of `projects/helix`. CT-2 and CT-3 add a seeded `smoke-csp` app and an opt-in `ignoreCertErrors` to `launchBrowser`, and CT-4 adds resolution helpers and the `split-tls` group. Re-read `smoke.mjs` and `cdp.mjs` in full before editing, and reuse those additions.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-7-smoke-split-mode-and-lane`.

2. Read first: `.claude/skills/run-helix/smoke.mjs` (all; note `BASE_DOMAIN` at `:95`, `health` at `:120`, `EDGE` at `:190`, `rawGet` at `:202`, `seedRegistry` at `:304`, the edge group at `:417-480`, the IdP group's local `hop` helper at `:527-545` and `redirectUri` at `:557`, `checkBrowser` at `:646`, the group list and `main()`); `cdp.mjs` (all); `scripts/stack-env.mjs`; `.claude/skills/run-helix/SKILL.md`; `apps/connections-lane/src/world.ts` (`:73-74`, `:243-244`, `:290-304`, `:418-424`, `:481`, `:567`, `:614`), `apps/connections-lane/playwright.config.ts`, `apps/connections-lane/README.md`; `apps/edge/src/serving/consentPages.ts` around line 58 (the popup posts to `window.opener` with a config-derived target origin) and `serving/assets.ts:203`.

3. Move the control-host uses onto the control domain in `smoke.mjs`. `BASE_DOMAIN` (`:95`) is the apps domain in split mode. Add `const CONTROL = STACK.controlDomain;` and change these, which are auth-host URLs and must follow the control domain (in single-domain mode both are equal, so nothing changes there):
   - `:468` `loc.startsWith(`https://auth.${CONTROL}`)`;
   - `:539` the `hop` stop condition;
   - `:557` `redirectUri` (it must equal the first entry of `IDP_EDGE_REDIRECT_URIS`, which CT-4 builds from the control domain);
   - the health URLs at `:120` and `:426`: use `https://${CONTROL}:${STACK.ports.edge}/health` (the control apex is a platform host in both layouts).
   `EDGE(host)` (`:190`) keeps the apps domain.

4. `cdp.mjs`: record request headers. `launchBrowser` already calls `Network.enable` (`cdp.mjs:111`). Add a request log that pairs `Network.requestWillBeSent` with `Network.requestWillBeSentExtraInfo` (the second carries the headers actually sent, including `Sec-Fetch-Site` and `Cookie`). Redirect hops reuse one `requestId`, so pair the n-th event of each kind per id.
   ```js
   const sent = new Map();  // requestId -> [url, ...] one entry per hop
   const extra = new Map(); // requestId -> [headers, ...]
   const push = (m, k, v) => m.set(k, [...(m.get(k) ?? []), v]);
   listeners.add((msg) => {
     if (msg.sessionId !== sessionId) return;
     if (msg.method === "Network.requestWillBeSent") push(sent, msg.params.requestId, msg.params.request.url);
     if (msg.method === "Network.requestWillBeSentExtraInfo") push(extra, msg.params.requestId, msg.params.headers);
   });
   // on the returned handle:
   requestLog() {
     const lower = (h = {}) => Object.fromEntries(Object.entries(h).map(([k, v]) => [k.toLowerCase(), v]));
     return [...sent].flatMap(([id, urls]) => urls.map((url, i) => ({ url, headers: lower(extra.get(id)?.[i]) })));
   },
   ```
   `reset()` (`cdp.mjs:150`) also clears both maps. Verify the pairing on one real login before trusting it: print the log for `/_auth/complete` and confirm the `Cookie` and `Sec-Fetch-Site` entries belong to that hop. If the pairing is off by one on redirects, key by URL instead and say so in `results/`.
   Extend `launchBrowser` (CT-4 added `hostRules`) only if something is missing; do not add a second resolver flag.

5. `smoke.mjs`: a split group.
   - Add `"split"` to `GROUPS` (`:61`) and a `checkSplit()` wired into `main()` after `checkBrowser`, running only when `STACK.split`. The seed must have run: change the seed condition in `main()` (`smoke.mjs:796`) to `wanted("edge") || wanted("cli") || wanted("split")`. Put the group's expectations in one place:
     ```js
     const APPS = STACK.appsDomain;
     // Control is a parent of apps only in the fallback pair (apps.local.helix.azxlabs.io).
     const FALLBACK_PAIR = APPS.endsWith(`.${CONTROL}`);
     ```
   - Short refresh for silent refresh: when `STACK.split`, add `EDGE_SESSION_REFRESH_MS: "3000"` to `SVC_ENV` (`:58`) so a session is due three seconds after it is minted. Nothing else in the run depends on a long refresh interval.
   - Login by HTTP (`login across the two domains`, no browser needed, so it runs without Chromium): use `rawGet` (exact headers) with `Accept: text/html`, `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document`, and a small cookie jar keyed by hostname so a cookie set by one host is only replayed to that host (that is the property under test):
     ```js
     const jar = new Map(); // hostname -> Map(name -> value)
     const send = async (url) => {
       const u = new URL(url);
       const cookies = [...(jar.get(u.hostname) ?? [])].map(([k, v]) => `${k}=${v}`).join("; ");
       const r = await rawGet(url, { Accept: "text/html", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Dest": "document", ...(cookies ? { Cookie: cookies } : {}) });
       for (const c of [].concat(r.headers["set-cookie"] ?? [])) { /* store name=value under u.hostname */ }
       return r;
     };
     ```
     Walk the chain by hand: app URL, then assert 302 to origin `https://auth.${CONTROL}:<port>` and path `/start`; follow to the IdP, take the user through the interaction page the way `checkIdp` does (`?user=<fixture user>`), arrive at the callback URL on `auth.${CONTROL}`; replay it with the flow cookie; assert the next `Location` has origin `https://<slug>.${APPS}:<port>` and path `/_auth/complete`; follow it; assert a `__Host-session` cookie was set with no `Domain=`, that `jar` has it under the app host only, and that `GET https://<slug>.${APPS}:<port>/` with it returns 200. Extract the IdP-walking part of `checkIdp`'s local `hop` (`:527-545`) into a module-level helper rather than copying it.
   - Browser checks (skipped with a reason when `NO_BROWSER`, no cached Chromium or the launch fails, as `checkBrowser` does at `:646-660`); launch with the CT-4 `hostRules` for both domains and the CT-2 certificate option. Steps, each a `check(...)`:
     1. Navigate to `EDGE(slug)`. Wait on `location.href`: at an `/interaction/` URL, navigate to it again with `?user=alice@azx.dev` appended; wait until the URL is `https://<slug>.<apps>:<port>/`. Fail with the full `requestLog()` trail if it loops through `/start` more than twice.
     2. From `requestLog()`: find the `/_auth/complete` entry and read `sec-fetch-site`. Print `Sec-Fetch-Site on the handoff: <value>` and write `sec-fetch-site.json` (value, both domains, browser version from `/json/version`) to `OUT`. Evaluate in the page `fetch("/_api/me")` and read the logged header (`same-origin` expected). Evaluate a no-cors `fetch` of `https://auth.<control>:<port>/health` and of `https://<other-slug>.<apps>:<port>/` and read both (`cross-site` and `same-site` expected for the non-fallback pair). Expectation table: handoff `cross-site` when `!FALLBACK_PAIR`, `same-site` when `FALLBACK_PAIR`. When the observed value contradicts the table for the non-fallback pair, print `HYPOTHESIS REFUTED: .localhost names are same-site in this browser`, mark this check passed (it recorded the answer) and `skip()` the checks that assert cross-site, with that reason.
     3. Cookie scope. In the page set three cookies with `document.cookie`: `probe_apps=1; Domain=${APPS}; Path=/; Secure`, `probe_localhost=1; Domain=localhost; Path=/; Secure`, `probe_ctl=1; Domain=${CONTROL}; Path=/; Secure` (the browser will refuse the second and, outside the fallback pair, the third; the log tells what actually reached the wire, which is the evidence). Then `browser.reset()`, navigate to `https://<other-slug>.${APPS}:<port>/` (positive control: its logged `Cookie` contains `probe_apps`, otherwise fail with "positive control did not hold: the cookie was never set"), then navigate to `https://auth.${CONTROL}:<port>/health`. For the non-fallback pair assert the control request's `Cookie` header has no `probe_*` and no `__Host-session`; for the fallback pair assert it **does** contain `probe_ctl` (the negative control, reported as "expected: no PSL, same site").
     4. Silent refresh. After step 1, wait 3.5 seconds, `browser.reset()`, navigate to the app URL. Assert the log contains a request to `https://auth.${CONTROL}:<port>/start?...silent=1`, then the callback, then `/_auth/complete`, and the page ends on the app origin. This only works if the browser keeps the dev IdP session cookie (it is for `localhost:3002` and the profile directory is the same for the whole run).
   - Concurrent redeem under the split layout is covered at the HTTP level in CT-5 (`flow.integration.test.ts`); do not repeat it here.

6. Stack and compose. `scripts/stack-env.mjs` already emits the split environment (CT-4). `.devcontainer/docker-compose.yml`: remove the "not a working login until CT-5 and CT-6" caveat CT-4 added to the comment at `:86-90`, and nothing else unless a variable you needed is missing. `.github/workflows/ci.yml:176` only sets `EDGE_BASE_DOMAIN`; CI is off and the single-domain job is unchanged, so leave it and write "ci.yml unchanged: single-domain only, CI off" in `results/`.

7. Connections lane (`apps/connections-lane`). Add split mode, off by default, switched by the same variable. The lane builds its own edge in-process with `testEdgeConfig` (`world.ts:567`) behind its own TLS terminator and a self-signed certificate (`world.ts:418-424`), and its browser maps the dev domain with `--host-resolver-rules` (`playwright.config.ts`).
   - `world.ts:73-74`: keep `BASE` (the control domain) and `AUTH_HOST` as they are. Add `const APPS = process.env.HELIX_APPS_DOMAIN?.trim().toLowerCase() || BASE;`.
   - `world.ts:297-303` (`appHost`, `appOrigin`): `${slug}.${APPS}`. `callbackUrl` (`:293`, comment at `:290-292`) stays on `AUTH_HOST`: that is exactly the control-domain callback. Update the doc comment above it to say the edge builds it with `controlOrigin(config, "auth")` and the portal from `CONTROL_PUBLIC_BASE`.
   - `world.ts:418-424` (the openssl certificate): add `DNS:*.${APPS},DNS:${APPS}` to `subjectAltName` when `APPS !== BASE`.
   - `world.ts:481`: `process.env.APP_PUBLIC_BASE = `https://${APPS}:${this.edgeTlsPort}``, and next to it `process.env.CONTROL_PUBLIC_BASE = `https://${BASE}:${this.edgeTlsPort}`` when split, deleted again in `stop()` beside the existing `delete process.env.APP_PUBLIC_BASE` (`:614`).
   - `world.ts:567`: pass `baseDomain: APPS, controlDomain: BASE` to the `testEdgeConfig({ ... })` call.
   - `playwright.config.ts`: the resolver rule becomes `MAP *.local.helix.azxlabs.io 127.0.0.1` plus, when `HELIX_APPS_DOMAIN` is set, `, MAP *.<apps> 127.0.0.1, MAP <apps> 127.0.0.1` in one `--host-resolver-rules` argument (Chromium takes a single flag with comma-separated rules).
   - `README.md` of the lane: one paragraph on the variable and that split mode makes the opener (the app page) cross-origin and, where the browser agrees, cross-site with the popup and callback.
   - The specs build URLs through `world.appOrigin(slug)` and `world.callbackUrl`; confirm with `grep -n "local.helix\|baseDomain" apps/connections-lane/src/*.spec.ts` that no spec hard-codes a host. If one does, route it through `world`.

8. Docs for the run: `.claude/skills/run-helix/SKILL.md` gets a "Split-domain mode" section: the variable, the two domains, that `--only split` runs just the new group, how to read `sec-fetch-site.json`, the fallback command, and that a Chromium-less run SKIPs the browser checks.

9. Run, from the dev container, and save every output under `results/`:
   - `./check-and-lint.sh`;
   - `just dev smoke` (single-domain; unchanged, with the same pass count as before this task);
   - `HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke`;
   - if (and only if) the recorded `Sec-Fetch-Site` was `same-site`: `HELIX_APPS_DOMAIN=apps.local.helix.azxlabs.io just dev smoke`; and run the fallback pair anyway once, because its inverted cookie check is the negative control that shows the cross-site check can fail;
   - `pnpm lane:connections` (single-domain) and `HELIX_APPS_DOMAIN=helix-apps.localhost pnpm lane:connections` (needs `xvfb-run` and the cached Chromium; the README has the exact command).

## Done When

- [ ] All requirements met.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just dev smoke` in single-domain mode passes with the same results as before (no new SKIP, no failures).
- [ ] `HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke` passes the login across the two domains, the handoff-origin assertions, silent refresh and the cookie-scope checks (including the positive control), and `results/` shows the `Sec-Fetch-Site` value it printed and the `sec-fetch-site.json`. If Chromium could not run, the browser checks are listed as SKIP, the task is **not** reported as proven, and the HTTP-level login check is the only evidence; say so.
- [ ] The `.localhost` hypothesis is answered in `results/` with the observed value and Chromium version: confirmed (cross-site checks counted) or refuted (cross-site checks skipped as unverified, fallback pair run).
- [ ] The same-site fallback pair has been run at least once and shows the expected `same-site` result and the inverted cookie check.
- [ ] `pnpm lane:connections` passes in single-domain mode, and the split-mode run (`HELIX_APPS_DOMAIN=helix-apps.localhost pnpm lane:connections`) completes the consent journeys with the popup on the control domain. If the lane cannot run here (no `xvfb-run`, no Chromium), say so; the popup claim in split mode is then unverified.
- [ ] The three differences from the design are in `results/`: the consent popup runs in the lane, not the smoke runner; `ci.yml` left unchanged; `Sec-Fetch-Site` captured through DevTools Protocol events.
- [ ] Stays **unverified** (local only, per V2), and stated in `results/` and carried into the operator rollout notes: Safari ITP, Firefox ETP and Chrome bounce-tracking behavior on real domains (a loopback name cannot prove them; Playwright's WebKit is not Safari); behavior with a real Public Suffix List entry or a real delegated zone; Safari's handling of `*.localhost`; real certificate issuance and Azure ingress header-size limits. Whether each browser engine classifies the `.localhost` pair as cross-site is answered only for the engine that ran.
- [ ] Committed with `fest commit -m "CT-7: smoke runner split mode, Sec-Fetch-Site record, connections lane"`.
