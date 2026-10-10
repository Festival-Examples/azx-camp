# Iterate batch IT-3: approval for new LLM grants and at app creation

Fixes review findings S-5 and S-6, per the owner's decision in `decisions.md`.

- **S-5.** `packages/shared/src/approval.ts`: when an LLM grant is being added, the budget delta is evaluated even when both values are undefined, with a requested unset cap counting as unlimited, so a fresh LLM grant with no budget is elevated. A fresh grant at or under $50 is baseline; above is elevated; changes to an existing grant are unchanged.
- **S-6.** `POST /api/v1/apps` (`apps/portal/src/routes/apps.ts`) now runs `gateCapabilitiesAtCreate` (`apps/portal/src/approvals/service.ts`): `classifyChange(EMPTY, requested)`, provider-binding validation, the baseline part stored on the new app, and an approval request opened for the elevated part, in one transaction. The CLI and the portal SPA read the result; docs updated (`docs/features/capabilities-and-manifests.md`, `docs/features/registry-and-deploys.md`).

## Changes made in review

- **Backward-compatible response.** The agent's first version answered `{ app, applied, pending }`. The published CLI (`@azx-pbc/helix-cli` 0.4.0) parses the create response with `AppSchema` at the top level, so every installed CLI, and any agent following the deploy skill, would have failed on `helix create` against an updated portal. The response is now the app object at the top level plus additive `applied` and `pending` fields (`CreateAppResultSchema = AppSchema.extend(...)` in `packages/shared/src/api.ts`); a test parses it with the plain `AppSchema`.
- **Browser lane.** The revert missed `apps/connections-lane/src/world.ts` (the lane is not part of the standard gate), so all 10 lane journeys failed reading `.app.id`. The file was restored to `main`'s version; the lane passes.

## Evidence

- `approval.test.ts` (fresh LLM grant cases), `apps.test.ts` (baseline-only create stores everything; an elevated budget stores the baseline part and opens a pending request; a fresh LLM grant with no budget opens a pending request), the old-client parse test, `client.test.ts`.
- Gate: 237 of 237 test files (`it3-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`it3-smoke.txt`). Browser lane: 10 passed (`it3-browser-lane.txt`).

## Follow-up found during this batch

`POST /api/v1/apps` with `visibility: public` still does not go through the visibility classifier, so an author can create a public app without the approval a later change to public would need. Same class as S-6 but outside the spend controls; filed as a follow-up for the owner to schedule.

## Executor

cursor-agent, `composer-2.5`: 144 tool calls, plus 65 for the compatibility fix.
