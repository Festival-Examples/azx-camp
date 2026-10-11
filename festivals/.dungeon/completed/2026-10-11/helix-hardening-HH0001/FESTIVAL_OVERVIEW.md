# Festival Overview: helix-hardening

## Problem Statement

**Current State:** Helix (`projects/helix`, private fork of AZX-PBC-OSS/helix) has three confirmed gaps (workflow/design/helix-spend-containment-egress/00-frame.md). A cut LLM stream is charged $0 and budgets are optional; the edge-to-egress hang-up does not reach the vendor before the first response byte. Egress relies on the application SSRF filter alone: no NSGs, the firewall allows every FQDN, and both live installs run without it. Hosted apps share a registrable domain with auth and the portal, and the CSP leaves image and navigation exfiltration channels open.

**Desired State:** The three decided designs are implemented as 34 reviewable changes with tests, telemetry, docs, ADR amendments, and operator rollout notes.

**Why This Matters:** These are the spend, isolation, and egress controls a platform hosting untrusted AI-generated apps depends on. They were rated High or Medium in the exploration (`workflow/explore/helix-repo-exploration/findings.md`, blockers 5, 6, 7, 10).

## Scope

### In Scope

- Spend controls: workflow/design/helix-spend-containment-egress/01-spend-controls.md, work breakdown SP-1 to SP-13
- Network egress control: workflow/design/helix-spend-containment-egress/03-egress-network-control.md, EG-1 to EG-11
- CSP and proxied-header tightening: workflow/design/helix-spend-containment-egress/02-app-containment.md, CT-1 to CT-3
- App/control domain split: workflow/design/helix-spend-containment-egress/02-app-containment.md, CT-4 to CT-10
- Tests, telemetry, docs, ADR amendments, and operator rollout notes for all of the above

<!-- Add more items as needed -->

### Out of Scope

- Rolling anything out to the two live installs or touching their deployments repo (decision D2 revised)
- Deploying to Azure; Azure-only behavior is labeled unverified (decision V4)
- Disclosure to or coordination with AZX (decision V3)
- Re-enabling CI or making the fork public (decision V1)
- The deferred items in plan.md: portal approver note for firewall installs, `ssrf.reason` span attribute, CSP report rate limit, NSG on the shared apps subnet

<!-- Add more items as needed -->

## Planned Phases

### 001_IMPLEMENT

Four sequences in the agreed order: 01 spend controls, 02 network egress, 03 CSP and headers, 04 domain split. Each task is one change from a design's work breakdown, sized for one pull request.

<!-- Add more phases as they're planned -->

## Notes

- Source of truth: workflow/design/helix-spend-containment-egress/plan.md (order, dependencies, rules), decisions.md, review.md, and each design's "Work breakdown" section.
- Cross-sequence dependencies: CT-9 needs EG-6 on installs that run the firewall; EG-11 and CT-10 write one shared ADR-0028 amendment; SP-8 and SP-10 widen `helix_edge` and must extend `role-split.integration.test.ts`.
- Open items settled inside tasks: the production migration owner role (SP-8), `.localhost` cross-site behavior (CT-7), Azure wildcard and certbot naming (CT-9, unverified in Azure).

<!-- fest:replay:start -->
## Execution replay

![Festival execution replay](festival-replay.gif)
<!-- fest:replay:end -->
