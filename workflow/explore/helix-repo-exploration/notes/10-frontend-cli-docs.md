# Frontend, CLI, and documentation

_Reviewer:_ cursor-agent (`composer-2.5`, read-only ask mode) on `main` at `792557a`. The coordinator re-opened the evidence for FE-1, FE-2, FE-4, FE-6, FE-11 and it matched.

_Scope:_ `apps/portal-web`, `packages/cli`, `packages/deploy-skill`, `examples/`, `apps/docs`, and contributor `docs/` (read-only). _Method:_ Read architecture and feature docs, SPA routing/auth/API layers, CLI entrypoints and auth, example READMEs, public docs pages, and spot-checks against source; no installs, builds, tests, or network.

## Summary

The portal SPA is a coherent React 19 application: React Router, TanStack Query, Mantine, zod-validated API client, runtime topology from `GET /api/v1/config` (no `VITE_*` domain leakage), and OIDC PKCE with session-gated UI. Vitest/jsdom coverage is broad across tabs, admin surfaces, deploy flows, and auth guards—closer to integration-style component tests than smoke tests. The `helix` CLI is small, schema-aligned with the portal API, and ships sensible token handling (portal-origin binding, 0600 cache, static-token path for CI). Examples and dual doc trees (VitePress for operators/authors, `docs/` for contributors) are a real onboarding asset, but several indexes lag the repo (oauth-demo, github-report, published CLI), examples are not gated in CI, and the root README still labels the product alpha while claiming Azure M5—documentation debt a new team would hit immediately. Nothing in this slice is a Critical security hole; the gaps are maintainability, doc accuracy, and production UX hardening (error boundaries, 404 routing, optional perf/a11y/e2e).

## What already meets the bar

- **Runtime config instead of build-time hosts:** `useDeployment()` documents and implements `GET /api/v1/config` with explicit rejection of `window.location` for app URLs (`apps/portal-web/src/lib/deployment.ts:32-48`, `100-102`); apps-list tests assert non-dev domains to guard the production-host bug (`apps/portal-web/src/test/apps-list.test.tsx:12-17`). No `VITE_` env usage in portal-web (grep over `apps/portal-web`).
- **Auth model matches the API:** `AuthProvider` gates on token + `/api/v1/me`, clears stale tokens on 401 (`apps/portal-web/src/auth/AuthProvider.tsx:92-99`), `RequireAuth` / `RequireAdmin` mirror server roles (`apps/portal-web/src/auth/guards.tsx:51-96`), browser tokens in `sessionStorage` with expiry (`apps/portal-web/src/auth/tokenStore.ts:1-42`), OIDC code+PKCE with portal API audience (`apps/portal-web/src/auth/oidc.ts:4-10`, `21-23`).
- **API boundary discipline:** Shared zod parsing and typed `PortalApiError` on every fetch (`apps/portal-web/src/api/client.ts:5-56`).
- **Route map is complete and documented:** `App.tsx` wires workspace, app detail, connections, usage, and admin routes with registry redirect (`apps/portal-web/src/App.tsx:27-51`); behavior is spelled out in `docs/features/portal-web.md`.
- **Automated UI coverage is substantive:** 36 Vitest files under `apps/portal-web/src` (glob), including guards, apps list (sort/`aria-sort`), deploy modal, access transition matrix, capabilities, connections disconnect `role="status"`, and provider import/export combobox a11y patterns in tests.
- **CLI UX and safety:** Clear usage (`packages/cli/src/bin.ts:21-37`), typed errors with portal codes (`packages/cli/src/client.ts:148-155`), explicit “run `helix login`” when unauthenticated (`packages/cli/src/client.ts:126-128`), token cache version 2 keyed by portal origin with 0600 writes (`packages/cli/src/auth/tokenStore.ts:6-13`, `89-96`), device login + `whoami`/`skill` commands (`packages/cli/src/commands.ts:169-223`). Published package at `0.4.0` with engines and npm release workflow (`packages/cli/package.json:1-24`, `.github/workflows/release-cli.yml:1-31`).
- **Author onboarding path exists:** In-app `HelpModal`, deploy skill template, and `GET /api/v1/skill` pipeline documented in `docs/features/onboarding.md`; public CLI guide at `apps/docs/src/apps/cli.md` matches the monorepo CLI README on resolution order and deploy/promote flow.
- **Examples are intentionally representative:** Standalone Vite apps with committed `dist/` for deploy-without-build (`examples/README.md:27-32`), covering gateway, CSP approval, fetch-proxy, OAuth, offline, and data concurrency (`examples/README.md:13-25`); per-app READMEs (e.g. `examples/oauth-demo/README.md:16-31`) document multi-process dev prerequisites.

## Findings

### FE-1 Unknown routes fall through to the apps list
- **Severity:** Low **Status:** Confirmed **Area:** portal-web / routing
- **What:** A non-existent path renders `AppsListPage` instead of a 404 or dedicated not-found view.
- **Evidence:** `apps/portal-web/src/App.tsx:51` — `<Route path="*" element={<AppsListPage />} />`.
- **Why it matters:** Broken bookmarks and mistyped URLs look like an empty or filtered registry; harder to debug and worse for support.
- **Recommendation:** Replace the catch-all with a not-found route (or redirect only for known legacy paths like `/admin/registry`).

### FE-2 No React error boundary
- **Severity:** Medium **Status:** Confirmed **Area:** portal-web / resilience
- **What:** An uncaught render error can white-screen the entire portal; there is no `ErrorBoundary` or router `errorElement`.
- **Evidence:** Grep over `apps/portal-web` finds no `ErrorBoundary` or `errorElement`; root tree is `main.tsx:24-38` → `App.tsx` without a boundary.
- **Why it matters:** Production UIs benefit from a recoverable failure surface; admin-heavy apps with charts and large forms increase blast radius.
- **Recommendation:** Add a top-level error boundary with “reload / contact admin” and optional error id from `reqId` if propagated.

### FE-3 No route-level code splitting
- **Severity:** Medium **Status:** Confirmed **Area:** portal-web / performance
- **What:** All app-detail tabs and admin pages are statically imported; Vite config has no `manualChunks` or `React.lazy`.
- **Evidence:** `AppDetailPage.tsx:11-17` imports every tab synchronously; `App.tsx:9-20` imports all page components; `vite.config.ts:13-39` has no chunk strategy; only incidental “lazy” comment in `ApprovalsPage.tsx:122`.
- **Why it matters:** Initial load ships Capabilities (~1006 lines, `wc -l` on `CapabilitiesTab.tsx`), provider forms, and chart stacks together—acceptable for an internal control plane today, costly as features grow.
- **Recommendation:** Lazy-load tab panels and admin routes; track bundle size in CI once a budget is chosen.

### FE-4 Stale “CLI not published” in examples README
- **Severity:** Medium **Status:** Confirmed **Area:** examples / documentation
- **What:** The examples hub still tells readers the CLI is unpublished and to use `tsx` only.
- **Evidence:** `examples/README.md:67-72` (“The CLI isn't published yet (M1)…`node --import tsx ../../packages/cli/src/bin.ts`”); `packages/cli/package.json:2-3` shows `"version": "0.4.0"` and public publish config; `apps/docs/src/apps/cli.md:8-12` documents `npm i -g @azx-pbc/helix-cli`.
- **Why it matters:** New engineers and pilot users follow `examples/` first; stale instructions undermine trust and skip the supported npm path.
- **Recommendation:** Update deploy section to prefer global `helix`, note `HELIX_PORTAL_URL` / `portalUrl`, keep tsx path as monorepo dev fallback.

### FE-5 Feature examples index omits shipped examples
- **Severity:** Medium **Status:** Confirmed **Area:** documentation
- **What:** Contributor feature doc table does not list `oauth-demo` (present in `examples/README.md`) or `github-report` (exists on disk with README).
- **Evidence:** `docs/features/examples.md:9-20` table ends at `asana-report`; no `oauth-demo` in `docs/` (grep); `examples/oauth-demo/` and `examples/github-report/README.md` exist; `examples/README.md` includes `oauth-demo` but not `github-report` (grep: no `github-report` in that file).
- **Why it matters:** OAuth and GitHub integration walkthroughs are hard to discover from the canonical feature index; `github-report` is effectively undocumented in the hub.
- **Recommendation:** Align `docs/features/examples.md`, `examples/README.md`, and root `README.md` example lists with the full directory set.

### FE-6 Public CLI docs overstate Node requirement
- **Severity:** Low **Status:** Confirmed **Area:** apps/docs
- **What:** VitePress CLI page requires Node 24+ only; the published package allows 22.12+.
- **Evidence:** `apps/docs/src/apps/cli.md:14-15` (“Node 24 or newer is required”); `packages/cli/package.json:22-24` (`"node": "^22.12.0 || >=24.0.0"`); `packages/cli/README.md:116-118` matches engines.
- **Why it matters:** Authors on Node 22 LTS may think they cannot use the CLI.
- **Recommendation:** Match `apps/docs` to `engines` in `package.json`.

### FE-7 Examples not exercised by the repo gate
- **Severity:** Medium **Status:** Confirmed **Area:** examples / CI
- **What:** `./check-and-lint.sh` does not reference `examples/` (grep: no matches).
- **Evidence:** `check-and-lint.sh` (grep for `examples`); `examples/README.md:29-32` relies on committed `dist/` without automated rebuild verification.
- **Why it matters:** Source and committed `dist/` can drift silently; example README build steps are unverified on every change.
- **Recommendation:** Add a lightweight job (build one representative example, or hash-check `dist/` after build) to CI when Actions minutes allow.

### FE-8 Complex examples need multi-service docs discipline
- **Severity:** Medium **Status:** Confirmed **Area:** examples / onboarding
- **What:** `oauth-demo` requires edge, egress, portal, idp, vendor, and vendor-TLS (`examples/oauth-demo/README.md:16-31`) plus admin API steps—far beyond hello-world—but is missing from `docs/features/examples.md` (FE-5).
- **Evidence:** As above; contrast `examples/hello-world/helix.json:1-4` (slug + dir only).
- **Why it matters:** M4.5 pilot and connections testing depend on these paths; without index visibility, teams rediscover setup by archaeology.
- **Recommendation:** Promote oauth-demo (and github-report) in feature docs with a “prerequisites” subsection linking to dev-oauth-vendor and runbooks.

### FE-9 SPA session tokens do not refresh silently
- **Severity:** Low **Status:** Confirmed **Area:** portal-web / auth UX
- **What:** Portal stores access token in `sessionStorage` without refresh; expiry forces re-login.
- **Evidence:** `apps/portal-web/src/auth/tokenStore.ts:3-5` (“No refresh token is ever stored”).
- **Why it matters:** Long-lived portal sessions may drop mid-edit; acceptable for v1 internal tool but worth documenting for operators.
- **Recommendation:** Document expected session length in `docs/features/portal-web.md` or add silent refresh if IdP issues refresh tokens to the web client (product decision).

### FE-10 Accessibility is partial, not systematic
- **Severity:** Medium **Status:** Confirmed **Area:** portal-web / a11y
- **What:** Some components use `aria-label`, `role="status"`, `role="alert"`, and tests assert `aria-sort` / combobox listboxes; there is no skip link, no documented a11y standard, and dark scheme is forced.
- **Evidence:** `apps/portal-web/src/main.tsx:29` (`forceColorScheme="dark"`); `index.html:6` (`color-scheme: dark`); grep hits in `DataTab.tsx`, `ProvidersPage.tsx`, `apps-list.test.tsx:771-785`; no “skip” link grep in portal-web.
- **Why it matters:** Enterprise customers often expect WCAG-oriented control planes; current state is “Mantine defaults + spot fixes.”
- **Recommendation:** Define a minimal a11y checklist (focus order, live regions for mutations, color contrast audit) and add one axe-core smoke in Vitest for critical pages.

### FE-11 Root README alpha banner vs deployment status
- **Severity:** Low **Status:** Confirmed **Area:** documentation / positioning
- **What:** Repository README opens with “Alpha — not yet suitable for public consumption” while `CLAUDE.md`/architecture describe Azure M5 deployment.
- **Evidence:** `README.md:3-6`; `README.md:18-24` describes Azure production and remaining M5 work.
- **Why it matters:** Staff sign-off and customer conversations need a single story on production readiness.
- **Recommendation:** Reconcile README status with `docs/platform-project-plan.md` and M5 residual (pilot app, egress firewall confirmation).

### FE-12 CLI release automation is manual-only (known ops gap)
- **Severity:** Medium **Status:** Confirmed **Area:** CLI / release
- **What:** npm publish workflow trigger on `cli-v*` tags is commented out; only `workflow_dispatch` runs.
- **Evidence:** `.github/workflows/release-cli.yml:25-31`.
- **Why it matters:** Published CLI can lag platform API changes unless someone remembers to dispatch; pairs with commented CI elsewhere.
- **Recommendation:** Document release cadence in `packages/cli/README.md` and re-enable tag trigger when Actions budget allows.

### FE-13 npm package metadata points at upstream OSS repo
- **Severity:** Low **Status:** Confirmed **Area:** CLI / fork ergonomics
- **What:** `@azx-pbc/helix-cli` `repository.url` is `AZX-PBC-OSS/helix`, not a private fork.
- **Evidence:** `packages/cli/package.json:6-9`; `Shell.tsx:56-60` hardcodes upstream GitHub links for “Source code” / “Report a bug.”
- **Why it matters:** Fork operators and internal users may file issues or clone the wrong repo.
- **Recommendation:** Fork-specific overrides via config endpoint or env (if product allows) or document fork divergence in operator docs.

## Missing for production / staff-level quality

- **Browser E2E for the portal:** Vitest/jsdom with stubbed `fetch` does not catch proxy/CORS, real OIDC redirect, or multipart deploy against a live portal. No Playwright (or similar) under `apps/portal-web`.
- **Example validation in CI:** No automated build or deploy smoke of `examples/*` despite committed `dist/` being part of the contract (`examples/README.md:29-32`).
- **Performance budgets:** No documented initial-load or chunk-size limits for the SPA baked into `apps/portal` images (`apps/portal/src/routes/spa.ts:8-27` serves static `portal-web/dist`).
- **Centralized doc freshness checks:** Contradictions (FE-4, FE-5, FE-6, FE-11) suggest no periodic “docs vs code” sweep for author-facing paths.
- **Fork/private deployment narrative:** Public docs and shell links assume AZX-PBC-OSS; a new owner on a private fork lacks a single “your URLs, your repo, your npm scope” guide beyond generic Azure Bicep README.
- **Internationalization:** Not present; fine for v1 English-only internal portal, not fine for multi-locale customers without an explicit non-goal in operator docs.

## Open questions

- Is `examples/github-report` intentionally excluded from hub tables (superseded by `asana-report`), or an documentation oversight?
- For production portal sessions, is “re-login on access-token expiry” the intended Entra experience, or is silent refresh planned for the web client?
- Will the M5 “real pilot app” be one of the existing examples, a new app, or production customer code—and should that choice drive which examples stay CI-gated?
- For the private fork, should published `@azx-pbc/helix-cli` remain tied to upstream OSS, or will there be a separately named/scoped CLI for internal deployments?
