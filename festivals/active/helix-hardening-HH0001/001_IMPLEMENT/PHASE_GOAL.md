---
fest_type: phase
fest_id: 001_IMPLEMENT
fest_name: IMPLEMENT
fest_parent: helix-hardening-HH0001
fest_order: 1
fest_status: completed
fest_created: 2026-10-08T19:45:32.311381-06:00
fest_updated: 2026-10-10T18:57:59.666549-06:00
fest_phase_type: implementation
fest_tracking: true
---


# Phase Goal: 001_IMPLEMENT

**Phase:** 001_IMPLEMENT | **Status:** Pending | **Type:** Implementation

## Phase Objective

**Primary Goal:** Implement pre-planned features and functionality

**Context:** Planning is complete in workflow/design/helix-spend-containment-egress (frame, three designs, review, decisions, plan). This phase implements the 34 changes in the plan's order.

## Required Outcomes

Deliverables this phase must produce:

- [ ] 01_spend_controls: SP-1 to SP-13 merged on the private remote, each meeting its "Done when" in 01-spend-controls.md
- [ ] 02_network_egress: EG-1 to EG-11 merged, each meeting its "Done when" in 03-egress-network-control.md
- [ ] 03_csp_and_headers: CT-1 to CT-3 merged, each meeting its "Done when" in 02-app-containment.md
- [ ] 04_domain_split: CT-4 to CT-10 merged, each meeting its "Done when" in 02-app-containment.md

<!-- Add more required outcomes as needed -->

## Quality Standards

Quality criteria for all work in this phase:

- [ ] `./check-and-lint.sh` passes in the dev container before each commit
- [ ] Changes to running services pass `just dev smoke`
- [ ] Telemetry and adversarial tests ship in the same change as the seam they cover
- [ ] Azure-only behavior is labeled unverified in Azure

<!-- Add more quality standards as needed -->

## Sequence Alignment

| Sequence | Goal | Key Deliverable |
|----------|------|-----------------|
| 01_spend_controls | Stop abandoned calls, charge what was used, cap the platform | SP-1 to SP-13 |
| 02_network_egress | Network control behind the SSRF filter | EG-1 to EG-11 |
| 03_csp_and_headers | Close the header and image exfiltration paths | CT-1 to CT-3 |
| 04_domain_split | Serve hosted apps from their own domain | CT-4 to CT-10 |

<!-- Add rows as sequences are created -->

## Pre-Phase Checklist

Before starting implementation:

- [ ] Planning phase complete
- [ ] Architecture/design decisions documented
- [ ] Dependencies resolved
- [ ] Development environment ready

## Phase Progress

### Sequence Completion

- [ ] 01_spend_controls
- [ ] 02_network_egress
- [ ] 03_csp_and_headers
- [ ] 04_domain_split

<!-- Track sequence completion here -->

## Notes

Work happens in `projects/helix` on a branch per task, committed with `fest commit`. CI is off, so the dev container gate is the only gate. Tests need Postgres and Azurite, which the dev container provides.

---

*Implementation phases use numbered sequences. Create sequences with `fest create sequence`.*