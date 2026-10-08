---
fest_type: workflow
fest_id: wf-helix-repo-exploration-WF
fest_parent: wf-helix-repo-exploration
fest_workflow_position: after
---

# Explore helix

Work out what helix (projects/helix, now the private lancekrogers/helix fork of AZX-PBC-OSS/helix) is, how it builds and runs, what the repo already knows is wrong, what breaks because it is now a private fork, and what the current health of the code is. Record evidence with file:line anchors under notes/, and mark each finding confirmed (reproduced or read) or hypothesis (inferred, not yet checked). Start from notes/00-seed-observations.md.

---

## Step 1: ORIENT — Explain in plain terms what helix is, who it serves, and how it is put together.

**Goal:** Explain in plain terms what helix is, who it serves, and how it is put together.

**Actions:**
1. Read projects/helix/README.md, TOUR.md, AGENTS.md (CLAUDE.md is a symlink to it), and docs/README.md.
2. Read docs/platform-architecture.md and docs/platform-project-plan.md for the trust-boundary split (edge, portal, egress) and the milestone plan.
3. List every workspace package from pnpm-workspace.yaml with its role in one line (apps/*, packages/*, examples/*).
4. Note the stated status (AGENTS.md:19 says deployed on Azure at M5, feature work at M4.5) and check it against git log on main.

**Output:** notes/01-what-it-is.md: a one-paragraph summary, the component map, and the stated vs observed project status.

**Checkpoint:** DOCUMENTATION — Document findings before continuing

---

## Step 2: RUN — Find out how helix is built, run, and tested locally, and record what actually works.

**Goal:** Find out how helix is built, run, and tested locally, and record what actually works.

**Actions:**
1. Read .devcontainer/Dockerfile, .devcontainer/docker-compose.yml (services app, db, azurite, otel-collector), .devcontainer/post-create.sh, and the root package.json scripts.
2. Read check-and-lint.sh and .github/workflows/ci.yml to map the local gate onto the CI jobs (static, test, browser-lane, bicep, package, images).
3. Bring the stack up in the dev container and run pnpm dev:idp, dev:portal, dev:edge, dev:egress, dev:web. Record each command, the result, and any error text verbatim.
4. Note host-only failures separately from container failures. Known host failure: pnpm cannot self-switch to the packageManager version 11.5.3 (see notes/00-seed-observations.md).

**Output:** notes/02-how-it-runs.md: commands that work, commands that fail with exact errors, and the prerequisites each one needs.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 3: DECISIONS — Identify which architecture decisions are load-bearing and which are stale.

**Goal:** Identify which architecture decisions are load-bearing and which are stale.

**Actions:**
1. Index docs/adr/ (51 entries): number, title, status, and whether a later ADR supersedes it.
2. Flag ADRs that the code contradicts, or that AGENTS.md treats as hard rules (for example ADR-0037 telemetry boundary, ADR-0040 no member enumeration).
3. Skim docs/reviews/ (architecture review, ADR challenge, build-vs-buy) for conclusions that were never acted on.

**Output:** notes/03-decisions.md: ADR index plus a short list of decisions that matter for any change to the repo.

**Checkpoint:** DOCUMENTATION — Document findings before continuing

---

## Step 4: KNOWN-PROBLEMS — Collect the problems the project already knows about, with their current state.

**Goal:** Collect the problems the project already knows about, with their current state.

**Actions:**
1. Read TODO.md (41 KB) and group its items by area and severity. Check a sample against the code to see whether they are still open.
2. Read SECURITY.md and the dated reviews under docs/reviews/ for unresolved findings.
3. List open issues and PRs on the upstream: gh issue list -R AZX-PBC-OSS/helix and gh pr list -R AZX-PBC-OSS/helix.
4. For the 10 non-main branches, record commits not on main (git log origin/main..<branch>) and decide whether each is merged, abandoned, or still live. Seed data is in notes/00-seed-observations.md.

**Output:** notes/04-known-problems.md: a grouped problem list with source links and current status.

**Checkpoint:** DOCUMENTATION — Document findings before continuing

---

## Step 5: FORK-IMPACT — Find what breaks or changes because the canonical remote is now the private lancekrogers/helix.

**Goal:** Find what breaks or changes because the canonical remote is now the private lancekrogers/helix.

**Actions:**
1. Check .github/workflows/release-cli.yml: it publishes @azx-pbc/helix-cli to public npm on a cli-v* tag via OIDC trusted publishing. Confirm whether the npm trusted publisher is bound to AZX-PBC-OSS/helix and what a cli-v* tag on the fork would do.
2. Check .github/workflows/docs.yml: it deploys GitHub Pages on push to main. Confirm whether Pages is available for this private repo on the current GitHub plan.
3. Check .github/workflows/ci.yml: it runs on push and its jobs are Docker-heavy. Estimate Actions minutes now billed to the personal account.
4. Inventory AZX identity baked into the repo: the @azx-pbc package scope, *.helix.azxlabs.io hostnames, infra/azure and infra/entra parameter files, image names, and docs links to AZX-PBC-OSS.
5. Decide with the user whether the fork should keep upstream as a remote, disable or retarget the publish workflows, or rename identities.

**Output:** notes/05-fork-impact.md: each fork-sensitive surface, what happens today, and the recommended change.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 6: HEALTH — Measure the current health of the code with the project's own gates.

**Goal:** Measure the current health of the code with the project's own gates.

**Actions:**
1. Run ./check-and-lint.sh (or just check) inside the dev container, where Postgres and Azurite are available. Record pass/fail per step with timings and the first failure output.
2. Run pnpm audit and pnpm outdated -r and record anything high or critical.
3. Review .devcontainer/Dockerfile supply-chain surface: the curl | sh installs at lines 35, 53, 54, and 61.
4. Note test gaps that AGENTS.md calls mandatory (adversarial auth tests, telemetry redaction suites) if any are missing or skipped.

**Output:** notes/06-health.md: gate results, audit results, and supply-chain notes with exact command output.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 7: SYNTHESIZE — Turn the notes into a decision-ready summary and choose where the follow-up work goes.

**Goal:** Turn the notes into a decision-ready summary and choose where the follow-up work goes.

**Actions:**
1. Write findings.md: what helix is, then problems ranked by impact. Each problem cites file:line or command output and is marked confirmed or hypothesis.
2. For each problem, propose a disposition: camp intent (small), workflow/design/ doc (needs a decision), festival (multi-step work), or no action.
3. Review findings.md with the user before creating any follow-up intents, designs, or festivals.

**Output:** findings.md at the workitem root.

**Checkpoint:** VERIFICATION — Verify output before continuing
