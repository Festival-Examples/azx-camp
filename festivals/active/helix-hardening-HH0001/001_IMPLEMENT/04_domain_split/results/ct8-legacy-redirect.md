# CT-8 result: legacy app-host redirect

**Result: done.** `EDGE_LEGACY_APP_REDIRECT` is parsed strictly (`=== "true"`) and defaults to off. It only takes effect in the split layout; with one domain the effective value is `false`. The effective value is logged in `boot.serving`.

`classifyHost` gains a fourth argument and a `legacy-app` kind for `<slug>.<control>` when the redirect is enabled. The order is: apps suffix, exact `auth.<control>`, then a single valid non-reserved label under the control suffix (never `dev-api`), else `platform`.

The redirect is an `onRequest` hook (`apps/edge/src/routing/legacyRedirect.ts`), registered after classification. A hook sees every route, so `/health` on a legacy host redirects to the app's `/health` instead of answering platform JSON.

**When it redirects**, all of these must hold:
- the method is GET or HEAD;
- the path does not start with `_`, checked raw, percent-encoded (`%5F`) and normalized;
- the path passes `validateReturnPath`;
- the registry is loaded;
- the app is live: known, not archived, and with a deployed version;
- its visibility mode is allowed.

**What it sends:** a 307 to `publicOrigin(config, slug)` plus the validated path, with the query kept and the host never taken from the request, plus `cache-control: no-store` and `referrer-policy: no-referrer`. No session transfers, so visitors sign in again on the new host.

**Everything else** gets the plain 404 an unknown host gets. Archived and unknown apps are not distinguished.

**Telemetry:**
- Counter `helix.edge.legacy_app_redirects`, whose only attribute is `helix.outcome`: `redirected`, `unknown_app`, or `refused_path` (a refused method counts here). This is the sunset signal.
- Root span `helix.edge.legacy_app_redirect` with `http.route=/*`, `helix.outcome`, and `helix.app_id` on a redirect only. No URL, host, path or slug attribute.
- `spanRedaction.test.ts` and `traceBoundary.test.ts` are extended. Both are listed in `docs/features/observability.md`.

**Smoke:** the split stack runs with `EDGE_LEGACY_APP_REDIRECT=true`, and the `split` group checks that a control-host app URL gets a 307 to the apps origin. The single-domain smoke is unchanged.

## Evidence (coordinator)

- **Gate:** `./check-and-lint.sh`, 242 of 242 test files, 3667 tests.
- **Adversarial suites with `OTEL_SDK_DISABLED=1`** (`spanRedaction`, `traceBoundary`, egress `spanAttributes`, `legacyRedirect`): 4 files, 57 tests.
- **Smoke with a real browser:** single-domain 37 of 37; split 47 of 47, including "legacy control host redirects to apps origin → `https://smoke-internal.helix-apps.localhost:9080/`".
- **Connections lane, split:** 10 of 10 (`ct8-gate.txt`).
- **Tests (`legacyRedirect.test.ts`):**
  - GET/HEAD 307 with the headers;
  - POST, PUT and DELETE → 404 counted as `refused_path`;
  - `_` and encoded paths refused;
  - an identical 404 for every `unknown_app` case;
  - a hostile `X-Forwarded-Host` is ignored;
  - flag off is today's 404;
  - `/health` on a legacy host redirects;
  - counter dimensions.
- **Classification tests (`hosts.test.ts`):** `dev-api` and reserved labels are never legacy apps, and `demo.apps.<control>` is not one either.

## Unverified

Turning the redirect off from counter data on a real install, browser cache behavior across the two domains, and the Bicep parameter (CT-9).

## Executor

cursor-agent, `composer-2.5`, 132 tool calls.
