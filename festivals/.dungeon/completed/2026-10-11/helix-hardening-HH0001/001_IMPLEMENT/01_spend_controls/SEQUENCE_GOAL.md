---
fest_type: sequence
fest_id: 01_spend_controls
fest_name: spend controls
fest_parent: 001_IMPLEMENT
fest_order: 1
fest_status: completed
fest_created: 2026-10-08T19:47:11.805968-06:00
fest_updated: 2026-10-10T01:26:38.089599-06:00
fest_tracking: true
---


# Sequence Goal: 01_spend_controls

**Sequence:** 01_spend_controls | **Phase:** 001_IMPLEMENT | **Status:** Pending | **Created:** 2026-10-08T19:47:11-06:00

## Sequence Objective

**Primary Goal:** Make a hang-up stop the vendor call, make cut and failed LLM calls cost something in the ledger, give every unset budget an install default, and bound the platform's daily spend and in-flight calls across edge replicas, delivered as 13 reviewable changes (SP-1 to SP-13 in `workflow/design/helix-spend-containment-egress/01-spend-controls.md`).

**Contribution to Phase Goal:** The phase goal lists "01_spend_controls: SP-1 to SP-13 merged on the private remote, each meeting its Done when". This sequence delivers that outcome and is the first of the four, so it also sets the pattern the other three follow for telemetry names, ADR amendments, and the edge database surface.

## Success Criteria

The sequence goal is achieved when:

### Required Deliverables

- [ ] **Hang-up reaches the vendor call**: egress `POST /proxy` aborts the upstream request when the edge hangs up, including before the upstream headers arrive, for both `llm` and `fetch`; a characterization test records what already worked after the first byte.
- [ ] **Cut and failed calls are charged**: a hang-up, or an error after an upstream 200 with at least one event, writes a ledger row with a measured, estimated or mixed cost, marked in `errorDetail`; the daily gate then refuses the next request when the charge crosses the budget.
- [ ] **No admitted app is unbounded**: an unset `dollarsPerDay` is enforced at an install default of 50 (per-install setting), and the approval classifier and every doc say so.
- [ ] **Platform daily ceiling**: a `SECURITY DEFINER` aggregate function with an owner policy, a cached, fail-closed ceiling check that refuses with `503 capability_unavailable` and `retry-after`, a boot self-test, a Bicep default, and an alert.
- [ ] **Concurrency caps across replicas**: a Postgres lease store with TTL, per-app and per-user caps on the LLM path, a per-replica limit, a wall-clock call deadline, and an optional per-app cap on the fetch path, each with an off value.
- [ ] **Records**: ADR-0051, the ADR-0021, ADR-0002, ADR-0011 and ADR-0028 changes, the operator rollout notes, and `TODO.md` corrected.

### Quality Standards

- [ ] **Gate**: `./check-and-lint.sh` passes in the dev container before every commit, and `just dev smoke` passes for every change to the edge, portal or egress.
- [ ] **Telemetry and adversarial tests ship with the seam**: names are constants in `packages/shared/src/telemetry.ts`, asserted with `startRecordingTelemetry`, listed in `docs/features/observability.md`; no `userOid`, URL, prompt text or scope string in any attribute; the adversarial suites are extended rather than routed around.
- [ ] **Edge database surface is pinned**: the definer function and the lease table are covered in `role-split.integration.test.ts` and amended in ADR-0002, and the edge keeps no grant on `app_secrets`.
- [ ] **Azure honesty**: anything only Azure can prove is labeled unverified in Azure in code comments, docs and the rollout notes; Bicep is compile-checked with `just infra build`.

### Completion Criteria

- [ ] All tasks in sequence completed successfully
- [ ] Quality verification tasks passed
- [ ] Code review completed and issues addressed (the definer function and owner policy get the dedicated review the auth code gets)
- [ ] Documentation updated

## Task Alignment

> **Note:** Task files define HOW. Each task maps to one change in the design's "Work breakdown" section.

| Task | Task Objective | Contribution to Sequence Goal |
|------|----------------|-------------------------------|
| 01_sp1_hangup_characterization_test.md | Record, with a real-socket test, whether a hang-up after the first response byte already tears down the vendor call (SP-1). | Settles the design's one unverified claim before any code changes and fixes how the leak is described. |
| 02_sp2_egress_upstream_abort.md | Pass the edge's hang-up into the egress upstream call through an `AbortController` fed by the response `close` event (SP-2). | Closes the pre-header window and stops egress holding sockets for abandoned calls, for LLM and fetch. |
| 03_sp3_cut_stream_usage_estimate.md | Add `estimateCutUsage` and `BYTES_PER_TOKEN` to `packages/shared` (SP-3). | The single place for the heuristic that prices a call the vendor never finished reporting. |
| 04_sp4_provider_usage_events.md | Yield a `usage` event from the Anthropic and OpenAI mappers as soon as counts are known (SP-4). | Gives a cut call whatever measured counts arrived, so the estimate fills only the gaps. |
| 05_sp5_charge_cut_and_failed_calls.md | Charge hang-ups and post-200 errors in the ledger, marked measured, estimated or mixed (SP-5). | Makes the existing per-app gate see abandoned calls; the highest-value change on its own. |
| 06_sp6_default_llm_budget.md | Enforce an install default for an unset `dollarsPerDay` and align the classifier and text (SP-6). | Removes the "approved but unlimited" state with one comparison and no data migration. |
| 07_sp7_admission_denial_throttle.md | Throttle per-app `quota_blocked` rows and count every admission denial (SP-7). | Stops denials becoming a write flood and gives operators a bounded counter before the ceiling arrives. |
| 08_sp8_platform_spend_definer_function.md | Add `platform_llm_spend_micro_usd` and the owner policy on `gateway_calls`, amend ADR-0002 (SP-8). | Lets the edge read a cross-app sum without widening what it can read per app. |
| 09_sp9_platform_daily_ceiling.md | Refuse new LLM calls platform-wide once the day's spend reaches the ceiling, with a cache, a boot self-test, Bicep and an alert (SP-9). | The hard backstop that bounds damage when the per-app estimate is wrong. |
| 10_sp10_inflight_lease_store.md | Add the `inflight_leases` table and the Pg and in-memory lease stores (SP-10). | The cross-replica primitive the concurrency caps are built on. |
| 11_sp11_llm_concurrency_caps_and_deadline.md | Cap in-flight LLM calls per app, per user and per replica, add the call deadline, release after the row is written (SP-11). | Bounds overshoot to `cap x worst-case call cost` and bounds how long one call can run. |
| 12_sp12_fetch_lease_caps.md | Optionally cap concurrent fetch calls per app with the same store (SP-12). | Bounds the egress sockets one app can hold; off unless configured. |
| 13_sp13_adr_and_docs.md | Write ADR-0051, the ADR pointers and amendments, the operator rollout notes, and correct `TODO.md` (SP-13). | Leaves the decisions, residuals and upgrade steps on record for operators of existing installs. |

## Dependencies

### Prerequisites (from other sequences)

- None. This sequence has no prerequisite from 02_network_egress, 03_csp_and_headers or 04_domain_split.

### Provides (to other sequences)

- **New constants in `packages/shared/src/telemetry.ts`** (`INSTR_EGRESS_UPSTREAM_ABORTS`, `INSTR_GATEWAY_CUT_CHARGES`, `INSTR_GATEWAY_ADMISSION_DENIED`, `INSTR_GATEWAY_PLATFORM_SPEND_RATIO`, `ATTR_USAGE_BASIS`, `ADMISSION_DENIAL_REASONS`, `CUT_CHARGE_BASES`): used by 02_network_egress, 03_csp_and_headers and 04_domain_split, which must check their new names against these before adding any.
- **The first ADR-0028 amendment** (per-install settings): used by 02_network_egress (its documentation task) and 04_domain_split (its documentation task), which extend this one amendment instead of adding another.
- **The ADR-0002 amendment and the `role-split.integration.test.ts` cases** for the definer function and the lease table: the pattern 02_network_egress and 04_domain_split follow for any change to edge database grants.
- **Bicep parameter and env-wiring pattern** (`fetchMaxBodyMb` style, the edge and dev-gateway env blocks, the alert rule in `modules/alerts.bicep`): reused by 02_network_egress and 04_domain_split for their own parameters and rules.

## Working Directory

Target project: `projects/helix` (relative to campaign root)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| The cut-stream estimate is a heuristic and can be wrong by tens of percent (non-Latin text, code, reasoning models whose hidden tokens are billed and never streamed). | High | Med | Every row says `usage=estimated` or `mixed`; over-charging a hang-up only hits that app's own budget; the platform ceiling is the backstop; `BYTES_PER_TOKEN` is one tunable constant. |
| The owner policy on `gateway_calls` is missing or bound to the wrong role, so the definer function returns zeros and silently disables the ceiling. The dev owner is a superuser and hides the fault locally. | Med | High | A test that runs the exact migration SQL under a non-bypass owner; a catalog check of the policy against the function owner; a boot self-test that fails the edge when the ceiling is on and the database is misconfigured; production role confirmed against `infra/azure/sql/01-roles.sql` before writing the migration. |
| Widening the edge database role (the definer function, the lease table) weakens the trusted path. | Low | High | Aggregate-only function returning two numbers; leases carry no app data; grants pinned in `role-split.integration.test.ts`; ADR-0002 amended; dedicated review pass. |
| A replica dies or a release fails, leaking lease slots. | Med | Low | Rows expire at `expiresAt`; expired leases never count even before a sweep; TTL is the call deadline plus a grace period, so a live call never loses its slot. |
| The default budget is raised above the baseline by an operator, so an unset grant is enforced above what the approver saw. | Low | Med | The knob is not clamped (stated in the config comment and ADR-0051); the boot log prints the effective default. |
| Existing approved apps with no budget start being refused when the default deploys. | Med | Med | Operator rollout notes: list the affected apps first, set explicit numbers or raise the default for a transition. |
| A hang-up is mistaken for a request-cap trip (or the reverse), swallowing a 413 or charging a cap trip as a hang-up. | Low | Med | The abort listener ignores a closed response when the request cap tripped; dedicated tests on both sides. |
| Starting values (50 per app, 100 per day platform, 10 per app, 3 per user, 200 per replica, 10 minutes, 3 bytes per token) are guesses. | High | Low | Each is a setting or a named constant with an off value (the deadline excepted); stated as unmeasured in ADR-0051. |
| Bicep wiring, the alert query, and abort propagation through the Container Apps ingress cannot be proven locally. | High | Med | Compile-checked with `just infra build`; labeled unverified in Azure in code, docs and rollout notes. |

## Progress Tracking

### Milestones

- [ ] **Milestone 1**: Part 1 landed (01_sp1 and 02_sp2): hang-up propagation characterized and fixed.
- [ ] **Milestone 2**: Part 2 landed (03_sp3 to 05_sp5): cut and failed calls are charged and the exploit test is green.
- [ ] **Milestone 3**: Part 3 landed (06_sp6 to 13_sp13): default budget, platform ceiling, concurrency caps, deadline, ADR-0051 and rollout notes.

## Quality Gates

### Testing and Verification

- [ ] All unit tests pass
- [ ] Integration tests complete (Postgres and Azurite, in the dev container)
- [ ] Performance benchmarks met: not applicable; the cost of the platform sum is recorded with an `EXPLAIN` in `results/`

### Code Review

- [ ] Code review conducted
- [ ] Review feedback addressed
- [ ] Standards compliance verified

### Iteration Decision

- [ ] Need another iteration? Decided at the iterate gate
- [ ] If yes, new tasks created: None until the iterate gate decides