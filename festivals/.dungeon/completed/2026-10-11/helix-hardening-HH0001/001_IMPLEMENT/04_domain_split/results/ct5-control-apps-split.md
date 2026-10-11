# CT-5 result: edge control/apps domain split

**Result: done, with the dedicated review pass recorded in `ct5-review.md`.**

`EDGE_CONTROL_DOMAIN` splits the edge's hosts. When it is unset, blank or equal to `EDGE_BASE_DOMAIN`, the layout is today's single domain.

- `classifyHost(host, baseDomain, controlDomain)` checks the apps suffix first, then the exact host `auth.<control>`, else `platform`. In split mode `auth.`, `portal.`, `api.` and `www.` under the apps domain are `platform` and get the same 404 as any platform host.
- `controlOrigin(config, "auth" | "portal" | "dev-api")` builds control origins. `publicOrigin` throws for reserved labels, so an unmigrated call site fails at its first call.
- All nine auth-host call sites use `controlOrigin`; the app-origin sites stay on `publicOrigin`.
- Boot validation (`resolveControlDomain`, shared by the edge and dev-gateway loaders) works as follows:
  - Legacy mode when the value is unset or equal.
  - Refuses an invalid hostname.
  - Refuses a control domain that is a subdomain of the apps domain.
  - Refuses an apps domain on or under `auth.`, `portal.` or `dev-api.` of the control domain (added after review).
  - Allows a parent control domain (the delegated-subdomain case in ADR-0028 decision 2).
- `resolveAppForAuth` treats reserved slugs as unknown (added after review).
- Both `boot.serving` log events gain `controlDomain` and `split`. No new metric or span attribute.

## Design notes (code versus design)

1. The design says eight auth-host call sites; the code has nine: `server.ts`, `auth/gate.ts`, `auth/routes/authHost.ts` (two), `auth/routes/passwordLogin.ts`, `routing/consentStart.ts`, `devGateway/consentStart.ts` (two) and `serving/assets.ts` (the `auth` half of `platformOrigins`).
2. The design says `dev-api.<apps>` classifies as `platform`. `dev-api` is not in `RESERVED_SUBDOMAINS`, so it classifies as an app with slug `dev-api`. That is harmless: the dev-gateway runs on `dev-api.<control>`, which never matches the apps suffix. The pinned property is that `auth.<apps>` is never `auth`.
3. The design puts the concurrent-redeem race in `flow.integration.test.ts`. The store-level race was already in `auth/sessions.integration.test.ts`. This change adds the HTTP-level race to the split block of `flow.integration.test.ts`.
4. The design says existing tests pass unmodified. Two `publicOrigin(..., "auth")` assertions in `config.test.ts` moved to `controlOrigin`, because `publicOrigin` now refuses reserved labels.

## Deviations and choices

- **`validateReturnPath`** (`auth/validate.ts`) now rejects percent-encoded control bytes. The code before this change accepted `/%0d%0aSet-Cookie:x=1`, which Test 6 must refuse. The reviewer confirmed that an encoded space, `%2F` and UTF-8 non-ASCII still pass, and that the newly rejected malformed paths were already refused by Fastify.
- **`gateTelemetry.test.ts` is unchanged.** The denial counter reads no config, and split mode adds no denial path; the reviewer agreed.
- **`connectionsJourney.integration.test.ts` is not extended.** The split consult is covered in `routing/consentStart.test.ts`, `devGateway/consentStart.test.ts` and Test 10. The real-browser split journey is CT-7.
- **`auth/handoff.test.ts` and `auth/flow.test.ts` are unchanged.** They take no host input.

## Edited existing test files

- `apps/edge/src/auth/adversarial.test.ts`: a `describe.each` single/split wrapper, plus split-only adversarial cases. The reviewer confirmed all 33 earlier tests survive with their assertions intact.
- `apps/edge/src/auth/flow.integration.test.ts`: `loginAs` options, plus a split block (login, concurrent redeem, `prompt=none` refresh).
- `apps/edge/src/config.test.ts`: the two `publicOrigin` lines, plus `controlOrigin`, reserved-label and boot-validation tests.
- `apps/edge/src/routing/hosts.test.ts`: split classification and lookalikes.
- `apps/edge/src/auth/validate.test.ts`: the corpus, split origin checks and reserved slugs.
- `apps/edge/src/auth/gate.test.ts`, `routing/consentStart.test.ts`, `devGateway/consentStart.test.ts`, `serving/connectHelper.test.ts` and `routing/connectionsProxy.test.ts`: split assertions.
- Fixtures: `apps/edge/src/test/config.ts` (`controlDomain`, `splitEdgeConfig`, `splitDevGatewayConfig`), `app.test.ts` and `serving/cspReport.test.ts` (`controlDomain`).
- `apps/connections-lane/src/world.ts`: a comment only.

## Evidence (coordinator)

- **Gate:** `./check-and-lint.sh`, 241 of 241 test files, 3634 tests. The six CT-5 suites run together: 220 tests.
- **Smoke and lane:** single-domain real-browser smoke 37 of 37; connections lane 10 of 10.
- **Split-mode boot check** on a real stack, with `EDGE_OIDC_ISSUER` pointed at the smoke IdP (`ct5-gate.txt`):
  - `auth.local.helix.azxlabs.io/start?app=smoke-internal` → 302 to the IdP, with `redirect_uri=https://auth.local.helix.azxlabs.io:9080/callback` and one flow cookie.
  - `auth.`, `portal.` and `www.helix-apps.localhost` → 404, no cookie.
  - The boot log shows `controlDomain` and `split: true`.
- **Dedicated review** (`ct5-review.md`): checks (a) to (f) pass, and all four revert checks fail when reverted. The working-tree hash was unchanged across the reviewer's edits (`9ab9ed74…`).

## Found along the way (carried to CT-7)

`scripts/stack-env.mjs` does not override `EDGE_OIDC_ISSUER` (or the portal's issuer) at a port offset. A kept smoke stack's edge pointed at `localhost:3002` while the smoke IdP listened on 4002. Single-domain smoke never runs the edge's `/start`, so nothing caught it. CT-7's cross-domain login needs it fixed.

## Not verified

Browser behavior (cross-site navigation, cookie handling and `Sec-Fetch-Site` across the two domains) is CT-7. Public-suffix-list isolation of a delegated apps zone, Safari's `*.localhost`, and Azure ingress are not verified. No Azure behavior is involved.

## Executor

cursor-agent, `composer-2.5`: the implementation (244 tool calls) and the review-fix batch. Dedicated review by a separate Claude agent; boot check and verification by the coordinator.
