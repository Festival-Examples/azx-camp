# SP-13 result: ADR-0051, rollout notes, and docs

**Result: done.** Documentation only. New `docs/adr/0051-llm-admission-control.md` (install default, platform ceiling, leases, deadline, cut-call charging, overshoot bound, residuals, rejected options) with a row in `docs/adr/README.md`. Amendments: ADR-0002 (one combined amendment for the definer function and the lease table), ADR-0011 (points at the lease store), ADR-0028 (admission settings are per-install; the egress and domain work will extend this same amendment). `apps/docs/src/deploy/updates.md` gains "Upgrading to the LLM spend controls" for operators, with rollback steps and an unverified-in-Azure list. `docs/features/llm-gateway.md`, `docs/features/capabilities-and-manifests.md`, and `infra/azure/README.md` updated. The closed client-disconnect item was deleted from `TODO.md` (the repo deletes finished items).

ADR-0051 records the classifier behavior from SP-6's review: a requested unset LLM cap counts as possibly unlimited, because the portal cannot read the edge's install default.

## Evidence

- Gate: all 236 test files passed, docs build green (`sp13-gate.txt`).
- `sp13-knob-check.sh` / `sp13-knob-check.txt`: every new setting is documented (OK).
- `sp13-rollout-sql.txt`: the operator query that finds approved apps with no budget, probed in a transaction on the dev database.
- `just infra build` not needed: no Bicep file changed.

## Note

The agent wrote the knob check and rollout-SQL files into this results folder although its instructions said not to edit festival files. The files are evidence, so they are kept.

## Executor

cursor-agent, `composer-2.5`, 76 tool calls.
