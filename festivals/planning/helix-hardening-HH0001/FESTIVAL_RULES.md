# Festival Rules: helix-hardening

Every task in this festival changes `projects/helix`. These rules come from the repository's own instructions (`projects/helix/AGENTS.md`) and from the decisions in `workflow/design/helix-spend-containment-egress/decisions.md`. Read both before the first task.

## Source of truth

- Each task implements one change from a design's "Work breakdown" section: `01-spend-controls.md` (SP-), `02-app-containment.md` (CT-), or `03-egress-network-control.md` (EG-), all under `workflow/design/helix-spend-containment-egress/`.
- The design is the specification. If the code disagrees with the design, stop and record the disagreement in the task's results before changing course.
- `plan.md` in the same directory holds the order, the cross-sequence dependencies, and what is out of scope.

## The gate

- Run `./check-and-lint.sh` (or `just check`) in the dev container before every commit, and get a clean pass. It runs typecheck, lint, the planning-identifier scan, format, the docs build, and the full test suite. The tests need Postgres and Azurite, which only the dev container provides.
- CI is off. Nothing else checks a change, so a skipped gate is an unchecked change.
- A change to the edge, portal, or egress also passes the smoke runner: `just dev smoke` (`node .claude/skills/run-helix/smoke.mjs`).
- Bicep changes pass `just infra build`.

## Repository rules that apply to every task

- **The edge is the trusted path.** No new runtime dependency in `apps/edge` without written justification. No ORM in the edge. Never block the event loop; pipe streams, never buffer LLM responses.
- **`packages/secret-store` stays dependency-free.**
- **`helix_edge` has no grant on `app_secrets`.** Any change to edge database grants extends `role-split.integration.test.ts` and records an ADR-0002 amendment.
- **Telemetry ships with the change.** A new route, hop, loop, failure mode, or decision point adds its instrumentation in the same change. Names are constants in `packages/shared/src/telemetry.ts`. Attributes and dimensions are bounded and non-personal (`appId` yes, `userOid` never). Never record a whole URL. Egress span attributes stay a hardcoded allowlist, and egress spans record no exception. Assert it with `startRecordingTelemetry`, extend the adversarial suites rather than routing around them, and add the signal to `docs/features/observability.md`. Check new names against those added earlier in this festival.
- **Security-relevant changes ship adversarial tests in the same change.** The OIDC handoff (CT-5) gets a dedicated review pass.
- **zod at every boundary**, ESM with `.js` import specifiers, `import type` for type-only imports.
- **Comments** explain a constraint, a failure case, or a non-obvious choice. Keep rejected alternatives in ADRs, not in comments.

## Scope limits

- Do not change the live installs, their deployments repo, or anything in Azure. Their adoption steps go in operator rollout notes.
- Anything only Azure can prove is labeled **unverified in Azure** in code comments, docs, and rollout notes.
- Every stricter behavior is a per-install setting with the strict value as the default.
- Do not add features beyond the task. Deferred items are listed in `plan.md`.

## Process

- One branch per task in `projects/helix`, named after the change ID (for example `sp-1-hangup-characterization`).
- Commit with `fest commit -m "..."` from the festival. Never raw `git commit` in the camp.
- Put test output and review notes in the sequence's `results/` directory.
- Do not estimate durations.

## When to stop and ask

- The design and the code disagree in a way that changes behavior.
- A change needs a new runtime dependency in the edge or `secret-store`.
- A change would alter a decision recorded in `decisions.md` or an accepted ADR beyond the amendment the design names.
