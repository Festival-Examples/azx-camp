---
fest_type: task
fest_id: 06_sp6_default_llm_budget.md
fest_name: sp6 default llm budget
fest_parent: 01_spend_controls
fest_order: 6
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.335173-06:00
fest_updated: 2026-10-09T16:22:17.621796-06:00
fest_tracking: true
---



# Task: sp6 default llm budget

## Objective

Enforce an install default daily LLM budget for an app whose manifest sets no `dollarsPerDay`, and make the approval classifier and every piece of text that says "unset means unbounded" agree with it. Implements SP-6 from 01-spend-controls.md.

## Requirements

- [ ] No prerequisite from an earlier task in this sequence (the design orders it after the Part 2 tasks only for review order). `07_sp7_admission_denial_throttle.md` depends on this task.
- [ ] A new setting `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` parsed in the shared gateway config, so the edge and the dev gateway both get it. Default is `BASELINE_DOLLARS_PER_DAY` (50, `packages/shared/src/approval.ts:206`).
- [ ] An unset `dollarsPerDay` is enforced at that default for both windows: the day cap, and the hourly burst cap at one sixth of it. An explicit number is honored, including one larger than the default.
- [ ] `0` is the explicit off value: an unset budget is unlimited again. This is the per-install relaxation for installs on the one-organization model (ADR-0028). The default stays strict.
- [ ] Failure path. A value that is negative, non-numeric, empty-but-present garbage, or `Infinity`/`NaN` fails at boot with the variable named in the message. An unset or blank variable falls back to the default.
- [ ] Failure path. The default is not clamped to the baseline. If an operator raises it above 50, an unset grant is enforced above what the classifier showed the approver. The config comment says so, and the edge boot log prints the effective default.
- [ ] The classifier: `budgetPrivilege` treats an unset LLM budget as `BASELINE_DOLLARS_PER_DAY`, not infinity. An unset grant classifies as baseline; a raise above 50 is elevated; removing a cap is a reduction. The data-writes and fetch-requests budgets keep treating unset as unlimited (decision S4).
- [ ] Every statement that an unset LLM budget is unbounded or unlimited is corrected (list in step 6). Agents read the catalogue and the skill; wrong text sends them chasing rejections.
- [ ] `infra/azure/main.bicep` gets a `llmDefaultDollarsPerDay` parameter passed to the edge and the dev gateway as `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-6-default-llm-budget`.

2. Config, `apps/edge/src/config.ts`. The `llm` block of `GatewayConfig` is at lines 159-199 and is parsed in `loadGatewayConfig` at lines 754-764 (the dev gateway shares it, so no second change is needed there).
   - Add a field to the `llm` interface with a docblock: `defaultDollarsPerDay: number;` "Daily LLM budget applied to an app whose manifest sets none (`EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`). Defaults to the approval baseline. Not clamped to it: an operator who raises it enforces more than the classifier showed the approver. `0` means an unset budget is unlimited."
   - Import `BASELINE_DOLLARS_PER_DAY` from `@azx-pbc/shared` (check `config.ts` already imports from it; if not, the edge depends on `@azx-pbc/shared` already, as `llm.ts` does).
   - Add a parser next to `requirePositiveMs` (line 684) and follow its style, including blank-counts-as-unset and the named error:

```ts
function requireNonNegativeNumber(raw: string | undefined, fallback: number, name: string): number {
  if (raw === undefined || raw.trim() === "") return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number (got ${JSON.stringify(raw)})`);
  }
  return value;
}
```

   - In the returned `llm` object (line 754) add `defaultDollarsPerDay: requireNonNegativeNumber(env.EDGE_LLM_DEFAULT_DOLLARS_PER_DAY, BASELINE_DOLLARS_PER_DAY, "EDGE_LLM_DEFAULT_DOLLARS_PER_DAY"),`.
   - Later tasks reuse this parser for the ceiling and the caps; keep it generic.

3. Fixtures. Both config fixtures in `apps/edge/src/test/config.ts` build an `llm` object and will stop type-checking: `testEdgeConfig` (the `llm:` block at line 74) and `testDevGatewayConfig` (line 124). Add `defaultDollarsPerDay: 50` to both.

4. Boot log. In `apps/edge/src/server.ts`, add `llmDefaultDollarsPerDay: config.llm.defaultDollarsPerDay` to the `boot.serving` log object (`event: "boot.serving"`, line 311). Add the same field to the dev gateway's boot line in `apps/edge/src/devGateway/server.ts` (line 207).

5. The handler, `apps/edge/src/gateway/llm.ts`. Lines 186-216 hold the quota check: `const cap = entry.llm.dollarsPerDay;` (line 187) and `if (cap !== undefined) {` (line 188). Change to:

```ts
    const usage = rt.usage;
    // An unset budget is the install default, never unlimited. 0 is the operator's explicit
    // "no default" (a one-organization install, ADR-0028).
    const cap = entry.llm.dollarsPerDay ?? rt.config.llm.defaultDollarsPerDay;
    if (cap > 0) {
```

   The body is unchanged: `capMicro = cap * 1_000_000`, the day window against `capMicro`, and the burst window against `capMicro * BURST_BUDGET_FRACTION`, so the hourly cap applies to the default too. `rt.config` is already on `LlmGatewayRuntime` (line 66). Update the comment at line 183 and the module docblock paragraph that says the budget is checked "if set".

6. Classifier and text.
   - `packages/shared/src/approval.ts`. Give `budgetPrivilege` (lines 245-248) a third parameter, `unsetMeans: number = Number.POSITIVE_INFINITY`, returning `v ?? unsetMeans` when there is a grant. Pass `BASELINE_DOLLARS_PER_DAY` at the two LLM call sites (lines 328-329). Leave the data call sites (lines 390-391) and the fetch call sites (lines 447-448) on the default. Rewrite the docblock at lines 236-244: an unset LLM budget is the install default, which the classifier reads as the baseline; unset data and fetch budgets are still unlimited.
   - `packages/shared/src/manifest.ts:24` ("unset => unbounded"): "unset => the install default (the approval baseline unless the operator changed it)". Keep the dollar-denomination sentence.
   - `packages/shared/src/capabilityHelp.ts:85` ("Removing the cap means unlimited."): "Removing the cap falls back to the install default (the $50/day baseline unless the operator changed it)."
   - `packages/shared/src/catalogue.ts` (the `approval` block at lines 145-195): read it and `apps/portal/src/routes/catalogue.ts:128,183` for any text about an unset budget; change what is wrong. `grep -n "unbounded\|unlimited" packages/shared/src/catalogue.ts` currently finds nothing, so this may be no change. The portal SPA text at `apps/portal-web/src/pages/tabs/CapabilitiesTab.tsx:456` already says a cap is mandatory once a model is enabled; leave it.
   - `docs/features/capabilities-and-manifests.md:152` (the "unset budget is unlimited" corollary): rewrite for the LLM budget only; keep it true for data and fetch.
   - `docs/features/llm-gateway.md:33-46` ("Quota (block-new, finish-in-flight)"): replace the sentence that an unset `dollarsPerDay` means unlimited.
   - `packages/deploy-skill/SKILL.md:147` and `apps/docs/src/apps/quickstart.md:154` (`"dollarsPerDay": 5 // daily spend cap in USD; omit for unbounded`): "omit for the install default". Check `apps/docs/src/apps/manifest.md` (it documents `dollarsPerDay?: number`) and any deploy-skill test or snapshot that pins the SKILL text (`grep -rn "omit for unbounded" packages apps --include='*.ts' --include='*.md' --include='*.snap'`), and update them. Do not edit anything under `apps/docs/.vitepress/dist`; it is build output.

7. Bicep, `infra/azure/main.bicep`. Follow the `fetchMaxBodyMb` pattern (parameter at lines 66-68, env entries at lines 1237 and 1442). Add next to `platformMonthlyUsdCap` (line 58):

```bicep
@description('Daily LLM spend budget in USD applied to any app whose manifest sets no dollarsPerDay (EDGE_LLM_DEFAULT_DOLLARS_PER_DAY on the edge and dev gateway). Mirrors BASELINE_DOLLARS_PER_DAY (50) in packages/shared/src/approval.ts; raising it enforces more than the approval classifier showed the approver. 0 = an unset budget is unlimited.')
@minValue(0)
param llmDefaultDollarsPerDay int = 50
```

   Add `{ name: 'EDGE_LLM_DEFAULT_DOLLARS_PER_DAY', value: string(llmDefaultDollarsPerDay) }` beside `EDGE_LLM_OPENAI_CONNECTION` in `edgeApp` (line 1230) and in `devGatewayApp` (line 1440). `infra/azure/main.bicepparam` needs no line while the default applies (`fetchMaxBodyMb` has none either); add a commented line in the style of its `llmMonthlyBudgetUsd` example (line 106) so operators can find the knob, and the same comment in `main.bootstrap.bicepparam` (line 120 region). Run `just infra build`.

8. Docs for operators: add a `llmDefaultDollarsPerDay` row to the parameters table in `apps/docs/src/deploy/configuration.md` (the parameters table; the `platformMonthlyUsdCap` row is line 121), and `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` to the variables table (the environment-variable tables; the first row of the `App(s)` table is line 199). Add the variable with its default to `.env.example` as a commented line (the file lists few `EDGE_*` settings today; add only the knobs this sequence adds).

9. Tests.
   - `apps/edge/src/config.test.ts`: in the style of the reconcile-interval test (line 102): default is 50; an explicit `"120"` is honored; `"0"` is accepted; `"abc"`, `"-1"`, `"NaN"`, `"Infinity"` throw `/EDGE_LLM_DEFAULT_DOLLARS_PER_DAY must be a non-negative number/`; blank counts as unset; the dev gateway loader applies the same validation.
   - `apps/edge/src/gateway/llm.test.ts`: the test `"imposes no cap when the grant omits dollarsPerDay"` (lines 369-375) asserts the old behavior and must change. Replace it with: an unset grant with `spendTodayMicro` at the default cap (`50_000_000`) is refused with `429 quota_exceeded`; an unset grant with the hourly spend over one sixth of the default is refused with `429 rate_limited`; an unset grant under both is served; an explicit `dollarsPerDay: 500` is honored with the same spend; a config with `defaultDollarsPerDay: 0` serves an unset grant at `10_000_000_000` micro-USD spend (the old behavior, now opt-in). `buildLlmEdge` (line 36) builds its config with `testEdgeConfig`; extend it to accept an override of `llm.defaultDollarsPerDay`.
   - `packages/shared/src/approval.test.ts` (lines 44-90): "treats removing a spend cap (→ unlimited) as elevated" (line 60) now means the opposite: removing a cap of 500 is a reduction to the baseline and not elevated. Rename and flip it. Keep "treats adding a cap (unlimited → capped) as baseline privilege reduction" (line 70) and add: unset to 100 is elevated; unset to 50 is baseline; unset to unset produces no delta. Add one case showing the data-writes and fetch-requests budgets still treat unset as unlimited (removing a cap there is still elevated).
   - Snapshot and catalogue tests: run `pnpm vitest run packages/shared apps/portal apps/portal-web` and update any snapshot whose text you changed, only for the changed strings.
   - Behavior note for the PR: this changes what already-approved unset apps get. The operator steps are in the rollout notes written by `13_sp13_adr_and_docs.md`.

10. Out of scope, record in `results/` and do not build: the portal Overview and Usage tabs show no cap for an unset app (`apps/portal-web/src/pages/tabs/OverviewTab.tsx:100`, `UsageTab.tsx:111`) although the edge now enforces the default. The portal does not know the edge's setting. Note it as a follow-up for the owner.

11. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The replaced `llm.test.ts` cases, the config cases and the flipped classifier cases pass; catalogue and snapshot tests are updated for the new wording only.
- [ ] `grep -rn "omit for unbounded\|unset => unbounded" packages apps docs --include='*.ts' --include='*.tsx' --include='*.md' | grep -v node_modules | grep -v dist` returns nothing about the LLM budget.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes. Output saved under `results/`.
- [ ] `just infra build` passes for the new Bicep parameter and env entries.
- [ ] Committed with `fest commit -m "SP-6: enforce an install default for an unset LLM budget"`.
- [ ] Unverified in Azure: the Bicep parameter and the env wiring on the edge and dev-gateway container apps are compile-checked only; a deployed edge actually receiving `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` is not proven. A Bicep default does not reach an install until its operator applies the template with their own parameters (an operator rollout note).