---
fest_type: task
fest_id: 13_sp13_adr_and_docs.md
fest_name: sp13 adr and docs
fest_parent: 01_spend_controls
fest_order: 13
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.337557-06:00
fest_tracking: true
---

# Task: sp13 adr and docs

## Objective

Write ADR-0051 for the LLM admission controls, add the remaining ADR pointers and amendments, put the operator rollout notes in the upgrade documentation, and remove the closed item from `TODO.md`. Implements SP-13 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `11_sp11_llm_concurrency_caps_and_deadline.md` (and through it every earlier task in this sequence): the ADR describes what was built, so write it from the merged code and the `results/` notes, not from the design.
- [ ] `docs/adr/0051-llm-admission-control.md` exists, follows the shape of the recent ADRs (`Status`, `Related`, `Context`, `Decision`, `Consequences`, `Considered and rejected`), and records the decisions listed in step 2. It supersedes nothing and extends ADR-0021.
- [ ] `docs/adr/README.md` has a row for 0051 (the table ends at line 67 with 0050).
- [ ] `docs/adr/0011-in-memory-rate-limiting.md` has a one-line pointer: the lease store follows the Postgres-counter choice in its Resolution.
- [ ] `docs/adr/0028-deployment-model-customer-deployed.md` gets the **first** amendment about per-install admission settings, written so the network-egress and domain-split tasks (later sequences) extend it instead of adding a second one. The festival plan says only one ADR-0028 amendment exists in the end.
- [ ] ADR-0002 already carries the platform-spend function amendment (the `08_sp8_platform_spend_definer_function.md` task) extended with the lease table (the `10_sp10_inflight_lease_store.md` task). Check that it reads as one amendment, not two.
- [ ] ADR-0021's amendment from the `05_sp5_charge_cut_and_failed_calls.md` task is cross-checked against the final behavior, including the deadline abort added later.
- [ ] The operator rollout notes are in the upgrade documentation (`apps/docs/src/deploy/updates.md`), in the six-step order of the design, with the unverified-in-Azure items named.
- [ ] Every knob this sequence added is present in `.env.example`, `apps/docs/src/deploy/configuration.md` and the feature docs, and every Bicep parameter is documented. Checked by the script in step 6, not by eye.
- [ ] `TODO.md` no longer carries the client-disconnect item. That file deletes finished work rather than checking it off (its own header says so), so "closed" means deleted, and the corrected scope lives in ADR-0051 and `docs/features/llm-gateway.md`.
- [ ] No claim in the new text is stronger than what was tested. Anything proven only locally is labeled; anything only Azure can prove is labeled **unverified in Azure**.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-13-adr-and-docs`. Read the sequence's `results/` directory first: the SP-1 characterization result decides how the egress hang-up is described, and the notes from each task list choices the owner has not confirmed (the per-replica default of 200, the fetch lease TTL, the deadline having no off value, the self-test refinement, the missing `finally` in the fetch handler). Carry those into the ADR's Consequences as stated choices.

2. `docs/adr/0051-llm-admission-control.md`. Model the layout on `docs/adr/0050-hosted-app-visitor-analytics.md` (headings: `Context` at line 6, `Decision` at line 12, `Consequences` at line 48). Header: `**Status:** Accepted _(recorded <date of the commit>)_` and a `**Related:**` line linking ADR 0021, 0002, 0011, 0028, 0037 and `docs/features/llm-gateway.md`. Use plain English and short paragraphs (`AGENTS.md`, "Documentation and comments"). Content:
   - **Context.** The ledger recorded $0 for a call the app abandoned, so the daily gate never moved; an approved app with no `dollarsPerDay` was unlimited; nothing bounded the platform's total or the number of calls in flight across the three edge replicas; the audience is treated as possibly hostile. State the corrected scope of the old leak: a hang-up after the upstream headers arrive already tore the vendor call down (the SP-1 result), the real gaps were the pre-header window and the $0 row.
   - **Decision**, numbered:
     1. An unset budget means the install default (`EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`, 50, the approval baseline), enforced for the day and the burst window; the classifier reads an unset LLM budget as the baseline; `0` makes it unlimited again for an install that chooses so.
     2. A platform-wide daily ceiling enforced at the gateway, required and on by default in deployed installs (Bicep supplies one tenth of `platformMonthlyUsdCap` per day), read through a `SECURITY DEFINER` aggregate function because RLS hides other apps' rows from the edge, cached per replica for 5 seconds, failing closed.
     3. Per-app and per-user in-flight caps as Postgres leases with a TTL (advisory-locked, all-or-none acquire), plus a per-replica semaphore for the replica's own sockets; anonymous callers get the app scope only; the lease is released after the ledger row is written; an optional fetch-path cap on the same store.
     4. A wall-clock call deadline (`EDGE_LLM_MAX_CALL_MS`), which also bounds the lease TTL.
     5. Every control is a per-install setting with the strict value as the default, so a one-organization install under ADR-0028 can relax it.
     6. Refusal semantics: `503 capability_unavailable` (no new shared error code), a `retry-after` to local midnight for the ceiling, throttled `quota_blocked` rows with an `errorDetail` marker for the budget and ceiling denials, metric and span only for concurrency refusals.
     7. Cut and failed calls are charged (measured else estimated, marked in the row); this is the ADR-0021 amendment, referenced here, and the egress upstream abort that closes the pre-header window.
   - **Overshoot bound.** Per app: at most `appCap x worst-case call cost` past `dollarsPerDay`, where worst-case cost is `maxTokens x output price` for the priciest allowed model. Platform: at most the ceiling plus the calls admitted before the cached read caught up. A bound, not an exact gate.
   - **Consequences**, including the residuals: reasoning tokens that are billed and never streamed are not charged; an edge crash mid-stream writes no row; the estimate (`BYTES_PER_TOKEN = 3`) can be off by tens of percent; every starting value is a guess until real traffic exists; the lease cap counts a fetch call for at most its TTL; the ceiling's `retry-after` assumes the edge and database share a time zone; behavior already approved apps get changes on deploy (see the rollout notes).
   - **Considered and rejected**, each with its reason: reserving the worst-case cost at admission (it turns block-new into block-if-it-might-exceed, an ADR-0021 change of substance, and `maxTokens` up to 128,000 would block most requests near the cap); a dedicated accumulator table (a second source of truth that can drift, and the edge would need `UPDATE`, which lets a compromised edge reset the ceiling; a shared `rate_counters` row overflows its `INTEGER` count at about $2,147 of micro-USD); the portal pushing a flag through the registry projection (a polling loop and stale data for a number the gateway should own); alert-only (ruled out by the possibly-hostile audience decision); a per-process semaphore as the only cap (the limit becomes `cap x replicas`, the failure ADR-0011 documents); requiring a number at approval (a portal change and a backfill, and the edge would still need the fallback); leaving unset unbounded and documenting it; counted tokens only (a hang-up before `message_start` still pays nothing); a pre-charge with a settling second row (two rows per call and a recovery story for orphans; the only option that also covers an edge crash, so revisit it if that residual matters).
   - Add the row to `docs/adr/README.md` after line 67: `| [0051](0051-llm-admission-control.md) | LLM admission control: install default budget, platform ceiling, in-flight caps | Accepted |`.

3. ADR pointers and amendments.
   - ADR-0011: in the Resolution section (line 34), add one sentence: the in-flight lease store (ADR-0051) follows the same choice, Postgres with no Redis, for the same reason.
   - ADR-0028: add `## Amendment (<date>): admission controls are per-install settings` after `Considered and rejected`. It says the platform ceiling, the concurrency caps, the install default budget and the call deadline are per-install settings, each with a strict default and an off value (the deadline excepted), so an install on the one-organization model can relax them; and that the later network-egress and domain-split work extends this same amendment. Link ADR-0051.
   - ADR-0002 and ADR-0021: read the existing amendments end to end and fix anything the final code made untrue (for example the final grant sets, the owner role names, and the deadline abort being "not a quota cut").
   - ADR-0008 is unchanged: say nothing there; ADR-0051 states that the upstream abort does not alter who holds the vendor key.

4. Feature docs.
   - `docs/features/llm-gateway.md`: read the "Quota", "Metering", concurrency and ceiling text the earlier tasks added as one document. Make the sections agree (the day boundary, the refusal codes, the throttle numbers, the cut-call rows). In "Planned / not yet built" (line 320) add the residuals from ADR-0051 so a reader finds them. State the corrected leak scope here too.
   - `docs/features/capabilities-and-manifests.md`: confirm line 152's corollary (SP-6 changed it) matches the final classifier; add a sentence that the data and fetch budgets are still unlimited when unset.
   - `infra/azure/README.md`: in the Cost section (line 1033) make sure the enforced platform ceiling and its relation to `platformMonthlyUsdCap` read correctly, and add a pointer to the upgrade notes below.

5. Operator rollout notes. In `apps/docs/src/deploy/updates.md` add a section after "The routine update" (that section runs from line 106 to line 170; its subsections are numbered 1 to 3), titled "Upgrading to the LLM spend controls". These are notes for an operator; nothing here is done to a live install by this work. Write the six steps in order, each with the command or the setting, in the page's voice:
   1. **Egress and edge images.** Build and deploy the new egress and edge images. There is no data migration for the abort and the charging change. New `error` rows carry `;usage=` markers; historical rows keep their $0.
   2. **List approved apps with no budget.** Before the default takes effect, find the apps that are unlimited today:

```sql
SELECT slug FROM apps
 WHERE capabilities->'llm' IS NOT NULL
   AND capabilities->'llm'->>'dollarsPerDay' IS NULL
   AND jsonb_array_length(COALESCE(capabilities->'llm'->'models', '[]'::jsonb)) > 0;
```

      These become $50 per day when the default deploys. Set an explicit number for each through the portal, or deploy with `llmDefaultDollarsPerDay` raised for a transition and lower it afterwards. Skipping this step means refusals on the first busy day. **Validate the query before you publish it**: the design marks the column and JSON path names as inferred. The `apps` table and its `capabilities` column are confirmed by `apps/portal/prisma/schema.prisma` (the `App` model, `capabilities Json` at line 104) and the manifest shape by `packages/shared/src/approval.ts`; run the query against the dev database with an app seeded with an LLM grant and no `dollarsPerDay`, and with one that has a number, and record both results in `results/`.
   3. **Apply the migrations before the edge image.** An edge that starts without the function or the lease table fails closed on its first ceiling or lease call. Confirm the migration identity's role name (`helixadmin` by default, the `postgresAdminLogin` parameter) is the role the owner policy on `gateway_calls` was created for.
   4. **Choose the platform ceiling.** The Bicep default is one tenth of `platformMonthlyUsdCap` per day. Set it from the install's own ledger; an untuned value either blocks real use or never trips. A one-organization install may set `llmPlatformDollarsPerDay` to `0` to switch it off and should say so in its own notes.
   5. **Apply the new template.** A Bicep default does not reach an install until the operator applies the template with their own parameters. Set the four concurrency parameters, the call deadline and the fetch cap there.
   6. **Mixed replicas.** An edge without the ceiling setting disables it, so a rolling deploy with old and new replicas does not refuse calls.
   - **Rollback.** The images roll back with `az containerapp update` as the page already describes; each Part 3 control has an off value (`0`), and the migrations are additive and can stay.
   - **What was not verified in Azure.** List: the Bicep parameters and the edge and dev-gateway environment wiring (compile-checked only); the alert rule's query and that it fires; the production owner role under `FORCE` RLS; abort propagation through the Container Apps ingress between edge and egress; lease behavior across real replicas.

6. Knob and parameter check. Write the check as a small shell script in `results/` (it is evidence, not a repo file) and run it: for each of `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`, `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY`, `EDGE_LLM_MAX_APP_IN_FLIGHT`, `EDGE_LLM_MAX_USER_IN_FLIGHT`, `EDGE_LLM_MAX_IN_FLIGHT`, `EDGE_LLM_MAX_CALL_MS`, `EDGE_FETCH_MAX_APP_IN_FLIGHT`, `grep -l` the name in `apps/edge/src/config.ts`, `.env.example`, `apps/docs/src/deploy/configuration.md`, `infra/azure/main.bicep`, and (for the LLM ones) `docs/features/llm-gateway.md`; and for each Bicep parameter (`llmDefaultDollarsPerDay`, `llmPlatformDollarsPerDay`, `llmMaxAppInFlight`, `llmMaxUserInFlight`, `llmMaxInFlight`, `llmMaxCallMs`, `fetchMaxAppInFlight`) confirm a row in `configuration.md`. Any miss is fixed in this task. Scope this to the knobs this sequence added: `.env.example` lists few `EDGE_*` settings today.

7. `TODO.md`: delete the bullet beginning "**Propagate a client-disconnect abort through egress to the vendor.**" (line 58 at `main`). Do not check it off. Its content survives in ADR-0051 and `docs/features/llm-gateway.md`. Also scan `TODO.md` for any other item this sequence made stale (`grep -n "client-disconnect\|dollarsPerDay\|unbounded\|leak" TODO.md`) and fix or delete it.

8. Comments and docs in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths. The `refs` step of the gate scans for planning identifiers of the `I-nn` and `T-nnn` shape; do not introduce any.

## Done When

- [ ] All requirements met.
- [ ] `grep -rn "SP-[0-9]" docs apps/docs/src infra TODO.md` finds no plan identifiers in the new text.
- [ ] The knob check script passes with no misses; its output is in `results/`.
- [ ] The rollout-note SQL was run against the dev database in both shapes and the results are in `results/`.
- [ ] `./check-and-lint.sh` passes in the dev container, including the docs build (it fails on a dead internal link). Output saved under `results/`.
- [ ] `just dev smoke` is not required: this change touches documentation only.
- [ ] `just infra build` passes if `infra/azure/README.md` or any Bicep file was touched; otherwise state "no Bicep change" in `results/`.
- [ ] Committed with `fest commit -m "SP-13: ADR-0051, rollout notes and docs for the LLM spend controls"`.
- [ ] Unverified in Azure: everything the rollout notes list under "What was not verified in Azure". The notes say so in their own words, not only here.
