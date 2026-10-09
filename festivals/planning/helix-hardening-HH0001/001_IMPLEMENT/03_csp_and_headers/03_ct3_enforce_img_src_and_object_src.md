---
fest_type: task
fest_id: 03_ct3_enforce_img_src_and_object_src.md
fest_name: ct3 enforce img src and object src
fest_parent: 03_csp_and_headers
fest_order: 3
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:54:29.451124-06:00
fest_tracking: true
---

# Task: ct3 enforce img src and object src

## Objective

Move the tightened policy onto the enforced `Content-Security-Policy` header (`img-src 'self' data: blob:` plus approved origins plus `EDGE_IMG_SRC_EXTRA`, and `object-src 'none'`), add the per-install relaxation `EDGE_IMG_SRC_ALLOW_ALL` that puts `https:` back in `img-src`, retire the Report-Only header, and rewrite every published statement that `img-src` is open. Implements CT-3 from 02-app-containment.md ("Part 2", second step; finding SEC-2).

## Requirements

- [ ] Depends on `02_ct2_report_only_csp_and_report_counter.md` (the `EDGE_IMG_SRC_EXTRA` setting, `imgSrcExtra` config field, `applyAppCsp` helper, the report counter and the measurement window). Do not start before CT-2 has merged and the operator has had its measurement window; the rollout notes in the design put the enforcing release after that.
- [ ] With the setting at its default, the enforced header on every app response carries `img-src 'self' data: blob:` followed by the app's approved origins and the `EDGE_IMG_SRC_EXTRA` origins, and `object-src 'none'`. `https:`, `*` and `http:` never appear in `img-src` by construction. Every other directive is unchanged.
- [ ] `EDGE_IMG_SRC_ALLOW_ALL` (default `false`, "allow" polarity, parsed with `=== "true"` like `EDGE_ALLOW_PUBLIC_APPS`) restores today's `img-src https: data: blob:` plus approved origins. `object-src 'none'` stays in force with the setting on; the setting relaxes only `img-src`.
- [ ] The `Content-Security-Policy-Report-Only` header is no longer sent in any mode. A second header that equals the enforced one adds nothing, so this also satisfies the design's "ALLOW_ALL suppresses the Report-Only duplicate". The design is worded two ways on this point (the CT-3 done-when keeps a duplicate that ALLOW_ALL suppresses; the Part 2 tests say "only the enforced header after CT-3"). Follow the second and record the choice in `results/`.
- [ ] The report counter and the sink from CT-2 stay as they are. Enforced `img-src` and `object-src` violations now arrive with disposition `enforce`.
- [ ] Failure path. An ungranted remote image is blocked and a violation report is recorded. The page itself keeps working. The Violations screen shows the report, and the existing one-click grant resolves it: `isResolved` treats an `img-src` report as resolved once the blocked origin is in the app's `externalOrigins`. An `object-src` report is never resolved by an origin grant (an origin list does not widen `object-src`).
- [ ] Failure path. A registry outage keeps serving the last committed CSP: the approval write-gate and the registry projection are unchanged by this task.
- [ ] Granting an origin still opens an elevated, admin-approved request: `packages/shared/src/approval.test.ts:112-116` passes unchanged.
- [ ] The connections consent popup still works for a hosted app under the tightened policy. The consent, completion and login pages are on the auth host with their own policies (`CONSENT_PAGE_CSP` at `apps/edge/src/serving/consentPages.ts:29` and the others) and this task does not change them. The evidence is the real-browser connections lane (`pnpm lane:connections`), not a code argument.
- [ ] `SECURITY.md`, ADR-0009, `docs/platform-architecture.md` and the agent-facing docs say what `img-src` and `object-src` are now, list the channels that stay open (top-level navigation, popups and `window.open`, any approved origin, WebRTC, DNS prefetch and preconnect hints, request URLs to permitted CDN hosts), and state that this removes the silent bulk image channel and does not deliver confidentiality. The WebRTC and DNS-hint claims are labeled untested.
- [ ] Per-install setting: an Azure install can set `EDGE_IMG_SRC_ALLOW_ALL` through a new optional Bicep parameter (default `false`). The design's file list omits `main.bicep`; record the addition in `results/` as a design gap, together with the CT-2 parameter.
- [ ] Not verified here: WebRTC ICE, DNS prefetch and preconnect behavior under CSP, and image blocking in Firefox and Safari.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b ct-3-enforce-img-src`. Start from a `main` that contains the CT-2 commit. Re-read `apps/edge/src/serving/csp.ts` as CT-2 left it (`buildPolicy`, `buildAppCsp`, `buildAppCspReportOnly`, `applyAppCsp`, `CSP_REPORT_ONLY_HEADER`) and `apps/edge/src/config.ts` (`imgSrcExtra`, `parseImgSrcExtra`). If the names differ from this document, use what CT-2 actually landed.

2. Config, `apps/edge/src/config.ts`. Add beside `imgSrcExtra` in `EdgeConfig` (that field sits after `anonRateLimit`, line 295 before CT-2):

```ts
  /**
   * EDGE_IMG_SRC_ALLOW_ALL: put `https:` back in every app's img-src. For
   * installs on the one-org model that accept the open image channel. Default
   * false (tight); object-src stays 'none' either way.
   */
  imgSrcAllowAll: boolean;
```

   In `loadConfig` (the returned object, `config.ts:820-835` before CT-2), add `imgSrcAllowAll: env.EDGE_IMG_SRC_ALLOW_ALL === "true",` next to `allowPasswordApps` (line 830), with the same "allow polarity" comment. Add `imgSrcAllowAll: false` to the three fixtures that CT-2 touched: `apps/edge/src/test/config.ts` (`testEdgeConfig`, `portalUrl: null` at line 102), `apps/edge/src/app.test.ts` (`testConfig`, line 55) and `apps/edge/src/serving/cspReport.test.ts` (`testConfig`, line 53). `pnpm typecheck` finds any full `EdgeConfig` literal you miss; `apps/connections-lane/src/world.ts:567` and `apps/edge/src/routing/connectionsJourney.integration.test.ts:818` go through `testEdgeConfig` and need nothing.

3. CSP builder, `apps/edge/src/serving/csp.ts`. Make the tight policy the only policy and give the builder the two options:

```ts
export interface AppCspOptions {
  /** Operator-trusted image origins (EDGE_IMG_SRC_EXTRA). */
  imgSrcExtra?: readonly string[];
  /** EDGE_IMG_SRC_ALLOW_ALL: restore `https:` in img-src. */
  imgSrcAllowAll?: boolean;
}

export function buildAppCsp(
  externalOrigins: readonly string[] = [],
  opts: AppCspOptions = {},
): string {
  // img-src: tight by default; `https:` only when the operator opted in. Approved
  // origins widen connect-src and img-src alike.
  const imgOrigins = originSources([...externalOrigins, ...(opts.imgSrcExtra ?? [])]);
  const imgSuffix = imgOrigins.length ? ` ${imgOrigins.join(" ")}` : "";
  const img = opts.imgSrcAllowAll
    ? `img-src https: data: blob:${imgSuffix}`
    : `img-src 'self' data: blob:${imgSuffix}`;
  // ...the rest of the list as in buildPolicy, with "object-src 'none'" after media-src
}
```

   Fold `buildPolicy` into `buildAppCsp` (or keep it private and have `buildAppCsp` call it with `tight` removed); delete `buildAppCspReportOnly`, `CSP_REPORT_ONLY_HEADER` and the `tight` option. `applyAppCsp` becomes:

```ts
export function applyAppCsp(
  reply: FastifyReply,
  externalOrigins: readonly string[],
  config: { imgSrcExtra: readonly string[]; imgSrcAllowAll: boolean },
): void {
  reply.header("content-security-policy", buildAppCsp(externalOrigins, config));
}
```

   `config` already satisfies the options shape, so the call sites in `assets.ts` (the 304 at line 179, the injected-HTML response, the streamed response) and `app.ts:791` (the service-worker script) do not change from what CT-2 left. Keep `APP_CSP = buildAppCsp()` exported; it is now the tight baseline.

   Rewrite the module comment at the top of the file (`csp.ts:1-22`): state that `img-src` is limited to `'self' data: blob:` plus approved origins, that `object-src` is `'none'`, what stays open (navigation, popups, approved origins, WebRTC, DNS hints) and that confidentiality is not delivered. Keep `unsafe-inline` and keep the warning never to add a hash or nonce to `script-src` (ADR-0009, ADR-0035). Do not cite this plan's change IDs.

4. Bicep, `infra/azure/main.bicep`. Add `param imgSrcAllowAll bool = false` after the CT-2 `imgSrcExtra` parameter, with a `@description` that says: puts `https:` back in every hosted app's `img-src`; for one-org installs that accept the open image channel; default false; `object-src 'none'` stays. Add `{ name: 'EDGE_IMG_SRC_ALLOW_ALL', value: imgSrcAllowAll ? 'true' : 'false' }` after the `EDGE_IMG_SRC_EXTRA` entry in the edge env list (the `EDGE_ALLOW_PASSWORD_APPS` entry is at line 1222 before CT-2). Emit the lowercase literal: the comment at lines 1216-1221 explains that ARM's `string(bool)` yields `True`, which the edge's strict `=== "true"` parse would read as false. The dev-gateway env is untouched.

5. Tests.
   - `apps/edge/src/serving/csp.test.ts`. Three existing tests pin the open policy and must change in this task. Each failure there is meant to be a security review, so keep the strict assertions strict:
     - "keeps img-src open (honest trade-off, §4.4)" (lines 44-47, inside "APP_CSP relaxed code-provenance directives"): delete it and add to "APP_CSP strict data-flow directives" (line 18): `img-src` is exactly `'self' data: blob:`, and `object-src` is exactly `'none'`.
     - "widens connect-src and img-src with approved origins" (lines 50-54): expect `img-src` to be `'self' data: blob: https://api.foo.com https://b.example.com`.
     - "with no origins equals the strict baseline" (lines 66-70): expect `img-src` to be `'self' data: blob:`.
     - New cases: `imgSrcExtra` origins widen `img-src` only (not `connect-src`) and dedupe against approved origins; `imgSrcAllowAll: true` gives `img-src https: data: blob:` plus approved origins and still has `object-src 'none'`; with the option off, `img-src` contains none of the tokens `https:`, `http:`, `*` for a list of hostile `externalOrigins` inputs (`"*"`, `"https:"`, `"http://a.example"`, `"https://*.a.example"`, `"not a url"`, `""`); malformed origins are dropped; `report-uri` is still `/_csp-report`.
   - `apps/edge/src/config.test.ts`, in `describe("loadConfig")` (line 41, pattern at line 235): `EDGE_IMG_SRC_ALLOW_ALL` unset is `false`; `"true"` is `true`; `"True"`, `"1"`, `"yes"` and `" true"` are `false` (strict, as for the other "allow" settings).
   - `apps/edge/src/app.test.ts`, `describe("app hosts: asset serving")` (line 202): the CT-2 cases that expected both headers now expect only `content-security-policy`, carrying the tight `img-src` and `object-src 'none'`, with `content-security-policy-report-only` undefined, on the asset, SVG, `/`, 304 and SPA-fallback responses and on the injected-HTML response. Add `buildTestEdge({ config: { imgSrcAllowAll: true } })` cases: `img-src https: data: blob:`, `object-src 'none'`, still no Report-Only header. Add an `imgSrcExtra` case showing the extra origin in `img-src` and not in `connect-src`.
   - `apps/edge/src/serving/serviceWorker.test.ts`: the granted-app case (line 152) expects the tight `img-src` and no Report-Only header; the tombstone cases still expect no CSP at all (line 190 case).
   - `apps/portal/src/routes/csp.test.ts`, next to "marks a violation resolved only when the current manifest permits that directive" (line 71): add a case with the same setup (an app whose `capabilities` has `externalOrigins: ["https://granted.example"]`, `t.prisma.cspReport.create` rows, `GET /api/v1/csp/violations` as admin) asserting `img-src` to `https://granted.example/pic.png` is resolved, `img-src` to `https://other.example/pic.png` is not, `object-src` to `https://granted.example/x.swf` is not, and an `img-src` report whose blocked URI is `data` is not. This is an integration test; it needs Postgres from the dev container. `apps/portal/src/db/mappers.test.ts` has no CSP cases and does not need one: `isResolved` (`apps/portal/src/db/mappers.ts:201`) is not exported and the route test covers it.
   - `packages/shared/src/approval.test.ts:112-116`: run it, no change.
   - `apps/edge/src/serving/cspReport.test.ts`, `spanRedaction.test.ts`, `traceBoundary.test.ts`: from CT-2, unchanged and must pass.

6. Smoke runner, `.claude/skills/run-helix/smoke.mjs`. Extend the `smoke-csp` app and the checks that CT-2 added (the seed loop at line 318, the header check at lines 443-448, the browser lane at line 646):
   - Header check: the enforced header now contains `img-src 'self' data: blob:` and `object-src 'none'`, and `content-security-policy-report-only` is absent.
   - Browser, blocked image: `#remote` (the https image from another origin) has `complete === true` and `naturalWidth === 0`, and a new `img-src` row for that origin appears in `csp_reports` (read it the way CT-2 did). `#inline` (the `data:` GIF) still has `naturalWidth` 1.
   - Browser, granted image: grant the auth origin to `smoke-csp` by updating its `capabilities` with `psql` against `SVC_ENV.DATABASE_URL`, the way `cleanupThrowaway` (line 732) already shells out, setting `capabilities` to `{"externalOrigins":["https://auth.<BASE_DOMAIN>:<edge port>"]}` (the shape `apps/portal/src/routes/csp.test.ts:82-85` writes through Prisma). The registry has a NOTIFY trigger (`apps/edge/src/registry/listener.ts:18-27`), so poll the edge's response CSP for the origin for up to 15 seconds as the seed does for a new app. Then assert the header's `img-src` and `connect-src` both contain the origin. If the fixture URL cannot render as a real image, serve an image from the fixture page's own bundle by granting a second origin that does, or assert the header and the absence of a new violation for that origin; say which in `results/`. Remove the grant afterwards so a rerun starts clean.
   - If Chromium or the CDP launcher cannot be used (see CT-2's note on certificates and name resolution), these browser checks SKIP. Report that as unverified, not passed.
   - The consent popup is not in this runner at 792557a (`smoke.mjs` has no popup check). Its evidence is `pnpm lane:connections` (see step 8).

7. Docs. Edit `SKILL.md`, never the generated `quickstart.md`.
   - `packages/deploy-skill/SKILL.md:44-59`: in the CSP block change line 49 from `img-src https: data: blob:;` to `img-src 'self' data: blob:;` and add `object-src 'none';` after line 50 (`media-src ...`). Rewrite the sentence at lines 57-59 so it says approved origins are appended to `img-src` and `connect-src`, and add the instruction to agents: inline images as `data:` URIs or ship them in the bundle; a remote image needs its origin in `externalOrigins`, approved by an admin (an approved origin is also a `connect-src` grant). Leave line 160 (`"externalOrigins": [], // direct browser calls: widens CSP connect-src/img-src`) as it is; it is still accurate. Check `SKILL.md:421` (`<img>`/`<form>`/font loads do not go through the proxy) is still accurate and leave it.
   - `apps/docs/src/apps/quickstart.md:56` (the `img-src` line of the block), `:66` (the sentence) and `:167` (the manifest comment) are the same text, **generated** from `SKILL.md` by `apps/docs/scripts/render-skill.ts` and gitignored (`.gitignore:55`, `apps/docs/README.md:6-10`). Do not edit them. After the docs step of `./check-and-lint.sh` has run, open the generated file at those lines and confirm they show the new text. The brief's list of files to edit includes this path; the right edit is the source.
   - `docs/features/edge-serving.md:131-141`: rewrite the bullets. Remove "`img-src https: data: blob:` stays open" (lines 135-136) and say `img-src` is `'self' data: blob:` plus approved origins, `object-src 'none'`, what stays open, and the two settings (`EDGE_IMG_SRC_EXTRA`, `EDGE_IMG_SRC_ALLOW_ALL`). Remove the Report-Only paragraph CT-2 added, or reword it to say the Report-Only phase has ended.
   - `SECURITY.md:94-98` (the "Relaxed CSP directives" out-of-scope bullet) says "An open `img-src` and navigation-based exfiltration are documented residual risks". Rewrite it: `img-src` is no longer open by default; navigation, popups, approved origins, WebRTC and DNS hints remain; after this change app code can still send out what its viewer can read, and the platform does not claim confidentiality against a hostile app author. The design cites `SECURITY.md:56-57, 96`, but lines 56-57 are the reference-deployment hostnames; those belong to the domain-split documentation task, not to this change. Record the anchor correction in `results/`.
   - `docs/adr/0009-relaxed-csp.md`: append an `## Amendment (<date>) — img-src tightened, object-src closed` section in the format other ADRs use (`docs/adr/0004-auth-model.md:37`). It records: `img-src` is `'self' data: blob:` plus approved origins plus `EDGE_IMG_SRC_EXTRA`, with `EDGE_IMG_SRC_ALLOW_ALL` as the per-install relaxation; `object-src 'none'` is added (this answers the "Open question" at lines 24-26 for `object-src`; the SRI and per-app CDN questions stay open); the CDN script list is unchanged because narrowing it is a separate decision; the residual channels are listed; the existing warning never to add a hash or nonce to `script-src` still holds. Change the Open question text at lines 24-26 to drop `object-src` from it.
   - `docs/platform-architecture.md:200-201` states "`img-src https: data: blob:` allows remote images"; rewrite to the new policy. `:366` (the threat-model table row) says "open `img-src`" remains; reword to match. These are not in the design's file list but state the same fact, and `SECURITY.md` points readers at this section ("architecture §10", `docs/platform-architecture.md:362`).
   - `TODO.md:79`: the CSP supply-chain item names `add object-src 'none'`. Remove that clause and leave the SRI, per-app CDN and stored-XSS clauses.
   - `apps/docs/src/deploy/configuration.md`: extend the `EDGE_IMG_SRC_EXTRA` table CT-2 added (under "Runtime environment variables", line 182) with `EDGE_IMG_SRC_ALLOW_ALL` / `imgSrcAllowAll`, and say plainly what it gives up.
   - `apps/edge/README.md`: add an `EDGE_IMG_SRC_ALLOW_ALL` row after the `EDGE_IMG_SRC_EXTRA` row CT-2 added.
   - `docs/features/observability.md`: in the `helix.edge.csp_reports` row CT-2 added, note that `report` is expected only during the measurement phase and `enforce` after this change.
   - Operator rollout notes for this part (design "Operator rollout notes: Part 2") belong in the notes document `04_domain_split` produces. Put the Part 2 notes into `results/` for now: deploy the enforcing release after reading the measurement window, pre-grant legitimate hosts or list trusted hosts in `EDGE_IMG_SRC_EXTRA` (never an image proxy), installs that do not want the change set `EDGE_IMG_SRC_ALLOW_ALL=true`, tell app owners to inline images or ship them in the bundle. Everything about Azure in them is **unverified in Azure**.

8. Run the gates.
   - Focused: `pnpm vitest run apps/edge/src/serving apps/edge/src/config.test.ts apps/edge/src/app.test.ts apps/portal/src/routes/csp.test.ts packages/shared/src/approval.test.ts`.
   - Negative check, once: temporarily make `buildAppCsp` emit `img-src https:` in the default branch and confirm `csp.test.ts`, `app.test.ts` and the smoke header check fail; restore it.
   - `./check-and-lint.sh` in the dev container; `just dev smoke`; `just infra build`.
   - `pnpm lane:connections` (the real-browser connections lane, `xvfb-run` and Chromium from the dev container) to show the consent popup journeys pass with the edge serving the tight policy. If the lane cannot run in the environment, say so in `results/`; the popup claim is then unverified.
   - Save all output under `results/`.

9. Comments in the repo cite ADR numbers and file names, never this plan's change IDs (CT-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The enforced header carries `img-src 'self' data: blob:` plus approved and `EDGE_IMG_SRC_EXTRA` origins and `object-src 'none'`; `EDGE_IMG_SRC_ALLOW_ALL=true` restores `https:`; no Report-Only header in any mode (tests in `csp.test.ts`, `app.test.ts`, `serviceWorker.test.ts`).
- [ ] The three updated `csp.test.ts` cases and the new hostile-input and allow-all cases pass; deleting the `'self'` form and emitting `https:` by default fails them.
- [ ] The portal route test shows `img-src` violations resolve once the origin is granted and `object-src` violations never do.
- [ ] `SECURITY.md`, ADR-0009 (amendment plus trimmed Open question), `docs/platform-architecture.md`, `docs/features/edge-serving.md`, `TODO.md`, `SKILL.md`, the edge README and `configuration.md` state the new policy and the residual channels. The regenerated `apps/docs/src/apps/quickstart.md` shows the new CSP block at lines 50-62.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes; the `smoke-csp` browser checks (blocked remote image with a recorded `img-src` violation, `data:` image loads, granted origin in the header) passed or are recorded as SKIPPED and unverified. Output saved under `results/`.
- [ ] `just infra build` passes with `imgSrcAllowAll`. Output saved under `results/`.
- [ ] `pnpm lane:connections` passes, or the reason it could not run is in `results/`.
- [ ] Committed with `fest commit -m "CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL"`.
- [ ] Unverified in Azure: that Container Apps passes `EDGE_IMG_SRC_ALLOW_ALL` and `EDGE_IMG_SRC_EXTRA` through as set, and the operator rollout steps for an existing install. Untested anywhere: WebRTC ICE and DNS-hint behavior under this policy (the docs say so), and Firefox and Safari image blocking.
