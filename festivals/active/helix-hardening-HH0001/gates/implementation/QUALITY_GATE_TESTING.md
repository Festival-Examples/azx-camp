---
# Template metadata (for fest CLI discovery)
id: QUALITY_GATE_TESTING
aliases:
  - testing-verify
  - qg-test
description: Standard quality gate task for testing and verification

# Fest document metadata (becomes document frontmatter)
fest_type: gate
fest_id: <no value>
fest_name: Testing and Verification
fest_parent: <no value>
fest_order: <no value>
fest_gate_type: testing
fest_autonomy: medium
fest_status: pending
fest_tracking: true
fest_created: 2026-10-08T19:45:32-06:00
---

# Gate: Testing and Verification

Verify all functionality implemented in this sequence works correctly.

## Test Categories

### Unit Tests

- [ ] All unit tests pass
- [ ] New/modified code has test coverage
- [ ] Tests are meaningful (not just coverage padding)

### Integration Tests

- [ ] Integration tests pass
- [ ] Components work together correctly

### Error Handling

- [ ] Invalid inputs are rejected gracefully
- [ ] Error messages are clear and actionable
- [ ] Recovery paths work correctly

## Verification

- [ ] Build completes without warnings
- [ ] No regressions introduced
- [ ] Coverage meets project requirements

## Helix commands

Run these from `projects/helix` inside the dev container (the tests need Postgres and Azurite). CI is off, so this gate is the only check.

- [ ] `./check-and-lint.sh` passes: typecheck, lint, refs, format, docs, tests
- [ ] `just dev smoke` passes when the sequence changed the edge, portal, or egress
- [ ] `just infra build` passes when the sequence changed Bicep
- [ ] New telemetry is asserted with `startRecordingTelemetry`, and the adversarial suites (`apps/edge/src/spanRedaction.test.ts`, `apps/edge/src/traceBoundary.test.ts`, `apps/egress/src/spanAttributes.test.ts`) still pass
- [ ] Anything only Azure can prove is listed as unverified in Azure in `results/`
- [ ] Command output is saved under the sequence's `results/` directory
