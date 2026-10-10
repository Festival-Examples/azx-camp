---
fest_type: gate
fest_id: 14_testing.md
fest_name: Testing and Verification
fest_parent: 01_spend_controls
fest_order: 14
fest_status: completed
fest_autonomy: medium
fest_gate_id: testing
fest_gate_type: testing
fest_managed: true
fest_created: 2026-10-08T20:21:49.590143-06:00
fest_updated: 2026-10-09T18:25:42.859689-06:00
fest_tracking: true
fest_version: "1.0"
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