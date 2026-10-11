# SP-6 result: install default for an unset LLM budget

**Result: done, with one change from the design.** An app with an LLM grant and no `dollarsPerDay` is now held to the install default, `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` (default $50, the approval baseline; `0` means no default, for one-organization installs). Enforcement is in `apps/edge/src/gateway/llm.ts`: `cap = entry.llm.dollarsPerDay ?? config.llm.defaultDollarsPerDay`, checked when `cap > 0`. The setting is parsed and validated in `apps/edge/src/config.ts`, logged at boot by the edge and the dev gateway, exposed as the Bicep parameter `llmDefaultDollarsPerDay`, and documented for operators and app authors (`.env.example`, `apps/docs`, `docs/features`, `packages/deploy-skill/SKILL.md`).

## Change from the design, made in review

The agent's first version made the approval classifier treat an unset LLM cap as the $50 baseline on both sides, so removing an explicit cap needed no approval. The classifier runs in the portal, which cannot see the edge's install default. On an install whose operator set the default to 0 (unlimited) or above $50, an app author could remove their cap without approval and become unlimited. Review changed the classifier (`packages/shared/src/approval.ts`) to compare asymmetrically: a requested unset cap counts as unlimited, an effective unset cap as the $50 baseline. Removing an LLM cap needs approval again; unset to more than $50 is elevated; unset to $50 or less is baseline. Tests and help text were updated to match. Recorded in `workflow/design/helix-spend-containment-egress/decisions.md`.

## Evidence

- Tests: `apps/edge/src/config.test.ts` (default, explicit value, 0, invalid values, blank, dev gateway), `apps/edge/src/gateway/llm.test.ts` (day and burst caps from the default, explicit cap honored, 0 unlimited), `packages/shared/src/approval.test.ts` (cap removal elevated, unset to 100 elevated, unset to 50 baseline, unset to unset no delta, data and fetch removal still elevated).
- Gate: all 232 test files passed (`sp6-gate.txt`).
- `just infra build`: passed (`sp6-infra-build.txt`).
- Smoke: 31 passed, 0 failed, 1 skipped (`sp6-smoke.txt`).

## Not done here

- The portal's Overview and Usage screens still show no cap for an app with an unset budget; the edge enforces the default but the portal does not read it. Tracked for SP-13's docs and as a portal follow-up.
- Unverified in Azure: the Bicep parameter reaching the edge and dev-gateway containers on a deployed install (compile-checked only).

## Executor

cursor-agent, `composer-2.5`: 113 tool calls, plus 34 for the review fix.
