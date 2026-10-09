---
fest_type: sequence
fest_id: 04_domain_split
fest_name: domain split
fest_parent: 001_IMPLEMENT
fest_order: 4
fest_status: pending
fest_created: 2026-10-09T12:11:05.313572-06:00
fest_tracking: true
---

# Sequence Goal: 04_domain_split

**Sequence:** 04_domain_split | **Phase:** 001_IMPLEMENT | **Status:** Pending | **Created:** 2026-10-09T12:11:05-06:00

## Sequence Objective

**Primary Goal:** Let an install serve hosted apps from their own registrable domain while sign-in, the portal and the dev gateway stay on the control domain, as a per-install setting that defaults to today's single-domain layout, with adversarial tests and a dedicated review pass on the OIDC handoff, and with the Azure-only parts compile-checked and labeled unverified. These are the seven changes CT-4 to CT-10 in `workflow/design/helix-spend-containment-egress/02-app-containment.md`.

**Contribution to Phase Goal:** The phase delivers the containment changes in the agreed order: spend first, then network egress, then CSP and headers, then the domain split last because it touches the login handoff. This sequence is the fourth and last step. It closes the cookie-bomb and reputation blast radius between hostile app code and the control plane (findings SEC-1 and KP-1, upstream issue #16) without moving the auth host, so Entra redirect URIs, vendor OAuth callback URLs and the portal URL stay as they are. It does not touch any live install: the operator rollout notes it writes are the deliverable for them.

## Success Criteria

The sequence goal is achieved when:

### Required Deliverables

- [ ] **A second loopback dev domain**: with `HELIX_APPS_DOMAIN` set, the dev container serves apps on `<slug>.helix-apps.localhost` beside the control domain `local.helix.azxlabs.io`, with a second mkcert certificate, Chromium and Node name resolution that does not rely on `getaddrinfo`, and `stack-env.mjs` exposing both domains; unset, nothing changes (`01_ct4_second_loopback_dev_domain.md`).
- [ ] **The edge control/apps split**: `EDGE_CONTROL_DOMAIN`, `classifyHost` with a control domain, `controlOrigin()`, a `publicOrigin()` that refuses control labels, boot validation that fails closed, all nine auth-host call sites migrated, and the ten adversarial tests the design names; with the setting unset every existing edge test passes with its assertions unchanged (`02_ct5_edge_control_and_apps_domain_split.md`).
- [ ] **A recorded dedicated review pass on the handoff change**: `results/ct5-review.md` names the reviewer, the files and the findings.
- [ ] **The portal control origin**: `CONTROL_PUBLIC_BASE` drives the vendor callback URL only; app URLs and `GET /api/v1/config` still come from `APP_PUBLIC_BASE`; bad values fail at boot (`03_ct6_portal_control_origin.md`).
- [ ] **Split mode proven in a real browser, locally**: the smoke runner logs in across the two domains, records `Sec-Fetch-Site`, shows an app-set cookie does not reach the control host, and exercises silent refresh; the connections lane completes the consent journeys with the opener on the apps domain; the answer to "does a browser treat the two `.localhost` names as cross-site" is recorded, with the same-site fallback pair run as the negative control (`04_ct7_smoke_runner_split_mode_and_connections_lane.md`).
- [ ] **The legacy redirect**: `EDGE_LEGACY_APP_REDIRECT`, default off, a 307 for GET/HEAD to live apps, never for `_` paths, with `helix.edge.legacy_app_redirects` as the sunset signal (`05_ct8_legacy_app_host_redirect.md`).
- [ ] **Bicep, DNS and certbot for the apps domain**: `hostedAppsDomain`, `hostedAppsTlsBound` and `legacyAppRedirect`, a second DNS zone, a second wildcard binding and a second certbot instance, unset equals today's values, compile-checked only (`06_ct9_bicep_dns_and_certbot_for_apps_domain.md`).
- [ ] **Docs, ADR amendments and operator rollout notes**: every new setting documented with its default and failure direction; rollout notes for all three containment parts with operator-run steps marked; one extended ADR-0028 amendment, an ADR-0019 pointer, an ADR-0044 amendment (`07_ct10_docs_adr_amendments_and_rollout_notes.md`).

### Quality Standards

- [ ] **Gate**: `./check-and-lint.sh` passes in the dev container before every commit; `just dev smoke` passes for every change that touches the edge, portal or smoke tooling (CT-4 to CT-8); `just infra build` passes for CT-9; `pnpm lane:connections` runs in single-domain and split mode for CT-7.
- [ ] **The old layout is the first test**: the single-domain suites pass unmodified (the only edits to existing tests are listed in CT-5's `results/`), and the Bicep output with the new parameters unset differs from `main` only in the ways CT-9's annotated diff accounts for.
- [ ] **Telemetry ships with the change**: the one new instrument (`INSTR_LEGACY_APP_REDIRECTS`) and its span are constants in `packages/shared/src/telemetry.ts`, asserted with `startRecordingTelemetry`, covered by `spanRedaction.test.ts` and `traceBoundary.test.ts`, and listed in `docs/features/observability.md`. Names are checked against what `01_spend_controls` and `03_csp_and_headers` added.
- [ ] **Stricter behavior is per install**: the split, the redirect and the portal base are settings with the strict or single-domain value as the default.
- [ ] **Azure and browser honesty**: nothing is applied to Azure or a live install. Two wildcard bindings on one Container App, certbot double instantiation at runtime, certificate issuance, the ADR-0044 canary with two bindings, DNS delegation, the Public Suffix List, and Safari, Firefox and Chrome tracking-protection behavior on real domains are labeled unverified in the code, the docs and `results/`.

### Completion Criteria

- [ ] All tasks in sequence completed successfully
- [ ] Quality verification tasks passed
- [ ] Code review completed and issues addressed (the CT-5 review pass in particular: the handoff, `classifyHost`, `controlOrigin` and the ten tests)
- [ ] Documentation updated

## Task Alignment

> **Note:** Task files define HOW. Each task maps to one change in the design's "Work breakdown" section. This sequence has seven task files; there are no separate testing, review, iterate or commit task files.

| Task | Task Objective | Contribution to Sequence Goal |
|------|----------------|-------------------------------|
| 01_ct4_second_loopback_dev_domain.md | Give the dev container a second domain that resolves to 127.0.0.1, a matching certificate and resolver helpers, switched by `HELIX_APPS_DOMAIN`, with no change when it is unset (CT-4). | Makes the split testable locally (decision V2) before any edge code changes. |
| 02_ct5_edge_control_and_apps_domain_split.md | Add `EDGE_CONTROL_DOMAIN`, a control-aware `classifyHost`, `controlOrigin()`, boot validation and the ten adversarial tests, and run a dedicated review pass on the handoff (CT-5). | The core of the sequence: the edge stops treating `auth.<appsDomain>` as an auth host and builds control and app origins from separate config. |
| 03_ct6_portal_control_origin.md | Add the optional `CONTROL_PUBLIC_BASE` so the vendor callback URL follows the control domain while app URLs follow `APP_PUBLIC_BASE` (CT-6). | Keeps the portal and the edge agreeing on the callback URL, and fails closed when they do not. |
| 04_ct7_smoke_runner_split_mode_and_connections_lane.md | Run the split layout end to end in Chromium: login across both domains, `Sec-Fetch-Site` recording, cookie scope, silent refresh, and the connections lane in split mode (CT-7). | The local evidence that the handoff works across two sites and that app-set cookies stay off the control hosts; records whether `.localhost` names are cross-site. |
| 05_ct8_legacy_app_host_redirect.md | Add the optional 307 from old `<slug>.<controlDomain>` URLs to the new app origin, with the redirect counter (CT-8). | Softens the URL change for existing installs and gives the operator a sunset signal. |
| 06_ct9_bicep_dns_and_certbot_for_apps_domain.md | Add `hostedAppsDomain`, the second gate, a second DNS zone, a second wildcard binding and a second certbot instance, compile-checked only (CT-9). | Makes the split deployable for an install, without touching one. |
| 07_ct10_docs_adr_amendments_and_rollout_notes.md | Document every setting, publish the operator rollout notes for all three parts, and write the ADR amendments (CT-10). | Turns the code into something an operator can adopt, and states what was and was not tested. |

## Dependencies

### Prerequisites (from other sequences)

- 03_csp_and_headers: CT-1 to CT-3 land first (plan.md orders the phases this way). This sequence edits the same files (`config.ts`, `test/config.ts`, `app.test.ts`, `serving/cspReport.test.ts`, `smoke.mjs`, `cdp.mjs`, `main.bicep`, the edge README, `configuration.md`), so every task re-reads them and uses the line numbers at 792557a only as a guide. CT-10 also takes the Part 2 operator notes that `03_csp_and_headers/03_ct3_enforce_img_src_and_object_src.md` leaves in its `results/`, and verifies the ADR-0009 amendment it writes.
- 02_network_egress: on installs that run the firewall, CT-9's second certbot instance needs the ACME, Azure Resource Manager and Entra hosts that task EG-6 adds to the apps subnet's list (`06_eg6_firewall_platform_lists_and_threat_intel.md`), so EG-6 must land first there. CT-10's ADR-0028 lines extend the amendment that `11_eg11_docs_and_adr_amendments.md` (EG-11) writes under.
- 01_spend_controls: `13_sp13_adr_and_docs.md` creates the shared ADR-0028 amendment heading and the "Upgrading to the LLM spend controls" section of `apps/docs/src/deploy/updates.md`; CT-10 extends the former and sits beside the latter.

### Provides (to other sequences)

- None. This is the last sequence of the phase. It hands operators the code, the Bicep, the docs and the rollout notes; rolling out to the two live installs is outside the festival.

## Working Directory

Target project: `projects/helix` (relative to campaign root)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| A change in the OIDC handoff path opens an auth bypass, an open redirect or an auth-host impersonation. | Low | High | Auth-host classification has one exact match; `publicOrigin` throws for control labels; the ten adversarial tests run in both layouts; a dedicated review pass with revert-checks is a Done-When item; the old suites must pass unmodified. |
| Browsers may treat `helix-apps.localhost` and `local.helix.azxlabs.io` as the same site, so the local cross-site tests prove less than the design hopes. | Med | Med | CT-7 reads `Sec-Fetch-Site` and records the answer. If it says `same-site`, the cross-site checks are skipped as unverified and the same-site fallback pair carries the host-routing, handoff and Origin tests. |
| Safari ITP, Firefox ETP or Chrome bounce-tracking mitigations treat the auth host's redirect as a tracker and break sign-in (a login loop at `/start`). | Med | High | Cannot be proven on loopback names. Stated as unverified; the rollout notes make a staging check in all three browsers an operator-run step before apps move. |
| Container Apps may refuse two wildcard custom domains on different certificates on one app, or two certbot jobs may collide while binding on the edge. | Med | High | Names are made distinct (the collision the design guessed at is real, `certbot.bicep:80` and `:148`), the second job is offset by half an hour, and the second gate parameter keeps a bad bind from failing the whole apply. Everything remains unverified in Azure; the design's fallback is a different binding design, decided when an operator reports. |
| A delegated apps subdomain that is not on the Public Suffix List is the same site as the control domain, so the cookie-bomb protection is silently absent. | Med | High | The edge logs the split but cannot check the list without a new dependency; docs and rollout notes state the requirement as operator-run; the same-site fallback pair in CT-7 demonstrates the leak. |
| App URLs change on cutover; sessions on old hosts are lost; apps with hard-coded hosts break. | High | Med | The optional legacy redirect (GET/HEAD only) and its sunset counter; the rollout notes list the compatibility breaks and the order that avoids TLS failures (DNS and certificates first, the portal flip last). |
| Edge and portal disagree about the control domain (only one side set). | Med | Med | One Bicep parameter sets both; the portal validates its own pair; a callback on the wrong host gets a 404 at the edge and a redirect mismatch at the vendor, so nothing leaks. The portal cannot detect a one-sided setting, which CT-6 says plainly. |
| The design and the code differ in places this plan found: nine auth-host call sites not eight, `dev-api` not reserved, `config.test.ts:653` and `:666` assert the function being changed, the consent popup has no smoke driver, `undici` is not resolvable from the repo root, the fallback pair needs two more certificate names, the compiled Bicep cannot be byte-identical, and the sunset step would remove the binding `auth.` rides on. | High | Low | Each task states the difference and follows the code; `results/` records it. |
| The browser checks SKIP without a cached Chromium, a certificate flag or name resolution. | Med | Med | A SKIP is never counted as a pass; CT-4 and CT-7 list which claims are unproven when that happens. |

## Progress Tracking

### Milestones

- [ ] **Milestone 1**: CT-4 merged and CT-5 merged with its review pass: the dev domain exists, the edge splits control and apps hosts, and the adversarial tests pass in both layouts.
- [ ] **Milestone 2**: CT-6, CT-7 and CT-8 merged: the portal agrees with the edge, split mode works end to end in Chromium and the connections lane, and the `Sec-Fetch-Site` answer is recorded.
- [ ] **Milestone 3**: CT-9 and CT-10 merged: the Bicep compiles with and without the new parameters, and the docs, ADR amendments and operator rollout notes are published with every unverified item named.

## Quality Gates

### Testing and Verification

- [ ] All unit tests pass
- [ ] Integration tests complete (the flow and portal route tests need the dev container's Postgres and the ephemeral dev IdP)
- [ ] No new work on the request hot path when the split and the redirect are off: one extra string argument to `classifyHost`, no hook registered

### Code Review

- [ ] Code review conducted
- [ ] Review feedback addressed
- [ ] Standards compliance verified

### Iteration Decision

- [ ] Need another iteration? Decided at the iterate gate
- [ ] If yes, new tasks created: Decided at the iterate gate
