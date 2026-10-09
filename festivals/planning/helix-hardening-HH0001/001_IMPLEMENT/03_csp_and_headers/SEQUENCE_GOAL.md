---
fest_type: sequence
fest_id: 03_csp_and_headers
fest_name: csp and headers
fest_parent: 001_IMPLEMENT
fest_order: 3
fest_status: pending
fest_created: 2026-10-08T20:54:29.385223-06:00
fest_tracking: true
---

# Sequence Goal: 03_csp_and_headers

**Sequence:** 03_csp_and_headers | **Phase:** 001_IMPLEMENT | **Status:** Pending | **Created:** 2026-10-08T20:54:29-06:00

## Sequence Objective

**Primary Goal:** Stop proxied responses from setting dangerous headers on a hosted app's origin, then close the silent image channel: ship the tighter `img-src` (`'self' data: blob:` plus approved origins) and `object-src 'none'` as a Report-Only policy first, enforce them after the measurement window, and keep `EDGE_IMG_SRC_ALLOW_ALL` as the per-install way back. These are the three changes CT-1 to CT-3 in `workflow/design/helix-spend-containment-egress/02-app-containment.md`.

**Contribution to Phase Goal:** The phase delivers the containment changes in the agreed order: spend first, then network egress, then CSP and headers, then the domain split. This sequence is the third step. It makes hosted-app responses unable to carry a policy or reporting header from a vendor, removes the bulk, no-gesture image exfiltration channel (finding SEC-2) without breaking apps that need a remote image (the existing approval path and `EDGE_IMG_SRC_EXTRA` cover them), and states plainly which channels stay open. It does not deliver confidentiality against a hostile app author, and the docs say so.

## Success Criteria

The sequence goal is achieved when:

### Required Deliverables

- [ ] **Extended header blocklist**: `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints`, `nel` and `link` are in `RESPONSE_HEADER_BLOCKLIST` (`packages/shared/src/fetch.ts`). None of them reaches an app-origin response through egress or through the edge gateway; `etag`, `content-type`, `retry-after` and rate-limit headers still pass. The loss of `Link` pagination headers is documented.
- [ ] **Report-Only tightened policy and report counter**: every app response (asset, injected HTML, 304, service-worker script) carries the unchanged enforced policy plus `Content-Security-Policy-Report-Only` with the tightened `img-src` and `object-src 'none'`; `EDGE_IMG_SRC_EXTRA` widens the Report-Only `img-src`; `helix.edge.csp_reports` counts reports with bounded `directive` and `disposition` dimensions and never records a URL; the approval copy says an approved host is also an image sink.
- [ ] **Enforced policy and the relaxation**: the enforced header carries the tight `img-src` and `object-src 'none'`; `EDGE_IMG_SRC_ALLOW_ALL=true` restores `https:` in `img-src`; the Report-Only header is retired; an ungranted image is blocked, produces a violation, and the Violations screen can resolve it by granting the origin.
- [ ] **Records and agent guidance**: ADR-0009 amendment, `SECURITY.md`, `docs/platform-architecture.md`, `docs/features/edge-serving.md`, `docs/features/observability.md`, `docs/features/fetch-proxy.md`, the edge README, `configuration.md` and `packages/deploy-skill/SKILL.md` (which generates `apps/docs/src/apps/quickstart.md`) state the new policy, the residual channels (navigation, popups, approved origins, WebRTC, DNS hints) and the instruction to inline images or ship them in the bundle.

### Quality Standards

- [ ] **Gate**: `./check-and-lint.sh` passes in the dev container before every commit; `just dev smoke` passes for every change here, since all three touch the edge or egress; `just infra build` passes for the Bicep parameters CT-2 and CT-3 add (`imgSrcExtra`, `imgSrcAllowAll`).
- [ ] **Telemetry ships with the change**: the one new instrument (`INSTR_CSP_REPORTS`) and its two attribute keys are constants in `packages/shared/src/telemetry.ts`, asserted with `startRecordingTelemetry`, listed in `docs/features/observability.md`, and checked against the redaction and trace-boundary suites. No name collides with the ones `01_spend_controls` added (`INSTR_GATEWAY_ADMISSION_DENIED`, `INSTR_GATEWAY_CUT_CHARGES`, `INSTR_GATEWAY_PLATFORM_SPEND_RATIO`, `INSTR_EGRESS_UPSTREAM_ABORTS`, `ATTR_USAGE_BASIS`).
- [ ] **Stricter behavior is per install**: the enforced `img-src` can be relaxed with `EDGE_IMG_SRC_ALLOW_ALL` (default off), and trusted image hosts can be added with `EDGE_IMG_SRC_EXTRA` (default empty); both are settings on the edge and Bicep parameters.
- [ ] **Azure honesty**: nothing here is applied to Azure or the live installs. Whether Container Apps passes the two settings through as set is labeled unverified in Azure, and the Part 2 rollout steps go into the operator rollout notes.

### Completion Criteria

- [ ] All tasks in sequence completed successfully
- [ ] Quality verification tasks passed
- [ ] Code review completed and issues addressed (the enforced `img-src` test changes in `csp.test.ts` get a careful read: those assertions are the containment)
- [ ] Documentation updated

## Task Alignment

> **Note:** Task files define HOW. Each task maps to one change in the design's "Work breakdown" section. This sequence has three task files; there are no separate testing, review, iterate or commit task files.

| Task | Task Objective | Contribution to Sequence Goal |
|------|----------------|-------------------------------|
| 01_ct1_proxied_response_header_blocklist.md | Add eight policy, reporting and navigation header names to the shared proxied-response blocklist, with tests on the shared list, egress and the edge gateway (CT-1). | Smallest, safest change and the base of the phase: a vendor can no longer set a CSP, `Clear-Site-Data` or reporting header on the app origin. |
| 02_ct2_report_only_csp_and_report_counter.md | Send a `Content-Security-Policy-Report-Only` header with the tightened `img-src` and `object-src 'none'` beside the unchanged enforced policy, add `EDGE_IMG_SRC_EXTRA`, and count CSP reports with bounded dimensions (CT-2). | Measures what the tighter policy would break before anything breaks, using the existing report sink and Violations screen. |
| 03_ct3_enforce_img_src_and_object_src.md | Move the tightened policy onto the enforced header, add `EDGE_IMG_SRC_ALLOW_ALL`, retire the Report-Only header, and rewrite the published CSP statements (CT-3). | Removes the silent bulk image channel and leaves a per-install way back, with the residual channels stated plainly. |

## Dependencies

### Prerequisites (from other sequences)

- None. `plan.md` orders this sequence after `02_network_egress`, but no task here needs code from it or from `01_spend_controls`. One soft link: both earlier sequences add names to `packages/shared/src/telemetry.ts` (`01_spend_controls`), so CT-2 re-reads the file and checks its new names against what is there when the task starts.

### Provides (to other sequences)

- **The CSP module and its settings**: `apps/edge/src/serving/csp.ts` (the single policy builder and `applyAppCsp`), the `imgSrcExtra` and `imgSrcAllowAll` fields on `EdgeConfig`, and the report counter. Used by `04_domain_split`, which changes the edge config, host classification and the app origin and must keep the CSP behavior and its tests intact.
- **The ADR-0009 amendment and the `SKILL.md` CSP block**: used by `04_domain_split` (the documentation task), which links to them from the operator rollout notes.
- **The hardened shared blocklist**: used by every later change that proxies a response.

## Working Directory

Target project: `projects/helix` (relative to campaign root)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Apps that load remote images (unsplash, picsum, avatar hosts, icon CDNs) lose them when the policy is enforced. | High | Med | The Report-Only phase measures it first; owners request the origin through the existing approval flow; operators list trusted hosts in `EDGE_IMG_SRC_EXTRA` or set `EDGE_IMG_SRC_ALLOW_ALL=true`; the docs tell agents to inline images or ship them in the bundle. The page keeps working when an image is blocked. |
| Each origin grant is an elevated, admin-approved request, which is heavy for a harmless image host, and an approved origin also gains `connect-src`. | Med | Med | Approval copy now says an approved host is also an image sink; `EDGE_IMG_SRC_EXTRA` avoids per-app requests; a separate `imageOrigins` capability is deferred until the Report-Only data exists. |
| `object-src 'none'` breaks apps that use `<object>` or `<embed>`; usage was not measured. | Low | Low | It is reported in Report-Only first, and the counter has an `object-src` directive value. Hypothesis until measured. |
| The report sink has no rate limit, and a tighter `img-src` multiplies reports; a hostile app can already flood it. | Med | Low | Deferred by `plan.md`. The counter makes load visible; add a per-app cap only if the measurement window shows it. |
| The legacy `report-uri` body may not carry `disposition` in every browser, so Report-Only and enforced reports cannot be told apart. | Med | Low | The code accepts the field being absent (`unknown`); CT-2 reads a real report in the smoke run and records what Chromium sent. |
| Stripping `link` removes Link-header pagination that apps use against vendors such as the GitHub API; the design assumed a `fetch()` response cannot act on it, but app code can read it. | Med | Med | The list is kept as the design set it (an allowlist is deferred). The consequence is documented for agents and recorded in `results/`; the owner decides whether to revisit it. |
| The design and the code differ in places this plan found: `quickstart.md` is generated and gitignored, `SECURITY.md:56-57` is not CSP text, the design's file list omits `main.bicep`, and CT-3 is worded two ways on the Report-Only header. | High | Low | Each task records the difference in `results/` and follows the code; the Bicep parameters are added and flagged as a design gap. |
| The browser smoke checks SKIP without Chromium, the certificate flag or name resolution, and the consent popup has no smoke check at this commit. | Med | Med | Header checks run without a browser; the popup is proved by `pnpm lane:connections`; a SKIP is reported as unverified. |
| WebRTC ICE, DNS prefetch and preconnect hints are not governed by `img-src` or `connect-src`, so a determined app can still leak data. | High | Low | Stated, not fixed: the docs say the change removes the silent bulk channel and does not deliver confidentiality; the claims are labeled untested. |

## Progress Tracking

### Milestones

- [ ] **Milestone 1**: CT-1 merged: the eight header names are blocked on both hops with tests on the shared list, egress and the edge gateway.
- [ ] **Milestone 2**: CT-2 merged and the Report-Only header is flowing: reports are counted and recorded, and the measurement window can start.
- [ ] **Milestone 3**: CT-3 merged: the enforced policy is tight, `EDGE_IMG_SRC_ALLOW_ALL` works, and the published CSP statements match.

## Quality Gates

### Testing and Verification

- [ ] All unit tests pass
- [ ] Integration tests complete (the portal `csp.test.ts` route test needs the dev container's Postgres)
- [ ] No new work on the request hot path beyond one header string per response; the header is built per response from the registry entry, as before

### Code Review

- [ ] Code review conducted
- [ ] Review feedback addressed
- [ ] Standards compliance verified

### Iteration Decision

- [ ] Need another iteration? Decided at the iterate gate
- [ ] If yes, new tasks created: Decided at the iterate gate
