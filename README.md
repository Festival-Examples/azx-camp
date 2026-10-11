# Helix hardening: a Festival case study

This camp records a Festival run on **Helix**, an existing open source platform for hosting AI-powered apps. The work began with a repository evaluation, moved through a design work item, and ended with a completed implementation festival. The code changes are in [my Helix repository](https://github.com/lancekrogers/helix), based on [AZX's original Helix](https://github.com/AZX-PBC-OSS/helix). This is an independent example, not an AZX release or a deployment to AZX's live installs.

![Replay of the Helix hardening festival from first task to completion](festivals/.dungeon/completed/2026-10-11/helix-hardening-HH0001/festival-replay.gif)

The replay comes from the festival's recorded task and gate events (`fest gif`). It shows the work advancing through four sequences and 54 tasks.

## Follow the work

1. **Explore the existing product.** [The exploration workflow](workflow/explore/helix-repo-exploration/WORKFLOW.md) split repository discovery into focused questions. [The findings](workflow/explore/helix-repo-exploration/findings.md) distinguish confirmed gaps from hypotheses and identify the spend, network, and hosted-app isolation problems taken forward.
2. **Design the changes.** [The design work item](workflow/design/helix-spend-containment-egress/WORKFLOW.md) developed three designs, recorded [owner decisions](workflow/design/helix-spend-containment-egress/decisions.md), and set the [implementation order and verification rules](workflow/design/helix-spend-containment-egress/plan.md).
3. **Execute the festival.** [Helix hardening HH0001](festivals/.dungeon/completed/2026-10-11/helix-hardening-HH0001/FESTIVAL_OVERVIEW.md) organized the work into spend controls, network egress, CSP and response headers, and a separate hosted-app domain. Each sequence has task files, test records, a review, and fixes. [The final phase record](festivals/.dungeon/completed/2026-10-11/helix-hardening-HH0001/001_IMPLEMENT/output_specs/PRESENTATION.md) maps the outcome to the evidence and lists what remains unverified.
4. **Inspect the code changes.** The four pull requests in my Helix repository cover [spend controls](https://github.com/lancekrogers/helix/pull/2), [network egress](https://github.com/lancekrogers/helix/pull/3), [CSP and headers](https://github.com/lancekrogers/helix/pull/4), and the [domain split](https://github.com/lancekrogers/helix/pull/5). They were merged in that order.

The festival implemented 34 planned changes and 11 review fix batches. Its final local gate passed 243 test files and 3,704 tests; browser smoke and network simulation also passed. The code was **not deployed to Azure or the live installs**. Azure-specific behavior is marked unverified in the rollout records. The phase record predates the PR merges, so its descriptions of the PRs as open are historical; the linked PRs show their current state.

## Repository layout

| Path | What it contains |
| --- | --- |
| [`workflow/explore/helix-repo-exploration/`](workflow/explore/helix-repo-exploration/) | Evidence gathered from the existing codebase and its operations |
| [`workflow/design/helix-spend-containment-egress/`](workflow/design/helix-spend-containment-egress/) | Designs, decisions, review, and implementation plan |
| [`festivals/.dungeon/completed/2026-10-11/helix-hardening-HH0001/`](festivals/.dungeon/completed/2026-10-11/helix-hardening-HH0001/) | Completed tasks, review findings, gate evidence, and replay |
| `projects/helix/` | Git submodule containing the Helix implementation |

The Helix submodule currently points to a private repository. The camp's written records and GIF can be read here; cloning Helix or following its PR links requires access to that repository.
