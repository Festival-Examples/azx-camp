# CT-2 result: Report-Only CSP and the report counter

**Result: done.** Every app response the edge builds a CSP for now carries the unchanged enforced `Content-Security-Policy` plus `Content-Security-Policy-Report-Only`: the streamed asset, the injected HTML, the 304 and the platform service-worker script. The service-worker tombstone still has no CSP.

The Report-Only policy is the enforced one with two differences: `img-src 'self' data: blob:` plus the app's approved origins and `EDGE_IMG_SRC_EXTRA`, and `object-src 'none'`. Both headers come from one private builder in `apps/edge/src/serving/csp.ts` (`buildAppCsp`, `buildAppCspReportOnly`), and one helper sets them at every site (`applyAppCsp`). The enforced string is byte-for-byte unchanged: the existing `csp.test.ts` cases pass unmodified.

- **`EDGE_IMG_SRC_EXTRA`:** on `EdgeConfig`, not `GatewayConfig`; only the edge serves apps, and the dev-gateway has no CSP builder. `parseImgSrcExtra` refuses to boot on anything but bare `https://host[:port]` origins and names the bad entry. It widens the Report-Only `img-src` only.
- **Counter:** `helix.edge.csp_reports` (`INSTR_CSP_REPORTS`) with exactly `helix.app_id`, `helix.csp.directive` (folded to `img-src`, `connect-src`, `script-src`, `style-src`, `font-src`, `object-src` or `other`) and `helix.csp.disposition` (`enforce`, `report` or `unknown`). It increments before the `csp_reports` insert. No blocked or document URI is a dimension, attribute or log field. `spanRedaction.test.ts` and `traceBoundary.test.ts` gained `/_csp-report` cases.
- **Approval copy:** `packages/shared/src/capabilityHelp.ts` now says an approved host is also an image destination.
- **Agent docs:** `packages/deploy-skill/SKILL.md` tells authors to inline images as `data:` URIs or ship them in the bundle; `quickstart.md` regenerated.
- **Bicep:** `imgSrcExtra` parameter (default empty) sets `EDGE_IMG_SRC_EXTRA` on the edge. This is a design gap, since the design's file list omitted `main.bicep`. A commented line was added to `main.bicepparam`.
- **No rate limit on the sink**, deferred by design until the measurement window shows load. `csp_reports` has no schema change, so a Report-Only row cannot be told apart from an enforced one (accepted for the window).

## Coordinator fixes

- **The browser smoke check had two bugs.** The agent's run skipped it (no Chromium configured), so it never ran:
  1. The inline `data:` GIF fixture was truncated and never decoded (`naturalWidth` 0). It is replaced with a valid 1x1 GIF, and `smoke-csp` now redeploys on every run so the served page tracks the fixture; a reused app is otherwise never redeployed.
  2. The check filtered the Violations API on `v.slug`, but the field is `appSlug`, so it could never match. Debugging showed the reports were stored all along: `count: 4` from `GET /api/v1/csp/violations` on the kept stack.
- **Bicep description:** said an empty `imgSrcExtra` "leaves the variable unset". It sets an empty string, which the edge reads as no origins. Corrected, with the unverified-in-Azure note.

## Evidence (coordinator)

- `./check-and-lint.sh`: 241 of 241 test files, 3540 tests. `just infra build` passes.
- `just dev smoke` with `HELIX_SMOKE_CHROME` (Chromium 1248, real browser): 36 passed, 0 failed, 0 skipped, including "Report-Only CSP violation is recorded for smoke-csp: 5 report(s); disposition="report"" (`ct2-gate.txt`).
- The raw report Chromium sent, captured over CDP on a kept stack: `"violated-directive":"img-src"`, `"disposition":"report"`, the full `blocked-uri`, and the Report-Only `original-policy` with `img-src 'self' data: blob:` and `object-src 'none'`. That settles the task's hypothesis for Chromium: the legacy `report-uri` body does carry `disposition`. The code still maps an absent field to `unknown`.
- The kept stack's `tsx watch` processes were stopped afterwards; `free-port` leaves them behind.

## Unverified

- Whether Container Apps passes an empty `EDGE_IMG_SRC_EXTRA` through as set.
- Firefox and Safari Report-Only and `report-uri` behavior.

## Executor

cursor-agent, `composer-2.5`, 153 tool calls. Coordinator fixes as listed.
