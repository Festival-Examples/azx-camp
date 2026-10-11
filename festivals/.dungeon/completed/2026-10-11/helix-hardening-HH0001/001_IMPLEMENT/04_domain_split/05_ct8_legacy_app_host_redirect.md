---
fest_type: task
fest_id: 05_ct8_legacy_app_host_redirect.md
fest_name: ct8 legacy app host redirect
fest_parent: 04_domain_split
fest_order: 5
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.359667-06:00
fest_updated: 2026-10-10T08:47:08.524921-06:00
fest_tracking: true
---


# Task: ct8 legacy app host redirect

## Objective

Add an optional, default-off grace-period redirect so that, after apps move to the apps domain, a GET or HEAD to the old `<slug>.<controlDomain>` URL of a live app gets a `307` to the same path on the new app origin, with a counter that tells the operator when to switch it off. Implements CT-8 from 02-app-containment.md.

## Requirements

- [ ] **Setting.** `EDGE_LEGACY_APP_REDIRECT`, parsed strictly (`=== "true"`, any other value or unset is off), default off. It only has an effect in the split layout; with `controlDomain === baseDomain` the old and new hosts are the same host, so the setting is ignored and the effective config value is `false`. The effective value is part of the `boot.serving` log.
- [ ] **Classification.** `classifyHost` gains a fourth parameter and a `legacy-app` kind: `{ kind: "legacy-app"; slug }` for `<slug>.<controlDomain>` when the redirect is enabled. The order is: apps suffix first, then the exact `auth.<controlDomain>`, then (only when enabled) a single label under the control suffix that matches `SLUG_PATTERN` and is not in `RESERVED_SUBDOMAINS`, else `platform`. `dev-api` is also never a legacy app label: `dev-api.<controlDomain>` belongs to the dev-gateway. With the setting off, `<slug>.<controlDomain>` is `platform` and gets today's 404.
- [ ] **When the redirect fires.** Only when all hold: the method is GET or HEAD; the path does not begin with `_` (so `/_auth/*`, `/_api/*`, `/_helix/*` and `/_csp-report` can never be used to move a token or a credentialed request to another host; this is broader than `isReservedAppPath` in `app.ts:117`, which names four prefixes); the path passes `validateReturnPath` (`auth/validate.ts:30`); the registry is loaded; the slug is registered, not archived, has a live version (`blobPrefix` not null) and its visibility mode is permitted by `visibilityModeAllowed(entry.visibilityMode, config)`.
- [ ] **What it sends.** `307`, `Location` built from config and the registry's slug plus the validated path (`publicOrigin(config, slug)` + path, query kept; the target host is never taken from the request), `cache-control: no-store` (browsers cache 301 and 308, and a rollback would break), and `referrer-policy: no-referrer` (the URL may carry a query). No session transfer: visitors sign in again on the new host.
- [ ] **What it never does.** A POST, PUT, PATCH or DELETE is not redirected (a 307 would replay the body at another origin); an unknown, archived, nothing-live or mode-disallowed slug, and a not-loaded registry, all get the same plain 404 an unknown host gets (no distinguishing archived from unknown, unlike the 410 `serveAsset` gives on the old app host); a refused path gets the 404. Setting off is today's 404 byte for byte.
- [ ] **Why a hook and not the catch-all route.** The catch-all `/*` route (`app.ts:806-818`) runs last. `/health` (`:413-415`), `/start` and `/callback` (`:440-470`), `/connections/*` and `/_csp-report` register before it and answer on any non-app host, so on a legacy host `/health` would return platform JSON instead of redirecting to the app's `/health`, and the redirect "for every non-`_` path" would be false. The redirect therefore runs in an `onRequest` hook, registered right after the classification hook (`app.ts:371-373`), which sees every route.
- [ ] **Telemetry ships with it** (edge rule in `FESTIVAL_RULES.md`; names are constants in `packages/shared/src/telemetry.ts`):
  - `INSTR_LEGACY_APP_REDIRECTS = "helix.edge.legacy_app_redirects"`, a counter with one attribute, `ATTR_OUTCOME`, from a bounded vocabulary `LEGACY_REDIRECT_OUTCOMES = ["redirected", "unknown_app", "refused_path"]`. No host, path, slug or app id. This is the sunset signal: when it reaches zero for a chosen period, the operator turns the setting off.
  - `unknown_app` covers unknown, archived, nothing-live, mode-disallowed and registry-not-loaded. `refused_path` covers a path that starts with `_`, fails `validateReturnPath`, or a non-GET/HEAD request (the design lists only three outcomes; a method refusal is a shape refusal and is still use of an old URL, which is what the signal measures).
  - A root span `SPAN_LEGACY_APP_REDIRECT = "helix.edge.legacy_app_redirect"` with attributes `http.route` (`ROUTE_LEGACY_APP_REDIRECT = "/*"`) and, once the app is resolved, `ATTR_APP_ID`. No URL attributes: do not use `spanUrlAttributes`. It must be a fresh root (`withRootSpan` sets `root: true`), never continuing an inbound `traceparent`.
  - Check the new names against everything already in the file: the spend sequence added `INSTR_GATEWAY_ADMISSION_DENIED`, `INSTR_GATEWAY_CUT_CHARGES`, `INSTR_GATEWAY_PLATFORM_SPEND_RATIO`, `INSTR_EGRESS_UPSTREAM_ABORTS`, `ATTR_USAGE_BASIS`; the CSP sequence added `INSTR_CSP_REPORTS`, `ATTR_CSP_DIRECTIVE`, `ATTR_CSP_DISPOSITION`. `packages/shared/src/telemetry.test.ts:41` fails on duplicate values.
- [ ] Per-install: the setting is a Bicep parameter in CT-9 (`legacyAppRedirect`, default false). The strict value (off) is the default.
- [ ] Depends on: `02_ct5_edge_control_and_apps_domain_split.md` (`controlDomain`, `controlOrigin`, the split fixtures and the three-argument `classifyHost`). CT-8 changes only the edge and shared telemetry.

## Implementation

Line numbers are at commit 792557a of `projects/helix`. CT-2, CT-3 and CT-5 shift them; search for the symbol and re-read the file first.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-8-legacy-app-host-redirect`.

2. Read first: `apps/edge/src/routing/hosts.ts` (as CT-5 left it); `app.ts:100-135` (`isReservedAppPath`), `:150`, `:368-373` (the classification hook), `:410-440` (`/health`), `:806-830` (catch-all, 404 and 405 handlers); `serving/assets.ts:55-90` (the 404/410/403 ladder the old app host answers with); `auth/validate.ts:30-50` and `:227` (`visibilityModeAllowed`); `telemetry.ts` in the edge (`instruments()` at `:95`, `withRootSpan`, `spanRoute`); `serving/visits.ts:163` (a counter with `ATTR_OUTCOME`); `routing/connectionStatus.ts:72` (setting an attribute on the active span after the fact); `packages/shared/src/telemetry.ts:27-54`, `:119-145` and `:232-246` (names, span names, the `VISIT_RECORD_OUTCOMES` vocabulary pattern); `packages/shared/src/telemetry.test.ts:24-82`.

3. Shared telemetry (`packages/shared/src/telemetry.ts`). Add the counter beside `INSTR_APP_VISITS` (`:40`), the span name beside `SPAN_AUTH_COMPLETE` (`:131`), the route beside the other `ROUTE_*` constants (`:169-186`), and the vocabulary beside `VISIT_RECORD_OUTCOMES` (`:245`):
   ```ts
   export const INSTR_LEGACY_APP_REDIRECTS = "helix.edge.legacy_app_redirects";
   export const SPAN_LEGACY_APP_REDIRECT = "helix.edge.legacy_app_redirect";
   export const ROUTE_LEGACY_APP_REDIRECT = "/*";

   /**
    * What the edge did with a request to an old `<slug>.<controlDomain>` host — the
    * `helix.edge.legacy_app_redirects` dimension. When `redirected` stays at zero
    * for the operator's chosen period, the redirect can be turned off.
    * - `redirected`: a 307 to the app's new origin.
    * - `unknown_app`: unknown, archived, nothing live, mode not permitted, or the
    *   registry not loaded; all answer 404 and none is told apart.
    * - `refused_path`: a path that starts with `_` or fails return-path validation,
    *   or a method other than GET/HEAD; answered with 404.
    */
   export const LEGACY_REDIRECT_OUTCOMES = ["redirected", "unknown_app", "refused_path"] as const;
   export type LegacyRedirectOutcome = (typeof LEGACY_REDIRECT_OUTCOMES)[number];
   ```
   In `telemetry.test.ts`, add the vocabulary to the "bounded dimensions" test (`:62`) in the same way the existing vocabularies are checked (read how it handles `VISIT_RECORD_OUTCOMES`): non-empty, no duplicates, and exactly the three values.

4. Edge telemetry (`apps/edge/src/telemetry.ts`). Add `legacyAppRedirects: Counter;` to `EdgeInstruments` (`:55-72`, with a one-line doc comment: `outcome` ∈ `LEGACY_REDIRECT_OUTCOMES`) and the instrument in `instruments()` (`:95-135`) after `appVisits`:
   ```ts
   legacyAppRedirects: meter.createCounter(INSTR_LEGACY_APP_REDIRECTS, {
     description:
       "Requests to an old <slug>.<control domain> host while the legacy redirect is on, by outcome. " +
       "No host, path or slug is recorded: this is the signal that says when to turn the redirect off.",
   }),
   ```

5. `config.ts`. Add `legacyAppRedirect: boolean` to `EdgeConfig` (not to `GatewayConfig`; the dev-gateway serves no apps) with a comment on the split-only effect. In `loadConfig`'s returned object, next to `allowPasswordApps`:
   ```ts
   // Allow-polarity, default off. Meaningful only in the split layout; with one domain the old and
   // new hosts are the same host, so the flag is forced off rather than left to confuse the log.
   legacyAppRedirect: env.EDGE_LEGACY_APP_REDIRECT === "true" && gateway.controlDomain !== gateway.baseDomain,
   ```
   (`loadConfig` spreads `loadGatewayConfig(env)`; compute it once into `gateway` first.) Add `legacyAppRedirect: false` to the full-config fixtures CT-5 touched: `test/config.ts` (`testEdgeConfig`), `app.test.ts:14`'s `testConfig` and `serving/cspReport.test.ts:12`'s `testConfig`. Add `legacyAppRedirect` to the `boot.serving` log in `server.ts` (CT-5 added `controlDomain` and `split` there).

6. `routing/hosts.ts`. Extend `HostClass` and `classifyHost`:
   ```ts
   export type HostClass =
     | { kind: "app"; slug: string }
     | { kind: "legacy-app"; slug: string }
     | { kind: "auth" }
     | { kind: "platform" };

   export function classifyHost(host, baseDomain, controlDomain = baseDomain, legacyAppRedirect = false): HostClass {
     // ... apps suffix and exact auth.<controlDomain> exactly as CT-5 left them ...
     const controlSuffix = `.${controlDomain}`;
     if (legacyAppRedirect && controlDomain !== baseDomain && host.endsWith(controlSuffix)) {
       const label = host.slice(0, -controlSuffix.length);
       if (!label.includes(".") && SLUG_PATTERN.test(label) &&
           !RESERVED_SUBDOMAINS.has(label) && label !== "dev-api") {
         return { kind: "legacy-app", slug: label };
       }
     }
     return { kind: "platform" };
   }
   ```
   Every existing call passes three or fewer arguments, so behavior is unchanged. Check the `kind` comparisons across the edge: `grep -rn "hostClass.kind\|HostClass" apps/edge/src --include='*.ts'`. Each handler tests `=== "app"` or `=== "auth"` and treats anything else as platform, so `legacy-app` falls through to 404 everywhere except the new hook. Confirm that for each one rather than assuming. `app.ts:372` passes `config.legacyAppRedirect` as the fourth argument.

7. The hook, in `app.ts` right after the classification hook (`:371-373`). Put the logic in a small module, `apps/edge/src/routing/legacyRedirect.ts`, so `app.ts` gains one registration, and keep the same imports style as `routing/connectionStatus.ts`:
   ```ts
   export function makeLegacyRedirectHook(deps: { config: EdgeConfig; registry: RegistryReader }) {
     return async function legacyRedirect(req: FastifyRequest, reply: FastifyReply): Promise<void> {
       if (req.hostClass.kind !== "legacy-app") return;
       const slug = req.hostClass.slug;
       await withRootSpan(SPAN_LEGACY_APP_REDIRECT, { "http.route": ROUTE_LEGACY_APP_REDIRECT }, async (span) => {
         const outcome = decide(req, slug, deps);          // pure: returns { outcome, target? }
         // appId only once the registry resolved the slug; never the slug, host or path.
         instruments().legacyAppRedirects.add(1, { [ATTR_OUTCOME]: outcome.kind });
         span.setAttribute(ATTR_OUTCOME, outcome.kind);
         if (outcome.kind === "redirected") {
           span.setAttribute(ATTR_APP_ID, outcome.appId);
           reply.header("cache-control", "no-store").header("referrer-policy", "no-referrer").redirect(outcome.target, 307);
         } else {
           sendNotFound(reply);
         }
       }, { reply });
       return reply; // end the request here; later routes must not run
     };
   }
   ```
   `decide` implements the rules in Requirements in this order: method (GET and HEAD only, else `refused_path`), path (`normalizeRequestPath(req.raw.url)` non-null and first segment not starting with `_`, also check the raw path for a leading `/_` because the decoded form of `%5F` must not slip past; and `validateReturnPath(req.raw.url)` non-null; else `refused_path`), registry loaded, `getApp(slug)`, not archived, `blobPrefix` non-null, `visibilityModeAllowed` (else `unknown_app`), then the target `` `${publicOrigin(config, slug)}${validated}` `` with `validated` being the string `validateReturnPath` returned. Use `sendNotFound` from wherever `app.ts` imports it. No existing hook in the edge short-circuits a request (`app.addHook(` appears at `app.ts:371`, `routing/trustProxyHealth.ts:162` and in the dev-gateway, and they only observe or set fields). Returning the `reply` from an async hook after sending is Fastify's documented way to stop the lifecycle; prove it with the test that `/health` on a legacy host answers 307 and not the health JSON. Register it only when `config.legacyAppRedirect` is true, so the off path adds no code to the request path at all.

8. Tests, all in `apps/edge/src`:
   - `routing/hosts.test.ts`: `classifyHost` with the fourth argument: `demo.<control>` is `legacy-app` (slug `demo`) when enabled and `platform` when not; `auth.<control>` is still `auth`; `portal.`, `api.`, `www.`, `dev-api.` and a two-label host under the control suffix are `platform`; a host under the apps suffix is still `app`; in the parent-of-apps layout `x.apps.<control>` is `app`, not `legacy-app`; with `controlDomain === baseDomain` the fourth argument changes nothing.
   - `routing/legacyRedirect.test.ts` (new; build the edge with `buildApp` and `splitEdgeConfig({ legacyAppRedirect: true })`, fakes from `test/fakes.ts`: `FakeRegistry` and `registryEntry({ slug, blobPrefix })`, as `serving/visits.test.ts` does):
     - GET `/page?x=1` on a live `demo.<control>` gives `307`, `Location` exactly `https://demo.<apps>:8080/page?x=1`, `cache-control: no-store`, `referrer-policy: no-referrer`; HEAD does the same; `/` and `/health` also redirect (the hook runs before the platform routes);
     - POST, PUT and DELETE are not redirected and get 404, and are counted `refused_path`;
     - `/_auth/complete?token=x`, `/_api/me`, `/_helix/sw.js`, `/_csp-report`, `/_anything`, and `/%5Fapi/me` and `/_api%2fme` (encoded forms) are not redirected (404, `refused_path`);
     - `//evil.example/x` (as the request target), `/\evil.example` and a path with a control character are not redirected;
     - unknown slug, archived slug, a slug with `blobPrefix: null`, a `public` app when `allowPublicApps` is false, and a registry with `loaded: false` all get an identical 404 body, and the response never differs in status between them; each is counted `unknown_app`;
     - the `Location` host is always `<apps>`: send a hostile `Host`-adjacent header set (`X-Forwarded-Host: evil.example`, `Origin`) and assert it makes no difference;
     - setting off (`legacyAppRedirect: false`): the same request on `demo.<control>` is the plain 404 and the counter does not move;
     - single-domain config with the setting forced on in the env (`loadConfig`): `legacyAppRedirect` is false (add this one to `config.test.ts`, with the env-parse cases: unset, `"true"`, `"TRUE"`, `"1"`, blank).
   - Telemetry in the same file, with `startRecordingTelemetry()` (pattern at `serving/visits.test.ts:247-266`): after one `redirected` and one `unknown_app`, `recording.metrics()` has `INSTR_LEGACY_APP_REDIRECTS` points whose attribute keys are exactly `["helix.outcome"]` and values within `LEGACY_REDIRECT_OUTCOMES`.
   - `spanRedaction.test.ts`: add a case that sends the redirect request with `?token=<secret-looking value>&code=<another>` and a distinctive slug, then scans every attribute of every span (the file's own technique at `:74-86`) and asserts neither the query values, the host, the slug nor the path appear, and that the only attribute keys are `http.route`, `helix.outcome` and `helix.app_id`.
   - `traceBoundary.test.ts`: add a case in the style of the consent-start route cases (`:166-213`): an inbound `traceparent` never parents the `helix.edge.legacy_app_redirect` span (`parentSpanContext` undefined, trace id differs).
   - `packages/shared/src/telemetry.test.ts`: as in step 3.

9. Docs: `docs/features/observability.md` instrument table (the row for `helix.app.visits` is the template, at about `:199`): add `helix.edge.legacy_app_redirects | counter | outcome (redirected / unknown_app / refused_path; when redirected stays at zero for your chosen period, turn EDGE_LEGACY_APP_REDIRECT off)` and the span in the span table if the file keeps one. The setting's own documentation and the sunset runbook are CT-10. Code comments explain constraints only (why a hook, why `_` anything, why 404 not 410); no change IDs.

10. Run from the dev container: `./check-and-lint.sh`, then `just dev smoke` (single-domain; the new code is off and unregistered, so it must be unchanged).

## Done When

- [ ] All requirements met.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just dev smoke` passes (single-domain, unchanged).
- [ ] With the flag on, GET and HEAD to `<slug>.<controlDomain>` for a live permitted app get a `307` with `no-store` to the same path and query on the apps origin; `_`-prefixed paths (including encoded forms), other methods, unknown, archived, nothing-live and mode-disallowed slugs, and a not-loaded registry never redirect; with the flag off the response is today's 404. Each is asserted in `routing/legacyRedirect.test.ts`.
- [ ] `INSTR_LEGACY_APP_REDIRECTS` counts `redirected`, `unknown_app` and `refused_path` with only the outcome attribute; `spanRedaction.test.ts` with a `?token=` request and `traceBoundary.test.ts` pass; `observability.md` lists the instrument.
- [ ] `results/` records: the names checked against the earlier sequences' constants, the decision that `dev-api` is never a legacy label, and that the method refusal is counted under `refused_path`.
- [ ] Not verified here: retiring the redirect on a live install (an operator step, driven by the counter), and how browsers and caches treat the 307 chain across the two domains (CT-7 covers Chromium only). No Azure behavior is involved.
- [ ] Committed with `fest commit -m "CT-8: optional legacy redirect from old app hosts"`.