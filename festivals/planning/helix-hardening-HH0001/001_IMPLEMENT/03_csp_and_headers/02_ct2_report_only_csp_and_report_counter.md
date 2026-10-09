---
fest_type: task
fest_id: 02_ct2_report_only_csp_and_report_counter.md
fest_name: ct2 report only csp and report counter
fest_parent: 03_csp_and_headers
fest_order: 2
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:54:29.435056-06:00
fest_tracking: true
---

# Task: ct2 report only csp and report counter

## Objective

Send every app response a second header, `Content-Security-Policy-Report-Only`, carrying the tightened policy (`img-src 'self' data: blob:` plus approved origins plus `EDGE_IMG_SRC_EXTRA`, and `object-src 'none'`) while the enforced policy stays exactly as it is, and count the violation reports that arrive. Implements CT-2 from 02-app-containment.md ("Part 2", first step; findings SEC-2, KP-9).

## Requirements

- [ ] Depends on `01_ct1_proxied_response_header_blocklist.md` in order only. There is no code dependency. `03_ct3_enforce_img_src_and_object_src.md` depends on this task and removes the Report-Only header again.
- [ ] The enforced `Content-Security-Policy` is byte-for-byte what `buildAppCsp` produces today (`img-src https: data: blob:` plus approved origins, no `object-src`). The existing tests in `apps/edge/src/serving/csp.test.ts` pass unmodified.
- [ ] The Report-Only policy is the enforced policy with exactly two differences: `img-src` is `'self' data: blob:` followed by the app's approved origins and the operator's `EDGE_IMG_SRC_EXTRA` origins, and `object-src 'none'` is present. Every other directive is identical, including `report-uri /_csp-report`.
- [ ] Both headers are on every app response the edge builds a CSP for: the streamed asset response, the injected-HTML response, the 304, and the platform service-worker script. They are not on the service-worker tombstone (it has no CSP today), and not on the auth-host, login, consent or portal pages, which have their own policies.
- [ ] `EDGE_IMG_SRC_EXTRA` is a comma-separated list of origins, default empty. Each entry must be a bare `https://host[:port]` origin. The edge refuses to boot on an entry that is not (a path, a query, credentials, a wildcard host, `http:`, `*`, a bare scheme such as `https:`, or text that is not a URL), and the error names the entry. It widens the Report-Only `img-src` only. It never widens `connect-src` and never touches the enforced header in this task.
- [ ] A malformed or hostile origin in an app's manifest `externalOrigins` is dropped by the existing `originSources` function (fail closed), and that holds for the new Report-Only policy too.
- [ ] A violation report from the Report-Only policy lands in `csp_reports` through the existing sink, with no schema change and no migration. The row cannot be told apart from an enforced-policy report; that is accepted for the measurement window.
- [ ] `helix.edge.csp_reports` (constant `INSTR_CSP_REPORTS`) counts each parsed report with exactly three dimensions: `helix.app_id`, `helix.csp.directive` and `helix.csp.disposition`. Directive is folded into a fixed set (`img-src`, `connect-src`, `script-src`, `style-src`, `font-src`, `object-src`, `other`); an unknown or hostile directive string becomes `other`. Disposition is `enforce`, `report` or `unknown`, folded the same way. The blocked URI and the document URI are never a dimension, a span attribute or a log field.
- [ ] Failure paths. The counter increments before the `csp_reports` insert, so a failing insert still counts (the handler already logs a warning and answers 204). A report with no usable blocked URI (`extractReport` returns null) is not counted and not stored, as today. An unknown slug still answers 404 and counts nothing. The sink still always answers 204 on the known-app path. A malformed Report-Only value in a browser is ignored by the browser and cannot break a page, so no runtime fallback is needed.
- [ ] No rate limit is added to the sink in this task. The design defers it until the measurement window shows load. Record in `results/` that none exists.
- [ ] The approval copy for an origin grant says an approved host is also an image sink.
- [ ] Agent-facing docs tell authors to inline images as `data:` URIs or ship them in the bundle, and that remote images will need an approved origin.
- [ ] Per-install setting: an Azure install can set `EDGE_IMG_SRC_EXTRA` through a new optional Bicep parameter (default empty). The design's file list does not include `main.bicep`, but its rollout notes tell operators to set this variable. Record the addition in `results/` as a design gap.
- [ ] Unverified: browsers' delivery of the legacy `report-uri` `disposition` field is a hypothesis until you read it from a real report in the smoke run. The code must work when the field is absent (`unknown`).

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b ct-2-report-only-csp`.

2. Read these before editing:
   - `apps/edge/src/serving/csp.ts` (the whole file, 80 lines). `buildAppCsp` is at lines 60-78, `originSources` at 41-53, `APP_CSP` at 80.
   - The four places that set `content-security-policy` on an app response: `apps/edge/src/serving/assets.ts:114` (builds `csp`), `:179` (304), `:214` (injected HTML), `:227` (streamed asset), and the service-worker script at `apps/edge/src/app.ts:791`. The design names only `assets.ts:114` and `app.ts:791`; the three `reply.header` sites in `assets.ts` are the ones that actually send it.
   - `apps/edge/src/serving/cspReport.ts` (`extractReport` at lines 65-101, `makeCspReportHandler` at lines 114-135) and its test `cspReport.test.ts`.
   - The visit counter, which is the pattern for a bounded edge counter: `INSTR_APP_VISITS` at `packages/shared/src/telemetry.ts:40`, `VISIT_RECORD_OUTCOMES` at `:245`, `appVisits` in `apps/edge/src/telemetry.ts:46-72` and `:95-132`, its use at `apps/edge/src/serving/visits.ts:162-164`, and its test at `apps/edge/src/serving/visits.test.ts:240-265`.
   - `parseTrustProxy` in `apps/edge/src/config.ts:608-670` for the style of a boot-time refusal.

3. Config, `apps/edge/src/config.ts`. Put the field on `EdgeConfig`, not on `GatewayConfig`: only the edge serves apps, and the dev-gateway has no CSP builder. (The design's change table lists `config.ts` without saying which interface; record this choice in `results/`.)
   - Add to `EdgeConfig` after `anonRateLimit` (line 295), with a doc comment saying what it widens and that it must not list a host that fetches attacker-chosen URLs (an image proxy):

```ts
  /**
   * Origins appended to every app's img-src (EDGE_IMG_SRC_EXTRA). Operator-trusted
   * image hosts, so owners need no per-app approval for them. Never connect-src.
   * Do not list a host that fetches attacker-chosen URLs: that is a sink.
   */
  imgSrcExtra: string[];
```

   - Add `export function parseImgSrcExtra(raw: string | undefined): string[]` near `parseTrustProxy`. Blank or unset gives `[]`. Split on `,`, trim, skip empty parts. For each part: `new URL(part)` must succeed, `protocol === "https:"`, no `username`/`password`, no `*` in `hostname`, `search === ""`, `hash === ""`, `pathname === "/"`, and the part with any single trailing `/` removed must equal `url.origin` (so `HTTPS://Example.com` is refused rather than silently rewritten; if you prefer to accept it, normalise and test it, but do not accept a path). Return the deduplicated list of `url.origin` values. On any bad part throw `new Error(\`EDGE_IMG_SRC_EXTRA is not a list of https origins (bad: ${...JSON.stringify}). Each comma-separated part must look like "https://images.example.com" or "https://images.example.com:8443": no path, query, credentials or wildcard.\`)`.
   - In `loadConfig` (the object returned at lines 820-835), add `imgSrcExtra: parseImgSrcExtra(env.EDGE_IMG_SRC_EXTRA),` after `anonRateLimit`.
   - Fixtures that build a full `EdgeConfig` and must gain `imgSrcExtra: []` or typecheck fails: `apps/edge/src/test/config.ts` (`testEdgeConfig`, `portalUrl: null` at line 102; the dev-gateway fixture at line 142 does not change), `apps/edge/src/app.test.ts` (`testConfig`, `portalUrl: null` at line 55), and `apps/edge/src/serving/cspReport.test.ts` (`testConfig`, `portalUrl: null` at line 53). `public-visibility.test.ts` goes through `testEdgeConfig`. After editing, run `grep -rn "anonRateLimit:" apps/edge/src` and confirm every full literal has the new field; `pnpm typecheck` finds any you missed. `DevGatewayConfig` does not change.

4. CSP builder, `apps/edge/src/serving/csp.ts`. Refactor `buildAppCsp` into one private policy builder that both headers share, so the Report-Only header can only differ where intended:

```ts
interface PolicyOptions {
  externalOrigins: readonly string[];
  /** false: today's enforced img-src. true: the tightened policy (Report-Only). */
  tight: boolean;
  imgSrcExtra: readonly string[];
}

function buildPolicy(o: PolicyOptions): string {
  const extra = originSources(o.externalOrigins);
  const suffix = extra.length ? ` ${extra.join(" ")}` : "";
  const imgOrigins = originSources([...o.externalOrigins, ...o.imgSrcExtra]);
  const imgSuffix = imgOrigins.length ? ` ${imgOrigins.join(" ")}` : "";
  return [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' ${CDNS}`,
    `style-src 'self' 'unsafe-inline' https://fonts.googleapis.com ${CDNS}`,
    `font-src 'self' data: https://fonts.gstatic.com ${CDNS}`,
    o.tight ? `img-src 'self' data: blob:${imgSuffix}` : `img-src https: data: blob:${suffix}`,
    "media-src 'self' data: blob:",
    ...(o.tight ? ["object-src 'none'"] : []),
    `connect-src 'self'${suffix}`,
    "worker-src 'self' blob:",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    `report-uri ${CSP_REPORT_PATH}`,
  ].join("; ");
}

export function buildAppCsp(externalOrigins: readonly string[] = []): string {
  return buildPolicy({ externalOrigins, tight: false, imgSrcExtra: [] });
}

export function buildAppCspReportOnly(
  externalOrigins: readonly string[] = [],
  imgSrcExtra: readonly string[] = [],
): string {
  return buildPolicy({ externalOrigins, tight: true, imgSrcExtra });
}
```

   Keep `APP_CSP` exported (`csp.test.ts` imports it). Run the existing `csp.test.ts` before and after the refactor and confirm the enforced string is unchanged.

   Add one helper so the four sites cannot drift, taking the reply and the config:

```ts
import type { FastifyReply } from "fastify";
export const CSP_REPORT_ONLY_HEADER = "content-security-policy-report-only";

/** Set the enforced policy and, during the measurement phase, the Report-Only one. */
export function applyAppCsp(
  reply: FastifyReply,
  externalOrigins: readonly string[],
  config: { imgSrcExtra: readonly string[] },
): void {
  reply.header("content-security-policy", buildAppCsp(externalOrigins));
  reply.header(CSP_REPORT_ONLY_HEADER, buildAppCspReportOnly(externalOrigins, config.imgSrcExtra));
}
```

   Update the module comment (lines 1-22): say that `img-src` stays open on the enforced header while the tightened policy is measured in Report-Only, and that `object-src` falls back to `default-src` until enforced. Keep the warning about never adding a hash or nonce to `script-src`. Do not cite this plan's change IDs; ADR-0009 is fine.

5. Use the helper at every site.
   - `apps/edge/src/serving/assets.ts`: delete the `const csp = buildAppCsp(entry.externalOrigins);` at line 114 and its import use at line 11 (import `applyAppCsp` instead). At the 304 (line 179) change the chain to `reply.status(304).header("cache-control", "no-cache"); applyAppCsp(reply, entry.externalOrigins, config);`. At the injected-HTML response (lines 209-215) and the streamed response (lines 220-227), remove `.header("content-security-policy", csp)` from the chain and call `applyAppCsp(reply, entry.externalOrigins, config)` before `reply.send`/the content-length branch. `config` is already in scope (`const { config, ... } = deps`, line 37).
   - `apps/edge/src/app.ts:791`: replace `reply.header("content-security-policy", buildAppCsp(entry.externalOrigins));` with `applyAppCsp(reply, entry.externalOrigins, config);`. Check that `config` is in scope in that route (it is used elsewhere in `buildApp`; `grep -n "config" apps/edge/src/app.ts` near line 747). Update the import at `app.ts:47`.
   - The tombstone and unknown-scope branches (`app.ts` just above 791) send no CSP today and must keep sending none (`serviceWorker.test.ts:200` asserts it).

6. Telemetry constants, `packages/shared/src/telemetry.ts`. First `grep -n "INSTR_\|ATTR_" packages/shared/src/telemetry.ts` again and confirm none of these names exist, because earlier sequences add names here (`01_spend_controls` adds `INSTR_GATEWAY_ADMISSION_DENIED`, `INSTR_GATEWAY_CUT_CHARGES`, `INSTR_GATEWAY_PLATFORM_SPEND_RATIO`, `INSTR_EGRESS_UPSTREAM_ABORTS` and `ATTR_USAGE_BASIS`; `02_network_egress` adds none). Add:

```ts
// beside INSTR_APP_VISITS (line 40)
export const INSTR_CSP_REPORTS = "helix.edge.csp_reports";

// beside the other ATTR_ keys (after line 111)
/** Violated directive on a CSP report, folded to CSP_REPORT_DIRECTIVES. */
export const ATTR_CSP_DIRECTIVE = "helix.csp.directive";
/** Whether the report came from an enforced or a Report-Only policy. */
export const ATTR_CSP_DISPOSITION = "helix.csp.disposition";

// beside VISIT_RECORD_OUTCOMES (line 245)
export const CSP_REPORT_DIRECTIVES = [
  "img-src", "connect-src", "script-src", "style-src", "font-src", "object-src", "other",
] as const;
export type CspReportDirective = (typeof CSP_REPORT_DIRECTIVES)[number];
export const CSP_REPORT_DISPOSITIONS = ["enforce", "report", "unknown"] as const;
export type CspReportDisposition = (typeof CSP_REPORT_DISPOSITIONS)[number];
```

   Add `cspReports: Counter;` to `EdgeInstruments` (`apps/edge/src/telemetry.ts:46-72`, with a doc line `appId`, `directive` ∈ `CSP_REPORT_DIRECTIVES`, `disposition` ∈ `CSP_REPORT_DISPOSITIONS`) and `cspReports: meter.createCounter(INSTR_CSP_REPORTS, { description: "CSP violation reports received, by app, directive and disposition. Operational only; the owner-facing counts come from csp_reports." })` in `instruments()` (lines 95-132). Import the constant at the top of that file with the others.

7. Report handling, `apps/edge/src/serving/cspReport.ts`.
   - Extend what `extractReport` returns with `disposition: "enforce" | "report" | "unknown"`. Legacy body: `o["disposition"]`. Reporting-API body: `b.disposition`. Anything other than the strings `enforce` or `report` is `unknown`.
   - Add and export a pure `foldDirective(raw: string): CspReportDirective`: lowercase, take the first whitespace-separated token, return it if it is in `CSP_REPORT_DIRECTIVES`, return the base name for the CSP3 sub-directives (`script-src-elem`, `script-src-attr`, `style-src-elem`, `style-src-attr` fold to `script-src` and `style-src`), and return `other` otherwise (including `default-src`, `unknown`, an empty string and anything app-chosen).
   - In `makeCspReportHandler`, after `extractReport` returns non-null and before `rt.store.record`, increment the counter. The store's `record` must receive the same four fields as today, so split the disposition off rather than spreading it into the record:

```ts
const parsed = extractReport(req.body);
if (parsed) {
  const { disposition, ...record } = parsed;
  instruments().cspReports.add(1, {
    [ATTR_APP_ID]: entry.appId,
    [ATTR_CSP_DIRECTIVE]: foldDirective(record.directive),
    [ATTR_CSP_DISPOSITION]: disposition,
  });
  if (rt.store) {
    try {
      await rt.store.record({ appId: entry.appId, ...record });
    } catch (err) {
      req.log.warn({ err }, "failed to record CSP report");
    }
  }
}
```

   The stored `directive` is unchanged (full string, clamped to 128 characters), so the Violations screen and `isResolved` (`apps/portal/src/db/mappers.ts:201`) behave as before. Import `instruments` from `../telemetry.js`.

8. Approval copy, `packages/shared/src/capabilityHelp.ts:61-70`. Change the `externalOrigins` entry:
   - `grants`: "Allows the app's own JavaScript, running in each visitor's browser, to call the named host directly and to load images from it, by widening the page's Content-Security-Policy."
   - add a risk: "An approved host can receive anything the page can read, one request at a time, including through image URLs."
   - `riskWhy`: "A new browser-callable host is also a new place the page can send data, as a request or as an image."
   Keep the title ("Direct browser calls"). The classifier at `packages/shared/src/approval.ts:406-410` is unchanged; `packages/shared/src/approval.test.ts:112-116` already asserts that adding an origin is elevated and must still pass.

9. Bicep, `infra/azure/main.bicep`. Add `@description('...') param imgSrcExtra string = ''` after `allowPasswordApps` (line 397), and `{ name: 'EDGE_IMG_SRC_EXTRA', value: imgSrcExtra }` after the `EDGE_ALLOW_PASSWORD_APPS` entry (line 1222) in the edge app's env list. Follow the `EDGE_ALLOW_PUBLIC_APPS` pattern and its comment at lines 1216-1221. The description must say: comma-separated https origins appended to every app's `img-src`, never an image proxy. Do not touch the dev-gateway env (it serves no app pages). Whether Container Apps accepts an empty-string env value is **unverified in Azure**; `just infra build` only compile-checks it. If you can find an existing conditional-entry pattern in `main.bicep`, use it to omit the entry when the parameter is empty; do not invent one.

10. Tests.
    - `apps/edge/src/serving/csp.test.ts`: add `describe("buildAppCspReportOnly")` and leave the existing `describe`s untouched. Assert: `img-src` is exactly `'self' data: blob:` with no origins; approved origins and `imgSrcExtra` origins appear in `img-src` and only approved origins appear in `connect-src`; duplicates between the two lists appear once; `object-src` is exactly `'none'`; `https:`, `*` and `http:` never appear in `img-src`; a malformed extra origin is dropped; every directive other than `img-src` and `object-src` is equal to the enforced policy's (compare the two parsed maps key by key); the enforced `buildAppCsp()` still has no `object-src` and still has `img-src https: data: blob:`.
    - `apps/edge/src/config.test.ts`: in `describe("loadConfig")` (line 41, pattern at line 235), add cases for `EDGE_IMG_SRC_EXTRA`: unset, blank and whitespace give `[]`; `"https://a.example, https://b.example:8443"` gives both; a duplicate gives one; each of `http://a.example`, `https:`, `*`, `https://*.a.example`, `https://a.example/path`, `https://a.example?x=1`, `https://u:p@a.example`, `not a url` throws `/EDGE_IMG_SRC_EXTRA is not a list of https origins/`; one bad entry in an otherwise good list refuses boot.
    - `apps/edge/src/app.test.ts`: in `describe("app hosts: asset serving")` (line 202), assert both headers on the asset (`/assets/app.js`, line 203), the SVG (line 217), `/` (line 238), the 304 (line 253) and the SPA fallback (line 263). The Report-Only value contains `object-src 'none'` and `img-src 'self' data: blob:`; the enforced value does not contain `object-src` and still contains `img-src https:`. Add a case with `buildTestEdge({ config: { imgSrcExtra: ["https://images.example"] } })` showing the extra origin in the Report-Only `img-src` and absent from the enforced header and from `connect-src`. Add the injected-HTML case (assets.ts:214): a registry entry with `fetch.shim` true (the shape is in `apps/edge/src/gateway/fetch.test.ts` where `registryEntry` is called with `fetch: { connections, requestsPerDay, shim: false }`) serving `/`, with both headers present.
    - `apps/edge/src/serving/serviceWorker.test.ts`: in `describe("GET /_helix/sw.js")` (line 151), the granted-app case at line 152 also asserts the Report-Only header; the mismatched-scope tombstone case (line 190) asserts `content-security-policy-report-only` is undefined too.
    - `apps/edge/src/serving/cspReport.test.ts`: update the two `extractReport` expectations (they use `toEqual`, so they now need `disposition`): legacy body without a field gives `"unknown"`, with `disposition: "report"` gives `"report"`, `"enforce"` gives `"enforce"`, `"bogus"` gives `"unknown"`; the Reporting-API body likewise. Add `foldDirective` cases: the six known names, `script-src-elem`, `IMG-SRC`, `img-src 'self'` (first token), `default-src`, `""`, and a 5 KB hostile string all give a member of the fixed set. In `describe("POST /_csp-report")` (line 100) add metric cases using the `visits.test.ts:240-265` pattern (`recording = startRecordingTelemetry()`, then `await recording.metrics()` and find `INSTR_CSP_REPORTS`): a report increments the counter once with exactly the attribute keys `helix.app_id`, `helix.csp.directive`, `helix.csp.disposition`; a hostile `effective-directive` string is counted as `other`; a store whose `record` throws still produces a count and a 204; a report with no `blocked-uri` produces no count; an unknown slug produces 404 and no count. The existing record assertion at line 136 (exact `toEqual` of the four stored fields) must still pass, which proves the disposition does not leak into the store.
    - `apps/edge/src/spanRedaction.test.ts`: add a case in the style of the existing route cases (for example the status route at line 523): POST `/_csp-report` to an app host with a `blocked-uri` of `https://x.example/?token=PLANTED-CSP-SECRET` and a `document-uri` carrying another planted value. Scan every span attribute and every metric attribute (`await recording.metrics()`) for the planted strings and assert none appear, and assert no attribute key is in `FORBIDDEN_URL_ATTRS`.
    - `apps/edge/src/traceBoundary.test.ts`: add a case that POSTs `/_csp-report` with `traceparent: APP_TRACEPARENT` (line 57) and asserts no recorded span has `APP_TRACE_ID` and that no attribute dump contains it. The report route creates no span today, so this pins "the report path never continues an inbound trace" and will fail if someone adds a span that does.
    - `packages/shared/src/approval.test.ts`: no change; confirm it passes.

11. Docs.
    - `docs/features/observability.md`: add a row after `helix.app.visits` (line 199): `helix.edge.csp_reports | counter | appId, directive (img-src / connect-src / script-src / style-src / font-src / object-src / other), disposition (enforce / report / unknown; Report-Only reports are separable from enforcement) ...` with the note that the blocked and document URIs are never recorded and that the owner-facing counts come from `csp_reports`. Do not add an alert in this task (the design lists a CSP-report alert as worth adding after measurement).
    - `docs/features/edge-serving.md:126-141` ("CSP injection"): add a short paragraph that every app response also carries `Content-Security-Policy-Report-Only` with the tightened policy during the measurement phase, that its reports reach the same sink, and that `EDGE_IMG_SRC_EXTRA` widens it. Leave the lines at 135-136 (`img-src https: ...` stays open) as they are; `03_ct3_enforce_img_src_and_object_src.md` rewrites them.
    - `apps/edge/README.md`: add an `EDGE_IMG_SRC_EXTRA` row to the env table after the `EDGE_ALLOW_PASSWORD_APPS` row (line 74), in the same column style.
    - `apps/docs/src/deploy/configuration.md`: in "Runtime environment variables" (line 182), add a short table for `EDGE_IMG_SRC_EXTRA` (set from the `imgSrcExtra` parameter, empty by default) with the warning about image proxies.
    - `packages/deploy-skill/SKILL.md`: near the CSP block (lines 44-59) add a short paragraph: remote images will need an approved origin once the policy is enforced; inline images as `data:` URIs or ship them in the bundle; the edge is already reporting remote-image use. Leave the CSP block itself alone in this task, because the enforced policy has not changed yet. Edit `SKILL.md` only: `apps/docs/src/apps/quickstart.md` is generated from it by `apps/docs/scripts/render-skill.ts` and is gitignored (`.gitignore:55`), so a hand edit would be lost. After the docs step of `./check-and-lint.sh` runs, open `apps/docs/src/apps/quickstart.md` near lines 50-70 and confirm the new paragraph rendered.

12. Smoke runner, `.claude/skills/run-helix/smoke.mjs`. Read `.claude/skills/run-helix/SKILL.md` first.
    - Header check (no browser, always runs): in the existing "CSP is injected" check (lines 443-448) also assert `content-security-policy-report-only` is present, contains `object-src 'none'` and `img-src 'self' data: blob:`, and that the enforced header still contains `img-src https:`.
    - Report-recorded check (browser). Add a third seeded app beside `smoke-public` and `smoke-internal` in `seedRegistry` (the slug loop starts at line 318), with its own page, because the existing seed reuses an app that already has a live version and would not pick up a changed page. Use a new slug such as `smoke-csp` (public) whose `index.html` contains `<img id="remote" src="https://auth.${BASE_DOMAIN}:${STACK.ports.edge}/health">` (an https origin that is not the app's own, served by the local edge) and `<img id="inline" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">`. In `checkBrowser` (line 646) open `EDGE("smoke-csp")`, wait, then read the recorded report. Read it through the portal's `GET /api/v1/csp/violations` (`apps/portal/src/routes/csp.ts:14`) if the dev token is an admin; otherwise query `csp_reports` with `psql` using `SVC_ENV.DATABASE_URL`, the way `cleanupThrowaway` does (line 732). Assert a row with directive `img-src` and a blocked URI starting with the auth origin exists, and that the page's `#remote` image element still has no `onerror` result you rely on (in this task the enforced policy allows it, so the image request is made; do not assert it loaded, because the auth host's `/health` is not an image). Also assert `#inline` has `naturalWidth` of 1.
    - The browser launcher (`.claude/skills/run-helix/cdp.mjs:36-61`) passes no certificate flag and the edge serves a mkcert certificate, and it resolves nothing locally. If Chromium rejects the edge certificate or cannot resolve `*.local.helix.azxlabs.io`, add an opt-in `ignoreCertErrors` option to `launchBrowser` that adds `--ignore-certificate-errors` and `--host-resolver-rules=MAP *.${BASE_DOMAIN} 127.0.0.1`, and use it only for this check. Keep the default unchanged.
    - The browser lane SKIPs without a cached Chromium (`smoke.mjs:646-660`). Report a SKIP as unverified, not passed. The header check above still runs, and the unit tests prove the rest.
    - While the report is in front of you, read the legacy body that Chromium actually sent and record in `results/` whether it carried `disposition` and what value. That settles the hypothesis in the requirements.

13. Run the gates. Focused first: `pnpm vitest run apps/edge/src/serving apps/edge/src/config.test.ts apps/edge/src/app.test.ts apps/edge/src/spanRedaction.test.ts apps/edge/src/traceBoundary.test.ts packages/shared`. Then `./check-and-lint.sh` in the dev container, `just dev smoke`, and `just infra build`. Save all output under `results/`.

14. Comments in the repo cite ADR numbers and file names, never this plan's change IDs (CT-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] HTML, asset, 304 and service-worker responses carry the unchanged enforced header and the Report-Only header (tests in `app.test.ts` and `serviceWorker.test.ts`); the tombstone carries neither.
- [ ] `csp.test.ts` proves the enforced policy is unchanged and the Report-Only policy differs only in `img-src` and `object-src`.
- [ ] `cspReport.test.ts` proves the counter's dimensions, the fold to `other`, the count-before-insert behavior and the unchanged stored record. `spanRedaction.test.ts` and `traceBoundary.test.ts` have the new report-route cases and pass.
- [ ] `docs/features/observability.md` lists `helix.edge.csp_reports`, the edge README and `configuration.md` list `EDGE_IMG_SRC_EXTRA`, and `SKILL.md` carries the image advice.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes. If the browser lane ran, a report from `smoke-csp` was recorded in `csp_reports` and the `disposition` value (or its absence) is written down in `results/`. If it skipped, say so in `results/`.
- [ ] `just infra build` passes with the new parameter. Output saved under `results/`.
- [ ] Committed with `fest commit -m "CT-2: report-only tightened CSP and CSP report counter"`.
- [ ] Unverified in Azure: that Container Apps accepts an empty `EDGE_IMG_SRC_EXTRA` value. Unverified until a real report is read: the `disposition` field of the legacy `report-uri` body. Not run here: browser behavior in Firefox and Safari (Report-Only support and `report-uri` delivery).
