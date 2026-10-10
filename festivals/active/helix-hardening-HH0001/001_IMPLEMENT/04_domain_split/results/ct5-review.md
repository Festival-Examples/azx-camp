# CT-5 dedicated review pass

- **Reviewer:** Claude, dedicated review pass (a second agent; not the author of the change).
- **Date:** 2026-10-10
- **Repository and branch:** `projects/helix`, `ct-5-control-apps-domain-split`. The change is uncommitted in the working tree (25 modified files, nothing untracked).
- **Tree identity:** `git diff | shasum` = `9ab9ed741b3424c57a96fb7e0a4a7ab5cd67e606` before the review and after every revert check. That matches the coordinator's `9ab9ed741b3424c5`.
- **Files read:**
  - Task and design: `02_ct5_edge_control_and_apps_domain_split.md` and design `02-app-containment.md` Part 1.
  - Production code, full diff and the surrounding code: `routing/hosts.ts`, `config.ts` (`resolveControlDomain`, `loadGatewayConfig`, `loadConfig`, `loadDevGatewayConfig`, `publicOrigin`, `controlOrigin`), `app.ts` (hook and the auth, connections and catch-all routes), `auth/routes/authHost.ts` (all of it), `auth/validate.ts` (all of it), `auth/gate.ts` (redirect builders, `countDenial`), `auth/routes/passwordLogin.ts`, `auth/cookies.ts`, `routing/consentStart.ts`, `devGateway/consentStart.ts`, `devGateway/resolver.ts`, `devGateway/app.ts` (Origin handling), `devGateway/server.ts`, `server.ts`, `serving/assets.ts`, `routing/connectionsProxy.ts` (header forwarding), `test/config.ts`, `test/fakes.ts` (`FakeOidcClient`).
  - Tests, full diff: `auth/adversarial.test.ts` (compared with `git show HEAD:`), `auth/flow.integration.test.ts`, `routing/hosts.test.ts`, `config.test.ts`, `auth/validate.test.ts`, `auth/gate.test.ts`, `routing/connectionsProxy.test.ts`, `routing/consentStart.test.ts`, `devGateway/consentStart.test.ts`, `serving/connectHelper.test.ts`, `app.test.ts`, `serving/cspReport.test.ts`. I also read `auth/gateTelemetry.test.ts`, which is unchanged.
  - Elsewhere: `packages/shared/src/app.ts` and `api.ts` (slug schema), `apps/portal/src/routes/apps.ts` (app creation), `apps/connections-lane/src/world.ts:291`.

All paths below are relative to `projects/helix/apps/edge/src/` unless stated otherwise. Line numbers are in the reviewed working tree.

**Baseline.** Before any revert, the 11 affected test files passed in the dev container: 350 tests. `adversarial.test.ts` runs 73 tests. That is 33 per layout, which equals the 33 tests in HEAD, plus 7 split-only tests.

---

## (a) Every auth-host and app-host URL builder matches the step 6 table

`git grep -n "baseDomain\|controlDomain\|publicOrigin\|controlOrigin" -- apps packages` (non-test files):

| Site | Builds | Helper | Matches table |
|---|---|---|---|
| `server.ts:135` | OIDC `redirect_uri` | `controlOrigin(config, "auth")` | yes (table said `:131`) |
| `auth/gate.ts:181` | `/start` (cold and silent) | `controlOrigin` | yes |
| `auth/gate.ts:204` | password-app `/_auth/login` | `publicOrigin(…, entry.slug)` | yes, app origin |
| `auth/routes/authHost.ts:153` | code-exchange callback URL | `controlOrigin` | yes |
| `auth/routes/authHost.ts:163` | silent-refresh restart `/start` | `controlOrigin` | yes |
| `auth/routes/authHost.ts:204` | `/_auth/complete` | `publicOrigin(…, entry.slug)` | yes, app origin |
| `auth/routes/passwordLogin.ts:61` | SSO `/start` link | `controlOrigin` | yes |
| `auth/validate.ts:97` | `isSameOrigin` expected value | `publicOrigin(…, slug)` | yes (table said `:88`) |
| `routing/consentStart.ts:246` | app origin / opener | `publicOrigin(…, slug)` | yes |
| `routing/consentStart.ts:320` | vendor `callbackUrl` | `controlOrigin` | yes |
| `devGateway/consentStart.ts:170` | vendor `callbackUrl` | `controlOrigin` | yes |
| `devGateway/consentStart.ts:211` | popup URL | `controlOrigin` | yes |
| `serving/assets.ts:202` | `platformOrigins` | `[publicOrigin(slug), controlOrigin("auth")]` | yes (table said `:203`) |
| `app.ts:395` | host classification | `classifyHost(host, baseDomain, controlDomain)` | yes |
| `server.ts:392-394`, `devGateway/server.ts:210-212` | `boot.serving` | `controlDomain`, `split` log fields | yes, log fields only |

No other code in `apps/` or `packages/` builds an auth or app origin. The portal is CT-6. The only other hit is a stale comment in `apps/connections-lane/src/world.ts:291` (F-9). `publicOrigin` has no remaining non-test call with a reserved label.

**Verdict: pass.**

## (b) No URL or host is taken from a request header except to classify it

- `Host` is read only at `app.ts:395`, where it goes into `classifyHost`. Nothing uses Fastify's `req.hostname` or `req.host`.
- `Origin` and `Referer` are only compared with config-built origins: `auth/validate.ts:97`, `routing/consentStart.ts:120-133` against `appOrigin` from `:246`, `auth/routes/appHost.ts:171`, `routing/consentCancel.ts:151`, and `auth/routes/passwordLogin.ts:167`.
- `X-Forwarded-For` is read only by the trust-proxy self-report (`routing/trustProxyHealth.ts:163`). No code reads `X-Forwarded-Host` or `X-Forwarded-Proto`.
- `/callback` takes only the path and query from `req.raw.url`. The origin comes from config (`authHost.ts:151-154`).
- Pre-existing and unchanged: the dev-gateway reflects `Origin` only after matching it against the dev token's registered origins (`devGateway/resolver.ts:59-62`, `devGateway/app.ts:253-258`). It then uses that value as `openerOrigin` (`devGateway/consentStart.ts:139`). The value is bound by an allowlist, and this diff does not touch it.

**Verdict: pass.**

## (c) `/_auth/complete`, `/start` and vendor-callback Locations come from config

- **`/_auth/complete`:** built at `authHost.ts:204` as `publicOrigin(rt.config, entry.slug)`. `entry` is re-resolved from the registry using the signed flow cookie's `app` (`:136`, `:143`). The final app-host redirect after redemption is the path-only `rd` (`auth/routes/appHost.ts:90`).
- **Redirects to `/start`:** `gate.ts:181` (`ssoStartUrl`, used by both `redirectToLogin` and `redirectToRefresh`), `authHost.ts:163` and `passwordLogin.ts:61`. All three use `controlOrigin`.
- **`/start`'s own Location:** the IdP authorize URL. Its `redirect_uri` is fixed at construction from `controlOrigin` (`server.ts:135`).
- **Vendor callback:** `routing/consentStart.ts:320` and `devGateway/consentStart.ts:170` use `controlOrigin`. The dev popup URL also uses it (`devGateway/consentStart.ts:211`).

**Verdict: pass.**

## (d) `classifyHost` returns `auth` for exactly one host string in split mode

`routing/hosts.ts` has two `auth` returns:

- `:38-40` requires `controlDomain === baseDomain`, so it is unreachable in split mode.
- `:47-49` requires the normalized host to equal `` `auth.${controlDomain}` `` exactly.

Normalization at `:27-32` works as follows. An absent value or one containing `[` gives `platform`. Otherwise the host is cut at the first `:` and lowercased. In split mode, then, the only spellings that classify as auth are case variants of `auth.<control>` followed by any port suffix. The tests pin `AUTH.<CONTROL>`, `:8443` and the bare `:` (`routing/hosts.test.ts`, "rejects lookalike auth hosts").

These all classify as `platform` and are pinned:

- the trailing dot `auth.<control>.`
- `xauth.`, `a.auth.` and `auth.<control>.evil.example`
- the userinfo shapes `evil.example:@auth.<control>` and `evil.example@app.<apps>`
- `auth.<apps>`, `portal.<apps>`, `www.<apps>` and `api.<apps>`
- `demo.<control>`
- both bare domains

The order is apps suffix first, so in the parent layout `auth.apps.helix.customer.test` falls to the reserved-label rule and classifies as platform. Test: "delegated-subdomain: control parent of apps".

If the control domain were a subdomain of the apps domain, `auth.<control>` would have a dotted label under the apps suffix. No host would classify as auth, so the login would fail closed. Boot refuses that pair anyway.

**Verdict: pass.**

## (e) Cookie attributes are unchanged

- `git diff HEAD -- apps/edge/src/auth/cookies.ts` is empty.
- The serializers at `auth/cookies.ts:59-75` emit `__Host-` names with `Path=/; Secure; HttpOnly; SameSite=Lax` and no `Domain`.
- No changed call site passes a host or config into a serializer.

**Verdict: pass.**

## (f) Revert checks

Procedure for each check:

1. Back up the file to `scratchpad/review-backup/` and record its `git diff <file> | shasum`.
2. Apply the minimal revert.
3. Run only the covering test files in the dev container with `pnpm vitest run`.
4. Restore with `cp` and confirm the per-file hash matches the recorded one.

| # | Revert | Tests run | Result |
|---|---|---|---|
| 1 | `hosts.ts:38`: drop `&& controlDomain === baseDomain` | hosts, adversarial, connectionsProxy | **4 fail:** hosts › "pins auth on the control domain only"; hosts › "delegated-subdomain: control parent of apps"; adversarial › "split layout: auth-host impersonation…" › "never runs auth handlers or sets cookies on reserved apps hosts"; connectionsProxy › "split layout: callbacks on auth.<apps> 404 without calling the portal". Every single-layout test passes. |
| 1b | Whole `hosts.ts` replaced with HEAD (ignores `controlDomain`) | hosts, adversarial, connectionsProxy, gate | **33 of 129 fail**, all split-layout. The single layout stays green. |
| 2 | `config.ts:1105-1109`: remove the reserved-label guard in `publicOrigin` | config, adversarial, gate, validate | **1 fails:** config › publicOrigin › "refuses reserved control labels" (test 7). Nothing else fails, as expected once every call site is migrated. |
| 3a | `authHost.ts:163`: back to the literal pre-change `publicOrigin(rt.config, "auth")` | adversarial | **2 fail:** "[single\|split] a silent refresh the IdP cannot satisfy restarts interactively", because the guard throws. |
| 3b | `authHost.ts:163`: hand-built `` `${scheme}://auth.${baseDomain}:${port}/start` ``, which bypasses the guard | adversarial | **1 fails:** the [split] silent-restart test. Expected `auth.local.helix.azxlabs.io:8080`, received `auth.helix-apps.localhost:8080`. This shows the split host assertion is load-bearing on its own. |
| 3c | Extra: `authHost.ts:153`, hand-built `auth.<baseDomain>` as the code-exchange base | adversarial, flow.integration | adversarial **73/73 pass**, because the fake OIDC client ignores the callback origin. flow.integration › split layout: **both tests fail** (real IdP, `redirect_uri` mismatch). See F-6. |
| 4 | `config.ts:867-872`: remove the subdomain refusal in `resolveControlDomain` | config | **1 fails:** "rejects a control subdomain of the apps domain" (both loaders, test 8). |

Restores: the per-file hashes matched before and after each revert (`hosts.ts` a8aa7642…, `config.ts` 257a1615…, `authHost.ts` f69c7e23…). The final whole-tree `git diff | shasum` is `9ab9ed741b3424c57a96fb7e0a4a7ab5cd67e606`. I made no git state changes.

**Verdict: pass.** Each covered production change fails at least one of the ten tests when reverted.

---

## Unchanged assertions in `adversarial.test.ts`

- All 33 HEAD tests are present with unchanged titles inside `describe.each(LAYOUTS)("$name layout", …)` (`adversarial.test.ts:182`). The single layout runs 33.
- `diff -w` against `git show HEAD:apps/edge/src/auth/adversarial.test.ts` shows changes only to where hosts come from:
  - `AUTH_HOST` became `edge.authHost`;
  - literal hosts became `edge.appHost()`, `edge.controlHost`, `layout.apps` or `appsApex`;
  - `testEdgeConfig()` became `layout.config()`.
- No `expect` was removed, no matcher changed and no expected status changed.

Two points, so that the "assertions unchanged" claim in `results/` is precise:

1. Some single-layout requests now send `Host: …:8080` where HEAD sent no port: the two-router test (`:498`), the gateway `call` helper (`:624`) and `connectHelper.test.ts` `serveIndex`. `classifyHost` drops the port (`hosts.ts:31-32`), so the classification under test is the same.
2. `completeUrl.host` (`:188`) and `restart.host` (`:303`) are now compared with values from `publicOrigin` and `controlOrigin` rather than literals. The literal values are still pinned in `config.test.ts` (`controlOrigin` dev and prod, `publicOrigin` "demo"). Revert 3b shows the split assertion catches a wrong host.

Other edited existing test helpers carry no assertion changes:

- `routing/consentStart.test.ts` `buildConsentEdge` gained a `config` option.
- `serving/connectHelper.test.ts` `serveIndex` gained a config parameter and derives its host from it.
- `flow.integration.test.ts` `browseIdpLogin` and `loginAs` gained parameters.

**Verdict:** no existing assertion is weakened, dropped or changed in meaning.

## The `validateReturnPath` change (`auth/validate.ts:46-54`)

**Verdict: correct; keep it.** It is not purely extra scope. Test 6 requires `/%0d%0aSet-Cookie:x=1` to get 400, and HEAD's version accepted that string: it has no raw control character, a single leading slash, the same origin and no `/_api`.

I probed the change with Node in the dev container:

- **Accepted:** `%20` (decodes to a space, which the regex excludes on purpose), `%2F` (decodes to `/`), `/café` and `/caf%C3%A9`.
- **Rejected:** `%0d%0a`, `%7f`, other `%00`-`%1f` bytes, and anything `decodeURIComponent` throws on. That last group is a bare `%`, `%zz` and non-UTF-8 bytes such as `%E9`.

The throwing cases cannot arrive as server-derived `rd` from the gate (`gate.ts:202`, `:227`). Fastify 5.12.5 answers 400 `FST_ERR_BAD_URL` for `/100%`, `/a%zz` and `/%E9t%E9` before the catch-all route at `app.ts:830` runs; I probed this with the edge's own Fastify. Sent directly as `/start?rd=`, they now get 400, which is correct because the app host could not serve such a path anyway.

Only the pathname is decoded. Encoded controls in the query (`/x?q=%0d%0a`) still pass. That is harmless: the `Location` header keeps them percent-encoded, and Node refuses raw CR or LF in headers. The rationale belongs in `results/` (F-4).

## `gateTelemetry.test.ts` left unchanged

**Verdict: acceptable, if `results/` records it.**

- The test at `auth/gateTelemetry.test.ts:30-47` never builds an app or reads config. It calls `instruments().sessionGateDenied.add` directly, so running it "against a split config" has no input to change. The author's "no config seam" statement is accurate.
- The property the task cares about holds by construction. `countDenial(reason: SessionDenialReason)` (`gate.ts:267-268`) is called with four literal reasons, and this diff touches none of them.
- Split mode adds no denial path. `auth.<apps>` is refused in `app.ts` routing with `sendNotFound`, before the gate.
- Optional, if someone wants real evidence: in `gate.test.ts`'s split describe, wrap one denied navigation in `startRecordingTelemetry` and assert that the recorded reasons are a subset of `SESSION_DENIAL_REASONS`.

## Boot validation

**Verdict: the rules match the task and apply to the dev-gateway.** One edge case is recorded as F-7.

`config.ts:856-875`:

- The input is trimmed and lowercased.
- Unset, blank or equal to the base returns the base, without validating the base, as specified.
- In split mode, `HOSTNAME` is checked on both values. It rejects a scheme, a port, a path, spaces, a single label, a leading or trailing dot, and an underscore.
- A control domain ending in `.${base}` throws with a message that names both variables and the reason.
- A parent of the apps domain is allowed.

The call is in `loadGatewayConfig` (`config.ts:905-906`). Both `loadConfig` (`:1028`) and `loadDevGatewayConfig` (`:1068`) spread that result and do not override `baseDomain` or `controlDomain` afterwards.

`config.test.ts` covers:

- the subdomain and malformed cases, through both loaders;
- unset, blank, `"  "`, equal and uppercase-equal, through `loadConfig` only;
- the parent pair with lowercasing, through `loadConfig` only.

The `loadConfig`-only cases hold by construction for the dev-gateway, which shares the code path. Test gaps are listed in F-8.

---

## Findings

**F-1. Should fix. Confirmed.** `auth/flow.integration.test.ts:117`: `loginAs` sends `/callback` with the module constant `AUTH_HOST` instead of the `authHost` it resolved at `:100`.

- The split test passes only because `SPLIT_CONTROL_DOMAIN` is `local.helix.azxlabs.io`, the legacy domain. For the same reason `SPLIT_AUTH_HOST` equals `AUTH_HOST` and `SPLIT_REDIRECT_URI` equals `REDIRECT_URI`, so the "split" login's IdP leg is byte-identical to the single one.
- If the constant changes, this test will 404 for a reason unrelated to the code under test. That is the drift the task's "build hosts from config" rule exists to prevent.
- **Fix:** at `:117`, use `headers: { ...authHost, cookie: … }`.

**F-2. Should fix. Confirmed.** Test 4 (`adversarial.test.ts`, "split layout: cookie scope across domains") is weaker than step 9 specifies:

- `:857` accepts `[404, 503]` and `:866` accepts `[401, 404]`, although each harness gives one fixed outcome: 503, because no portal provider is wired, and 401.
- "The body carries no identity" is not asserted for `/_api/me` or `/connections/*` on the control host.
- "Does not consume the flow" is not asserted for the flow cookie sent to `appa.<apps>/callback`.
- The cookie-attribute loop (`:872`) checks `/start` and redeem but not the `/callback` `Set-Cookie`. `login()` (`:141-166`) does not return the callback response.
- **Fix:**
  - pin 503 and 401;
  - assert the bodies contain no `oid` or email;
  - assert `flowOnApp.headers["set-cookie"]` is undefined (the real callback handler always clears the flow cookie first, `authHost.ts:133`, so its absence proves the handler did not run);
  - return the callback response from `login()` and include it in the loop.

**F-3. Should fix (fix or record). Confirmed.** Step 9 calls Test 9 "concurrent redeem race and `prompt=none` against the real dev IdP". The split `describe` in `flow.integration.test.ts` has the login and the race, but no split silent-refresh case: the gate redirect host is `auth.<control>` with `silent=1`, and the callback completes on `app.<apps>`.

- Partial cover exists elsewhere. The adversarial split "restarts interactively" test checks the restart host, and `redirectToRefresh` shares `ssoStartUrl` with the cold path that `gate.test.ts` covers in split mode. The race's seven 403s cover replay.
- **Fix:** copy the case at `flow.integration.test.ts:313` into the split describe using `splitApp` and `SPLIT_AUTH_HOST`, or record in `results/` why it is omitted.

**F-4. Should fix. Confirmed.** `results/` contains no CT-5 records yet; only `ct4-*` files are there. The Done-When requires them before the commit:

- the four design notes;
- every edited existing test file: `adversarial.test.ts` (wrapper), `flow.integration.test.ts` (`loginAs` and `browseIdpLogin`), `connectHelper.test.ts` (`serveIndex`), `routing/consentStart.test.ts` (`buildConsentEdge`), `config.test.ts` (the two `controlOrigin` lines), and the fixtures;
- the `gateTelemetry.test.ts` deviation and its reason (section above);
- the `connectionsJourney.integration.test.ts` fallback: the file is not in the diff, and the two origins are asserted at the consult call in `routing/consentStart.test.ts` instead;
- "`auth/handoff.test.ts` and `auth/flow.test.ts` unchanged, no host input";
- the rationale for the `validateReturnPath` change;
- the not-verified statement: browser behavior (CT-7) and Azure.

**Fix:** write those records before `fest commit`.

**F-5. Note. Confirmed by code reading (not executed).** An app whose slug is a reserved label (`www`, `api`, `portal` or `auth`) now hits a 500 at `/callback`.

- The portal does not reserve those slugs: `CreateAppRequestSchema.slug` is `AppSchema.shape.slug`, which only checks `SLUG_PATTERN` (`packages/shared/src/api.ts:17`, `app.ts:11`).
- `resolveAppForAuth` accepts them (`auth/validate.ts:69-83`).
- `/callback` creates the pending row (`authHost.ts:184`) and mints the token. `publicOrigin(rt.config, "www")` at `:204` then throws.
- In HEAD the same flow ended with a 302 to `www.<base>/_auth/complete?token=…`. That is a platform host which 404s on the edge, and it would hand the token to another server if that name resolved off-edge. The new guard fails closed, which is an improvement. The residual is a 500 and an orphaned pending row for an app that could never be served.
- **Fix (optional):** have `resolveAppForAuth` return `unknown` for `RESERVED_SUBDOMAINS`, so `/start` answers 404 before any IdP round-trip. Reserving the slugs in the portal is CT-6 territory.

**F-6. Note. Confirmed (revert 3c).** `FakeOidcClient.exchangeCode` (`test/fakes.ts:490`) ignores the callback URL's origin.

- The `controlOrigin` migration of the code-exchange `redirect_uri` (`authHost.ts:153`) is covered only by the Postgres/real-IdP split tests in `flow.integration.test.ts`. The adversarial suite stays green when it is reverted.
- **Fix (optional):** record `callbackUrl` in the fake and assert its origin equals `controlOrigin(cfg, "auth")` in the adversarial split happy path.

**F-7. Note. Confirmed that the config is accepted (by reading `resolveControlDomain`); the browser impact is a Hypothesis.**

- `EDGE_BASE_DOMAIN=auth.example.test` with `EDGE_CONTROL_DOMAIN=example.test` loads. The parent case is allowed, and the base does not end in `.example.test`.
- Apps then live under the auth host (`<slug>.auth.example.test`), so any app can set `Domain=auth.example.test`, the exact reach the subdomain rule exists to refuse. The same holds for `portal.` and `dev-api.`.
- This is a special case of the accepted parent layout and its Public Suffix List caveat, but it is an obviously wrong config.
- **Fix (optional):** also refuse when `baseDomain` equals, or ends with, `.<label>.<control>` for `label` in `auth`, `portal` or `dev-api`.

**F-8. Note. Confirmed.** Smaller gaps against the step 9 list. The behavior holds in each case, but the tests do not pin it.

- **Test 1:** adversarial impersonation wires no portal fake, so "portal records no call" relies on test 10.
- **Test 2:** the request-level list omits absent, `[::1]:8080` and empty hosts.
- **Test 5:** `origin: null` in the `call` helper means "no Origin header". The literal `Origin: null` string is never sent.
- **Test 6:** the request-level corpus omits `https://<apps>/` and, unlike HEAD's corpus, does not assert that no `set-cookie` is sent.
- **Test 8:** there are no trailing-dot, space or path cases, and no case for an invalid `EDGE_BASE_DOMAIN` in split mode.
- **Minor:**
  - `hosts.test.ts`'s split describe uses literal domains instead of `SPLIT_*`;
  - `secFetchMode` in `call` is unused;
  - `edge.provider.calls.length = 0` after an `expect(...).toHaveLength(0)` has no effect.

**F-9. Note. Confirmed.** `apps/connections-lane/src/world.ts:291`: the comment still says the edge builds the callback with `publicOrigin(config, "auth")`. **Fix:** change it to `controlOrigin`.

## Not verified in this review

- `./check-and-lint.sh` (typecheck, lint, format, docs): not run. I ran only vitest and two read-only Node probes in the dev container.
- Browser behavior: cross-site classification, cookie handling and the `Sec-Fetch-Site` values real browsers send (CT-7).
- Azure.

## Final verdict

**Production code: approved.** No blocking defect was found. Checks (a) to (f) pass, the single-domain layout behaves as before, and every failure direction is closed.

**Commit: not yet.** It is ready once F-1 to F-4 are fixed or, where the finding allows it, recorded with a reason in `results/`. All four are changes to tests or records. F-5 to F-9 are optional; the author can take them or leave them with a line in `results/`.

## Resolution (coordinator, 2026-10-10)

The author agent fixed the findings in a follow-up batch on the same branch. The coordinator then reran the gate (3634 tests), the six CT-5 suites (220 tests), the real-browser smoke (37 of 37) and the connections lane (10 of 10); output is in `ct5-gate.txt`.

| Finding | Resolution |
| --- | --- |
| F-1 | Fixed. `loginAs` sends `/callback` to the resolved `authHost`. The split layout's control domain is now `helix-control.localhost`, so `SPLIT_REDIRECT_URI` differs from `REDIRECT_URI` and the test proves the host. |
| F-2 | Fixed. Each outcome is pinned to one status: 503 on `/connections/foo`, 401 on an app-host `/callback`. `expectNoIdentity` runs on the control-host responses. The handoff still redeems after the flow-cookie probe. The cookie-attribute loop covers start, callback and redeem. |
| F-3 | Fixed. The split test "silently refreshes via prompt=none on the control auth host" runs against the real dev IdP. |
| F-4 | Fixed. `ct5-control-apps-split.md` holds the design notes, edited test files, deviations and the not-verified statement. |
| F-5 | Fixed. `resolveAppForAuth` treats `auth`, `portal`, `api` and `www` as unknown (404 at `/start` before any pending row); test added. |
| F-6 | Recorded. The `redirect_uri` migration at `authHost.ts:153` is covered by the Postgres and real-IdP integration tests (Test 9), not the unit fake. |
| F-7 | Fixed. `resolveControlDomain` refuses an apps domain on or under `auth.`, `portal.` or `dev-api.` of the control domain, naming both variables; test added. |
| F-8 | Partly fixed: a path-bearing `Host` (a trailing dot was already in the classify table) and a literal `Origin: null`. The remaining items are behavior that holds but is not pinned. |
| F-9 | Fixed: the comment in `apps/connections-lane/src/world.ts`. |

The reviewer's revert checks (f) ran on the code before these fixes. The fixes changed tests, plus two production additions (reserved slugs, the reserved-label boot rule). Neither touches the four reverted hunks.
