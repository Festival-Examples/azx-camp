---
fest_type: workflow
fest_id: wf-helix-spend-containment-egress-WF
fest_parent: wf-helix-spend-containment-egress
fest_workflow_position: after
---

# Design: spend leak, hosted-app containment, network egress control

Plan three fixes for projects/helix found by workflow/explore/helix-repo-exploration (findings.md blockers 5, 6, 7 and 10): (1) AI spend escapes the budget when a client disconnects, and budgets are optional, after-the-fact, per-app only (KP-2, SEC-4, OPS-14); (2) hosted apps share a registrable domain with auth and portal, and the CSP leaves image and navigation exfiltration channels open (SEC-1, SEC-2, KP-1, upstream issue #16); (3) no network-level egress control: both live installs run without the firewall, its rule allows every FQDN, and there are no NSGs behind the SSRF filter (OPS-9, SEC-7, ADR-0005). Each design names the files it changes, states failure paths as well as the happy path, cites file:line anchors that were actually opened, and follows the repo's rules in projects/helix/AGENTS.md (edge stays dependency-minimal, telemetry ships with the change, adversarial tests ship with auth changes).

---

## Step 1: FRAME — Confirm each problem against the current code and record the constraints every design must respect.

**Goal:** Confirm each problem against the current code and record the constraints every design must respect.

**Actions:**
1. For each of the three problems, re-open the evidence cited in workflow/explore/helix-repo-exploration (findings.md, notes/04, 07, 08, 03) and confirm the current behavior in projects/helix at main.
2. Record the constraints from AGENTS.md, the relevant ADRs (ADR-0005, ADR-0019, ADR-0021, ADR-0028, ADR-0037), and the deployment model (single-tenant installs per customer).
3. List the decisions only the owner can make, starting with the audience question (one trusted organization vs outside app authors), because it sets how far each design must go.

**Output:** 00-frame.md: confirmed problem statements with evidence, constraints, and open owner decisions.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 2: DESIGN — Draft one design per problem, each with options, a recommendation, and an implementation outline.

**Goal:** Draft one design per problem, each with options, a recommendation, and an implementation outline.

**Actions:**
1. Write 01-spend-controls.md, 02-app-containment.md, and 03-egress-network-control.md. The three are independent and may be drafted in parallel.
2. Each design covers: current behavior with file:line anchors; goals and non-goals; options with tradeoffs; the recommended option; the change by file; failure paths; tests (adversarial where security-relevant); telemetry per AGENTS.md; rollout and migration for the existing live installs; whether an ADR is needed; and open questions for the owner.

**Output:** 01-spend-controls.md, 02-app-containment.md, 03-egress-network-control.md.

**Checkpoint:** DOCUMENTATION — Document findings before continuing

---

## Step 3: REVIEW — Check every design against the code and against each other before the owner sees them.

**Goal:** Check every design against the code and against each other before the owner sees them.

**Actions:**
1. Re-open a sample of each design's file:line claims, covering every claim its recommendation depends on, and fix anything that does not match.
2. Check cross-design interactions: a separate app domain changes cookie, CSP, OIDC redirect, and certificate setup; network egress allow-lists interact with connection approvals and the LLM vendor hosts; spend controls touch the edge, egress, and the ledger.
3. Record what was checked and what was changed in review.md.

**Output:** review.md, plus corrected designs.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 4: DECIDE — Get the owner's decisions on the open questions and record them.

**Goal:** Get the owner's decisions on the open questions and record them.

**Actions:**
1. Present the open decisions from all three designs to the owner, each with the recommended answer and its tradeoff.
2. Record each answer, and who made it, in decisions.md. This step is not complete until the owner has answered; do not advance it before then.

**Output:** decisions.md.

**Checkpoint:** VERIFICATION — Verify output before continuing

---

## Step 5: PLAN — Turn the decided designs into an execution plan the owner approves.

**Goal:** Turn the decided designs into an execution plan the owner approves.

**Actions:**
1. Update each design to its decided option and remove the alternatives that were rejected, keeping the reasons in a short section.
2. Break the work into ordered changes with acceptance criteria and the evidence that proves each one (tests, telemetry, a check against a live install where relevant).
3. Propose the execution vehicle by the camp's sizing rules (camp intents for small changes, a festival for multi-phase work) and create it only after the owner agrees.

**Output:** plan.md, and the agreed intents or festival.

**Checkpoint:** VERIFICATION — Verify output before continuing
