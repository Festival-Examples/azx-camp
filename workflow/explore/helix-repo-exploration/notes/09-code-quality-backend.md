# Backend code quality and architecture

_Reviewer:_ cursor-agent (`composer-2.5`, read-only ask mode) on `main` at `792557a`. The coordinator re-opened the evidence for CQ-1, CQ-3, CQ-6, CQ-8 and it matched.

_Scope:_ `apps/edge`, `apps/portal`, `apps/egress`, and `packages/shared`, `packages/secret-store`, `packages/directory`, `packages/telemetry` on `main` @ 792557a. _Method:_ Read `eslint.config.mjs`, package manifests, server/error/pool/proxy paths, ADR-0007, representative hotspots; `find`/`wc` for largest files; `find … '*.test.ts' | wc -l` for test count (186 files).

## Summary

The three-plane split is real in dependencies and runtime roles: the edge ships without Prisma or `secret-store` in production deps (`apps/edge/package.json:13-22`), egress is the only plane that combines `secret-store` with outbound proxying (`apps/egress/package.json:11-21`, `apps/egress/src/app.ts:104-117`), and the portal owns Prisma and registry writes (`apps/portal/package.json:21-40`). Enforcement goes beyond convention: ESLint bans raw RLS-table SQL and bare `pool.connect()` on the edge, blocks `propagation.extract` on edge/portal, and confines the OTel SDK to `server.ts` plus `@azx-pbc/telemetry` (`eslint.config.mjs:117-279`). Error handling is deliberately uniform and security-aware on all three Fastify apps. The main staff-level gaps are maintainability hotspots (900-line config and 800-line route modules), a documented transparent-proxy credential echo residual on egress, coarse static RLS lint instead of typed encapsulation, and portal authorization that stops at owner-or-admin rather than full RBAC.

## What already meets the bar

- **Plane separation in dependencies:** Edge runtime deps are `shared`, `telemetry`, `fastify`, `jose`, `openid-client`, `pg`, `undici`, `zod` only (`apps/edge/package.json:13-22`). Egress adds `secret-store` (`apps/egress/package.json:11-21`). Portal adds Prisma, Azure SDKs, `directory`, `secret-store` (`apps/portal/package.json:21-40`).
- **Lint-backed security boundaries:** RLS SQL and pool checkout rules on edge (`eslint.config.mjs:117-182`); telemetry URL-attribute and trace-extract rules (`eslint.config.mjs:54-66`, `191-200`); OTel SDK import ban outside `server.ts` (`eslint.config.mjs:231-279`).
- **Least-privilege data access on the edge:** `withPartition` sets RLS GUCs via parameterized `set_config` inside a transaction (`apps/edge/src/db/partition.ts:32-58`). `role-split.integration.test.ts` exercises `helix_edge` grants (grep hit at `apps/edge/src/registry/role-split.integration.test.ts:40`).
- **Portal runtime DSN guard:** Production refuses owner `DATABASE_URL` without `PORTAL_DATABASE_URL` (`apps/portal/src/db/client.ts:21-31`).
- **Opaque error surfaces toward untrusted callers:** Edge `edgeErrorHandler` with adversarial tests (`apps/edge/src/errors.ts:125-164`, `apps/edge/src/errorHandler.test.ts:43-56`). Egress fixed 500 body (`apps/egress/src/app.ts:104-117`). Portal `ApiError` envelope (`apps/portal/src/plugins/errors.ts:78-117`).
- **Graceful shutdown contract:** Shared `installGracefulShutdown` with hard deadline; edge wires pools, registry, telemetry on `onClose` (`packages/shared/src/lifecycle.ts:79-130`, `apps/edge/src/server.ts:294-300`).
- **Streaming and resource caps on egress:** `capBody` on request/response, undici `headersTimeout`/`bodyTimeout`, streamed `reply.send(cappedBody)` (`apps/egress/src/proxy.ts:592-692`, `apps/egress/src/proxy.ts:272-274`).
- **Test depth:** 186 `*.test.ts` files under scope; 23 `*.integration.test.ts` files repo-wide including edge role-split/RLS, egress renewal/retire/delegated, portal OIDC/callback/RLS; dedicated adversarial suites under edge auth, egress, and shared providers.
- **`secret-store` zero runtime dependencies:** `packages/secret-store/package.json` lists only `typescript` under `devDependencies` (lines 12-14).

## Findings

### CQ-1 Monolithic modules concentrate routing and config
- **Severity:** Medium **Status:** Confirmed **Area:** Maintainability
- **What:** Several modules mix boot wiring, policy, and handlers at high line count.
- **Evidence:** Largest non-test edge sources: `config.ts` (902 lines), `app.ts` (832), `gateway/data-handler.ts` (794) — `find apps/edge/src … | sort -n | tail`. Portal: `routes/providers.ts` (1007 lines) — same command on `apps/portal/src` excluding `db/generated`.
- **Why it matters:** Onboarding and safe refactors slow when a single file owns env parsing, host classification, and gateway registration together.
- **Recommendation:** Extract submodules along existing seams (config domains, `buildApp` route groups, provider route facets) without changing behavior; add ownership notes in `TOUR.md` or feature docs.

### CQ-2 ESLint RLS enforcement is coarse (store-module allowlist)
- **Severity:** Medium **Status:** Confirmed **Area:** Architecture / safety
- **What:** RLS-table SQL is allowed only in three store files; the rule does not prove each query runs inside `withPartition`.
- **Evidence:** `eslint.config.mjs:118-128` documents “Option A” and defers stronger encapsulation; ignores list at `eslint.config.mjs:136-147`.
- **Why it matters:** A new query inside an allowed file but outside `withPartition` fails closed at runtime yet passes CI—a silent correctness bug class the comment itself names.
- **Recommendation:** Track the deferred pool encapsulation; until then, require `withPartition` in code review for any change to `gateway/data.ts`, `gateway/usage.ts`, or `auth/sessions.ts`.

### CQ-3 Documented egress body echo residual (transparent proxy)
- **Severity:** Medium **Status:** Confirmed **Area:** Security
- **What:** Injected credentials are stripped from response headers, but an upstream that echoes secrets in the body still streams to the app.
- **Evidence:** `apps/egress/src/proxy.ts:676-679` (“accepted transparent-proxy residual”).
- **Why it matters:** Production operators and app authors need to treat vendor APIs that reflect request material as out of scope for Helix’s header stripping.
- **Recommendation:** Keep in operator docs and connection-provider review; consider response scanning only if product accepts false positives and latency cost (would be an ADR).

### CQ-4 Fire-and-forget gateway metering on hot paths
- **Severity:** Low **Status:** Confirmed **Area:** Reliability / observability
- **What:** Some denials record usage with `void usage.record(...).catch(log)` so the HTTP response is not blocked on ledger I/O.
- **Evidence:** `apps/edge/src/gateway/fetch.ts:211-230` (allowlist denial); similar pattern at `apps/edge/src/gateway/fetch.ts:265-279` for quota.
- **Why it matters:** Under DB pressure, ledger rows can lag or drop while metrics counters still fire—by design per comments, but ops cannot reconcile `gateway_calls` to HTTP logs one-to-one.
- **Recommendation:** Document as intentional in `docs/features/` metering section; alert on sustained `gateway usage record failed` warn rate.

### CQ-5 Dual connection surfaces (prod edge vs dev-gateway)
- **Severity:** Medium **Status:** Confirmed **Area:** Consistency
- **What:** Production connection consent flows live under `apps/edge/src/routing/`; dev-mode parallels under `apps/edge/src/devGateway/` (nine TS files including separate `consentStart.ts` and `app.ts`).
- **Evidence:** `apps/edge/src/routing/consentStart.ts` (~430 lines per `wc`); `apps/edge/src/devGateway/consentStart.ts` imports shared `callConsult` but defines dev-specific handler (`apps/edge/src/devGateway/consentStart.ts:1-29`). Fourth instrumented `server.ts` called out in `eslint.config.mjs:239-241`.
- **Why it matters:** Fixes to consent or connection status may need duplicate changes; drift is easy to miss without journey tests.
- **Recommendation:** Keep `connectionsJourney.integration.test.ts` mandatory for connection changes; consider shared inner core extracted from both handlers.

### CQ-6 Stale milestone comments in edge `app.ts`
- **Severity:** Low **Status:** Confirmed **Area:** Onboarding
- **What:** Module docblock still says sessions/OIDC and `/_api/*` “come later” though they are implemented.
- **Evidence:** `apps/edge/src/app.ts:66-67` vs imports for LLM, data, fetch at `apps/edge/src/app.ts:33-37`.
- **Why it matters:** New contributors misread maturity of the data plane.
- **Recommendation:** Refresh the docblock to current M4/M4.5 scope.

### CQ-7 `REGISTRY_CHANNEL` not centralized in `@azx-pbc/shared`
- **Severity:** Low **Status:** Confirmed **Area:** Consistency
- **What:** `PROVIDERS_CHANNEL` is exported from shared; registry notify channel literal lives only in the edge listener.
- **Evidence:** `packages/shared/src/connections.ts:120-125` notes duplication with `apps/edge/src/registry/listener.ts:29`; `LISTEN` at `apps/edge/src/registry/listener.ts:328`.
- **Why it matters:** Migration/listener drift if the string changes in SQL but not TypeScript.
- **Recommendation:** Export `REGISTRY_CHANNEL` from shared (with migration comment) mirroring `PROVIDERS_CHANNEL`.

### CQ-8 Portal authorization stops at owner-or-admin
- **Severity:** High **Status:** Confirmed **Area:** Authorization (product)
- **What:** App-scoped routes use `ownsApp` (owner or platform-admin); fine-grained owner/editor/viewer RBAC is explicitly deferred.
- **Evidence:** `apps/portal/src/plugins/auth.ts:22-24`, `235-255`; ADR-0007 resolution at `docs/adr/0007-portal-authz-v0.md:35-51` states BOLA on app-scoped resources is closed but “full owner/editor/viewer RBAC remains the v1 item.”
- **Why it matters:** Multi-owner teams cannot delegate editor access without sharing ownership or admin group membership—acceptable for pilot, not for general customer portal.
- **Recommendation:** Treat per-app RBAC as a production gate for multi-tenant portal; until then, restrict portal audience operationally.

### CQ-9 Empty `catch` blocks only in browser-injected serving scripts
- **Severity:** Low **Status:** Confirmed **Area:** Error handling
- **What:** Service worker / shim templates swallow errors in generated client-side code.
- **Evidence:** `apps/edge/src/serving/shim.ts:55`, `apps/edge/src/serving/serviceWorker.ts:138`, `272`, `326`, `369`, `426`; `apps/edge/src/serving/connectHelper.ts:109`, `239`.
- **Why it matters:** Not server-side swallowing; intentional so one bad cache op does not break the SW. Server handlers use structured logging instead.
- **Recommendation:** No change required; document that these files are emitted script sources, not Node request paths.

### CQ-10 `packages/directory` and `secret-store` lack live-cloud integration tests
- **Severity:** Medium **Status:** Hypothesis **Area:** Tests
- **What:** Unit tests exist (`secret-store`: 3 test files; `directory`: 2); no `*.integration.test.ts` under those packages in repo search.
- **Evidence:** Glob under `packages/secret-store` and `packages/directory`; portal uses `EntraDirectory` at runtime (`apps/portal/package.json:25`).
- **Why it matters:** Key Vault REST and Graph error shapes (throttling, auth expiry) are mostly exercised via mocks; production regressions may surface first in deploy.
- **Recommendation:** Optional staged integration job against a disposable vault/app registration, or contract tests from recorded fixtures with strict schema validation.

## Missing for production / staff-level quality

- **Continuous automated gate on merge:** Repository policy (manual CI dispatch) is outside this tree review; a staff team still needs a enforced pre-merge `./check-and-lint.sh` habit—code quality assumes it runs, not that CI enforces it.
- **Per-app portal RBAC:** Documented v1 gap (CQ-8); required before handing the portal to unrelated app owners at scale.
- **Structural RLS encapsulation:** ESLint Option A is explicit stopgap (`eslint.config.mjs:118-128`); typed partition client that cannot query without GUC would reduce reliance on reviewer vigilance.
- **Backend architecture map beyond file size:** `TOUR.md` helps, but no generated dependency graph or “change X → touch Y” guide for gateway vs auth vs registry—worth adding as the team grows.
- **Operational reconciliation story for async metering:** Fire-and-forget ledger writes (CQ-4) need dashboard/alert ownership documented for on-call.

## Open questions

- Is the portal’s intended production audience still “single operator / small trusted group,” or multi-tenant owners on day one? That decision determines whether CQ-8 blocks sign-off independent of code quality.
- Are dev-gateway journey tests considered sufficient parity with prod edge for M4.5 connections, or is a second Playwright lane against prod routing required?
- Will production always set `PORTAL_DATABASE_URL` and edge role DSNs separately, or can a misconfigured deploy still fall back to owner URLs outside `NODE_ENV=production` in any hosting path?
