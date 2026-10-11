# Constraints: each quality standard with its proof

The four quality standards are from `PHASE_GOAL.md`.

## 1. `./check-and-lint.sh` passes in the dev container before each commit

Every change was run through the full gate by the coordinator before its commit, and the result was saved per change. The files below are those per-change gate records (each holds the step summary and test counts for that change), followed by the sequence gates and the final run.

**ls */results/*-gate.txt (one per change or fix batch)**

```text
01_spend_controls: it1-gate.txt
01_spend_controls: it2-gate.txt
01_spend_controls: it3-gate.txt
01_spend_controls: it4-gate.txt
01_spend_controls: it5-gate.txt
01_spend_controls: pr2-review-fixes-gate.txt
01_spend_controls: sp1-gate.txt
01_spend_controls: sp10-gate.txt
01_spend_controls: sp11-gate.txt
01_spend_controls: sp12-gate.txt
01_spend_controls: sp13-gate.txt
01_spend_controls: sp2-gate.txt
01_spend_controls: sp3-gate.txt
01_spend_controls: sp4-gate.txt
01_spend_controls: sp5-gate.txt
01_spend_controls: sp6-gate.txt
01_spend_controls: sp7-gate.txt
01_spend_controls: sp8-gate.txt
01_spend_controls: sp9-gate.txt
02_network_egress: eg1-gate.txt
02_network_egress: eg10-gate.txt
02_network_egress: eg11-gate.txt
02_network_egress: eg2-gate.txt
02_network_egress: eg3-gate.txt
02_network_egress: eg4-gate.txt
02_network_egress: eg5-gate.txt
02_network_egress: eg6-gate.txt
02_network_egress: eg7-gate.txt
02_network_egress: eg8-gate.txt
02_network_egress: eg9-gate.txt
02_network_egress: it6-gate.txt
02_network_egress: it7-gate.txt
02_network_egress: pr3-review-fixes-gate.txt
03_csp_and_headers: ct1-gate.txt
03_csp_and_headers: ct2-gate.txt
03_csp_and_headers: ct3-gate.txt
03_csp_and_headers: it8-gate.txt
03_csp_and_headers: it9-gate.txt
04_domain_split: ct10-gate.txt
04_domain_split: ct4-gate.txt
04_domain_split: ct5-gate.txt
04_domain_split: ct6-gate.txt
04_domain_split: ct7-gate.txt
04_domain_split: ct8-gate.txt
04_domain_split: ct9-gate.txt
04_domain_split: it10-gate.txt
04_domain_split: it11-gate.txt
```

**sequence gates: grep 'full gate' */results/gate-testing-summary.txt**

```text
01_spend_controls/results/gate-testing-summary.txt:full gate run 1 exit=1
01_spend_controls/results/gate-testing-summary.txt:full gate run 2 exit=0
02_network_egress/results/gate-testing-summary.txt:full gate run 1 exit=0
02_network_egress/results/gate-testing-summary.txt:full gate run 2 exit=0
03_csp_and_headers/results/gate-testing-summary.txt:full gate run 1 exit=0
03_csp_and_headers/results/gate-testing-summary.txt:full gate run 2 exit=0
04_domain_split/results/gate-testing-summary.txt:full gate run 1 exit=0
04_domain_split/results/gate-testing-summary.txt:full gate run 2 exit=0
```

Sequence 01's run 1 failed on a pre-existing timing test (`apps/portal/src/deploy/diagnose.test.ts`) and passed on run 2; see `01_spend_controls/results/gate-testing.md`.

**final run at ca0afd1: logs/check-and-lint.log, last 12 lines**

```text
 ✓  portal-web  src/deploy/report.test.ts (2 tests) 6ms

 Test Files  243 passed (243)
      Tests  3704 passed | 1 skipped (3705)
   Start at  00:28:29
   Duration  59.84s (transform 5.09s, setup 1.33s, import 38.54s, tests 110.15s, environment 10.19s)

✔ tests passed (61s)

────────────────────────────────────────
timing: typecheck=14s lint=7s refs=0s format=6s docs=2s tests=61s total=90s
✔ All checks passed
```

Tests that failed intermittently during the phase, each passing on rerun with no code change:

- `apps/edge/src/routing/connectionsJourney.integration.test.ts`: flaky before this work (it is the one failure in the baseline run at `792557a`, `01_spend_controls/results/00-baseline-gate.md`). The phase only added config fields to its fixtures.
- `apps/portal/src/deploy/diagnose.test.ts` (a timing bound) and `apps/portal/src/routes/sessions.test.ts` (once): the phase did not change either file.
- `apps/edge/src/gateway/usage.rls.integration.test.ts`: **this one is in tests the phase added.** The platform-sum cases from SP-8 and SP-9 asserted an exact total while other test files insert rows; IT-5 changed them to compare deltas. One of them (`prodAfterDev`) still failed once during IT-11, then passed three isolated reruns and two full gates. The cause was not established (`04_domain_split/results/it11-split-rollout-docs.md`).
- Under heavy host load (load average 60 to 80 during SP-2) three more files failed in one run and passed when rerun alone; they are named in `01_spend_controls/results/sp2-egress-upstream-abort.md`.

The `sessions.test.ts` failure happened on the first full-gate run of the earlier final verification at `97b3fe1`; its log and six clean reruns are kept in `logs/earlier-run-at-97b3fe1/`. The final run at `ca0afd1` above passed first time.

## 2. Changes to running services pass `just dev smoke`

**per-change smoke records: ls */results/*smoke***

```text
   4 gate-testing-smoke.log
   3 gate-testing-smoke-extra.log
   1 sp9-smoke.txt
   1 sp9-smoke-ceiling-on.txt
   1 sp8-smoke.txt
   1 sp8-agent-smoke.log
   1 sp7-smoke.txt
   1 sp6-smoke.txt
   1 sp5-smoke.txt
   1 sp4-smoke.txt
   1 sp2-smoke.txt
   1 sp12-smoke.txt
   1 sp11-smoke.txt
   1 sp10-smoke.txt
   1 it5-smoke.txt
   1 it4-smoke.txt
   1 it3-smoke.txt
   1 it2-smoke-ceiling-on.txt
   1 it1-smoke.txt
   1 gate-testing-smoke-split-helix-apps.localhost.log
   1 gate-testing-smoke-split-apps.local.helix.azxlabs.io.log
   1 gate-testing-smoke-browser.log
   1 eg8-smoke.txt
   1 eg7-smoke.txt
   1 eg3-smoke.txt
   1 eg2-smoke.txt
   1 eg1-smoke.txt
   1 ct7-split-smoke-and-lane.md

files:       33
```

Changes after sequence 02 record their smoke result inside the change's `*-gate.txt` file (real-browser runs). The final runs at the last commit:

**logs/summary.txt**

```text
check-and-lint exit=0
adversarial suites (OTEL off) exit=0
infra build exit=0
smoke single-domain (real browser) exit=0
smoke split helix-apps.localhost (real browser) exit=0
smoke same-site pair (real browser) exit=0
connections lane single-domain exit=0
connections lane split exit=0
netsim translator tests exit=0
net-sim (host Docker) exit=0
modified files after runs: 0
```

**logs/smoke-single-domain.log, last line**

```text
37 passed, 0 failed, 0 skipped
```

**logs/smoke-split.log, last line**

```text
47 passed, 0 failed, 0 skipped
```

**logs/smoke-same-site-pair.log, last line**

```text
47 passed, 0 failed, 0 skipped
```

## 3. Telemetry and adversarial tests ship in the same change as the seam they cover

For each change that added a seam (an outbound hop, a decision point that can deny, a new route or counter), the test files changed in that same commit:

**output_specs/logs/tests-with-seams.txt**

```text
# For each change that adds a seam: the test files changed in the SAME commit (git show --name-only, filtered to tests)
# The last four entries are the sequence 03 review fix and the PR review fixes, which each added a decision point.

$ git log -1 --format='%h %s' 62c4059; git show --name-only --format= 62c4059 | grep -E '\.test\.'
62c4059 SP-2: abort the egress upstream call when the edge hangs up
apps/egress/src/adversarial.test.ts
apps/egress/src/proxy.test.ts
apps/egress/src/spanAttributes.test.ts

$ git log -1 --format='%h %s' f1b43a2; git show --name-only --format= f1b43a2 | grep -E '\.test\.'
f1b43a2 SP-5: charge cut and failed LLM calls
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/spanRedaction.test.ts

$ git log -1 --format='%h %s' 494776b; git show --name-only --format= 494776b | grep -E '\.test\.'
494776b SP-7: throttle and count LLM admission denials
apps/edge/src/gateway/denialThrottle.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git log -1 --format='%h %s' 3e82db5; git show --name-only --format= 3e82db5 | grep -E '\.test\.'
3e82db5 SP-9: enforce the platform daily LLM ceiling
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/gateway/usage.platformSpendCheck.test.ts
apps/edge/src/gateway/usage.rls.integration.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git log -1 --format='%h %s' f5c315d; git show --name-only --format= f5c315d | grep -E '\.test\.'
f5c315d SP-11: cap concurrent LLM calls and add a call deadline
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/replicaGate.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git log -1 --format='%h %s' df397a2; git show --name-only --format= df397a2 | grep -E '\.test\.'
df397a2 SP-12: add an optional per-app lease cap on the fetch path
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/gateway/fetch.test.ts
apps/edge/src/routing/connectionsJourney.integration.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts

$ git log -1 --format='%h %s' 00e626e; git show --name-only --format= 00e626e | grep -E '\.test\.'
00e626e EG-1: block Azure platform and special-purpose ranges in the SSRF filter
apps/egress/src/adversarial.test.ts
apps/egress/src/ssrf.test.ts

$ git log -1 --format='%h %s' d6043ff; git show --name-only --format= d6043ff | grep -E '\.test\.'
d6043ff EG-2: add a deployment-supplied extra SSRF block list
apps/edge/src/routing/connectionsJourney.integration.test.ts
apps/egress/src/adversarial.test.ts
apps/egress/src/config.test.ts
apps/egress/src/delegated.integration.test.ts
apps/egress/src/exchange.test.ts
apps/egress/src/managedIdentity.test.ts
apps/egress/src/proxy.test.ts
apps/egress/src/renewal.integration.test.ts
apps/egress/src/requestId.test.ts
apps/egress/src/retire.integration.test.ts
apps/egress/src/spanAttributes.test.ts
apps/egress/src/spanOutcome.test.ts
apps/egress/src/ssrf.test.ts
apps/portal/src/routes/connectionsCallback.integration.test.ts

$ git log -1 --format='%h %s' a8ca07a; git show --name-only --format= a8ca07a | grep -E '\.test\.'
a8ca07a EG-8: network probe entry point for egress; host-node checks informational (NSGs do not filter them)
apps/egress/src/netprobe.test.ts

$ git log -1 --format='%h %s' 04bfd6b; git show --name-only --format= 04bfd6b | grep -E '\.test\.'
04bfd6b CT-1: strip policy and reporting headers from proxied responses
apps/edge/src/gateway/fetch.test.ts
apps/egress/src/proxy.test.ts
packages/shared/src/fetch.test.ts

$ git log -1 --format='%h %s' 836673e; git show --name-only --format= 836673e | grep -E '\.test\.'
836673e CT-2: Report-Only tightened CSP, EDGE_IMG_SRC_EXTRA, and the CSP report counter
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/serving/csp.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/serving/serviceWorker.test.ts
apps/edge/src/spanRedaction.test.ts
apps/edge/src/traceBoundary.test.ts

$ git log -1 --format='%h %s' 19f4ca7; git show --name-only --format= 19f4ca7 | grep -E '\.test\.'
19f4ca7 CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_ONLY measurement mode
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/serving/csp.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/serving/serviceWorker.test.ts
apps/portal/src/routes/csp.test.ts

$ git log -1 --format='%h %s' 1aa32c8; git show --name-only --format= 1aa32c8 | grep -E '\.test\.'
1aa32c8 CT-5: edge control/apps domain split with adversarial tests
apps/edge/src/app.test.ts
apps/edge/src/auth/adversarial.test.ts
apps/edge/src/auth/flow.integration.test.ts
apps/edge/src/auth/gate.test.ts
apps/edge/src/auth/validate.test.ts
apps/edge/src/config.test.ts
apps/edge/src/devGateway/consentStart.test.ts
apps/edge/src/routing/connectionsProxy.test.ts
apps/edge/src/routing/consentStart.test.ts
apps/edge/src/routing/hosts.test.ts
apps/edge/src/serving/connectHelper.test.ts
apps/edge/src/serving/cspReport.test.ts

$ git log -1 --format='%h %s' c3f75df; git show --name-only --format= c3f75df | grep -E '\.test\.'
c3f75df CT-8: legacy app-host redirect (EDGE_LEGACY_APP_REDIRECT) with the sunset counter
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/routing/hosts.test.ts
apps/edge/src/routing/legacyRedirect.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
apps/edge/src/traceBoundary.test.ts
packages/shared/src/telemetry.test.ts

$ git log -1 --format='%h %s' 1b0eef3; git show --name-only --format= 1b0eef3 | grep -E '\.test\.'
1b0eef3 Iterate IT-8: refuse worker loads on the gateway, default-src none on proxied responses, keep wss origins, cap CSP report inserts, harden the smoke check
apps/edge/src/config.test.ts
apps/edge/src/gateway/fetch.test.ts
apps/edge/src/serving/csp.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/egress/src/proxy.test.ts
apps/portal/src/routes/csp.test.ts
packages/shared/src/fetch.test.ts

$ git log -1 --format='%h %s' c41a69c; git show --name-only --format= c41a69c | grep -E '\.test\.'
c41a69c Review fix (PR #2): LLM call deadline governs both hops, timeouts after dispatch are charged as a cut, reasoning cap matches the request builder
apps/edge/src/gateway/egressLlmProvider.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/routing/connectionsJourney.integration.test.ts
apps/egress/src/adversarial.test.ts
apps/egress/src/delegated.integration.test.ts
apps/egress/src/exchange.test.ts
apps/egress/src/managedIdentity.test.ts
apps/egress/src/proxy.test.ts
apps/egress/src/requestId.test.ts
apps/egress/src/spanAttributes.test.ts
apps/egress/src/spanOutcome.test.ts
apps/portal/src/routes/connectionsCallback.integration.test.ts
packages/shared/src/fetch.test.ts
packages/shared/src/llmTimeouts.test.ts
packages/shared/src/pricing.test.ts
packages/shared/src/usageEstimate.test.ts

$ git log -1 --format='%h %s' 955af5e; git show --name-only --format= 955af5e | grep -E '\.test\.'
955af5e Merge hardening/01-spend-controls (PR #2 review fix) into network egress; the llm dispatcher keeps the extra SSRF block list
apps/edge/src/routing/connectionsJourney.integration.test.ts
apps/egress/src/adversarial.test.ts
apps/egress/src/delegated.integration.test.ts
apps/egress/src/exchange.test.ts
apps/egress/src/managedIdentity.test.ts
apps/egress/src/proxy.test.ts
apps/egress/src/requestId.test.ts
apps/egress/src/spanAttributes.test.ts
apps/egress/src/spanOutcome.test.ts
apps/portal/src/routes/connectionsCallback.integration.test.ts

$ git log -1 --format='%h %s' 149ac5a; git show --name-only --format= 149ac5a | grep -E '\.test\.'
149ac5a Review fix (PR #3): the probe reports whether a deny was proven, net-verify exits 3 when none was, port checks no longer count, detached-NSG simulation scenario
apps/egress/src/netprobe.test.ts
```

**adversarial telemetry suites at ca0afd1 with OTEL_SDK_DISABLED=1 (logs/adversarial-otel-off.log), last 8 lines**

```text
 ✓  node  apps/edge/src/gateway/telemetry.test.ts (8 tests) 38ms
 ✓  node  apps/edge/src/spanRedaction.test.ts (20 tests) 478ms
     ✓ never leaks oid, scope, or path content on a concurrency cap refusal  328ms

 Test Files  4 passed (4)
      Tests  50 passed (50)
   Start at  00:29:29
   Duration  2.13s (transform 1.24s, setup 0ms, import 1.97s, tests 746ms, environment 0ms)
```

**instrument constants added in this phase (git diff 792557a..ca0afd1 -- packages/shared/src/telemetry.ts | grep '^+export const INSTR_')**

```text
+export const INSTR_EGRESS_UPSTREAM_ABORTS = "helix.egress.upstream_aborts";
+export const INSTR_LEGACY_APP_REDIRECTS = "helix.edge.legacy_app_redirects";
+export const INSTR_CSP_REPORTS = "helix.edge.csp_reports";
+export const INSTR_GATEWAY_CUT_CHARGES = "helix.gateway.cut_charges";
+export const INSTR_GATEWAY_ADMISSION_DENIED = "helix.gateway.admission_denied";
+export const INSTR_GATEWAY_PLATFORM_SPEND_RATIO = "helix.gateway.platform_spend_ratio";
+export const SPAN_LEGACY_APP_REDIRECT = "helix.edge.legacy_app_redirect";
```

The OIDC handoff change (CT-5) also had the dedicated review pass the project rules require: `04_domain_split/results/ct5-review.md`, including one-hunk-at-a-time revert checks.

## 4. Azure-only behavior is labeled unverified in Azure

**output_specs/logs/unverified-in-azure.txt**

```text
$ git grep -i -c "unverified in Azure" origin/hardening/04-domain-split (files and match counts at ca0afd1)
infra/azure/README.md:10
infra/azure/main.bicep:7
apps/docs/src/deploy/updates.md:6
docs/features/network-controls.md:5
docs/adr/0005-ssrf-egress-controls.md:3
apps/docs/src/deploy/configuration.md:3
infra/azure/modules/private-endpoint.bicep:2
infra/azure/modules/nsg.bicep:2
infra/azure/modules/alerts-netprobe.bicep:2
docs/features/observability.md:2
docs/adr/0028-deployment-model-customer-deployed.md:2
infra/netsim/run.mjs:1
infra/azure/modules/network.bicep:1
infra/azure/modules/netprobe-job.bicep:1
infra/azure/modules/firewall.bicep:1
infra/azure/modules/firewall-diagnostics.bicep:1
infra/azure/modules/alerts.bicep:1
docs/features/llm-gateway.md:1
docs/features/connection-providers.md:1
docs/features/authentication.md:1
docs/adr/0051-llm-admission-control.md:1
docs/adr/0044-declarative-wildcard-tls-bindings.md:1
.justfiles/infra.just:1

$ totals
56 matches in 23 files
```

Nothing in this phase was applied to Azure. Each operator rollout section in `apps/docs/src/deploy/updates.md` marks the steps only a real install can verify, and the ADR-0005 amendment carries an empty probe-results table for an operator to fill in.

## 5. No regressions and no new warnings (gate step 3)

This is not one of the four standards in `PHASE_GOAL.md`; it answers the gate's QUALITY step. The checks compare the pre-festival base `792557a` with the tip `ca0afd1`. The baseline run at `792557a` itself is `01_spend_controls/results/00-baseline-gate.md` (231 test files, one failure, the known flaky `connectionsJourney` test); the gate log at the first change, a test-only commit, is kept as `logs/gate-at-first-change-dc287c7.log`.

**output_specs/logs/regression-check.txt**

```text
# Regression and warning checks, 792557a (pre-festival base) against ca0afd1 (tip of the stack)

## Test counts: the gate at the first change (SP-1, a test-only commit on top of 792557a) and at the tip
$ grep -E 'Test Files|Tests  ' logs/gate-at-first-change-dc287c7.log
 Test Files  231 passed (231)
      Tests  3173 passed | 1 skipped (3174)
$ grep -E 'Test Files|Tests  ' logs/check-and-lint.log
 Test Files  243 passed (243)
      Tests  3704 passed | 1 skipped (3705)

## Test files deleted in the phase
$ git diff --name-status --diff-filter=D 792557a..ca0afd1 -- '*.test.ts' '*.test.tsx' '*.test.mjs' | wc -l
0

## Test files added in the phase (12 run under vitest; translate.test.mjs runs under node --test)
$ git diff --name-status --diff-filter=A 792557a..ca0afd1 -- '*.test.ts' '*.test.tsx' '*.test.mjs'
A	apps/edge/src/gateway/leaseStore.inflightCheck.test.ts
A	apps/edge/src/gateway/leaseStore.integration.test.ts
A	apps/edge/src/gateway/leaseStore.test.ts
A	apps/edge/src/gateway/replicaGate.test.ts
A	apps/edge/src/gateway/usage.platformSpendCheck.test.ts
A	apps/edge/src/routing/legacyRedirect.test.ts
A	apps/egress/src/netprobe.test.ts
A	apps/egress/src/ssrfRegistry.test.ts
A	apps/portal/src/netControls/egressHosts.integration.test.ts
A	apps/portal/src/netControls/egressHosts.test.ts
A	infra/netsim/translate.test.mjs
A	packages/shared/src/llmTimeouts.test.ts
A	packages/shared/src/usageEstimate.test.ts

## Test titles removed from existing test files, and whether each still exists at the tip
# (a title line that moved or was re-indented shows as removed in a diff; the check below looks for the title text at ca0afd1)
removed title lines: 30; titles still present at the tip: 25; titles gone: 5
  gone: apps/edge/src/gateway/llm.test.ts :: imposes no cap when the grant omits dollarsPerDay
  gone: apps/edge/src/serving/csp.test.ts :: keeps img-src open (honest trade-off, §4.4)
  gone: packages/shared/src/approval.test.ts :: treats removing a spend cap (→ unlimited) as elevated
  gone: packages/shared/src/approval.test.ts :: treats adding a cap (unlimited → capped) as baseline privilege reduction
  gone: packages/shared/src/approval.test.ts :: applies scalar removal (cap removed)

## The tests that replaced the five titles that are gone (each covers behavior the phase changed on purpose)
$ git show ca0afd1:apps/edge/src/gateway/llm.test.ts | grep -n 'omits dollarsPerDay'
493:  it("enforces the install default when the grant omits dollarsPerDay", async () => {
$ git show ca0afd1:apps/edge/src/serving/csp.test.ts | grep -n -E '^\s*it\(.*img-src' | head -4
40:  it("pins img-src to 'self' data: blob: exactly", () => {
59:  it("widens connect-src and img-src with approved origins", () => {
75:  it("includes wss origins in connect-src but not img-src", () => {
100:  it("widens img-src only with imgSrcExtra (not connect-src) and dedupes", () => {
$ git show ca0afd1:packages/shared/src/approval.test.ts | grep -n -E '^\s*it\(.*(removing an LLM spend cap|adding a cap|scalar removal)'
60:  it("elevates removing an LLM spend cap (requested unset may exceed install default)", () => {
71:  it("treats adding a cap (unset default → capped) as baseline privilege reduction", () => {
883:  it("applies scalar removal (LLM cap removed to install default) from elevated bundle", () => {

## Tests disabled in the phase (.skip, .only, .todo added)
$ git diff 792557a..ca0afd1 -- '*.test.ts' '*.test.tsx' | grep -cE '^\+.*\b(it|describe|test)\.(skip|only|todo)\b'
0
# The one skipped test in both runs is the same pre-existing one:
$ grep 'skipped)' logs/gate-at-first-change-dc287c7.log ; grep 'skipped)' logs/check-and-lint.log
 ✓  node  apps/edge/src/gateway/provider.test.ts (10 tests | 1 skipped)
 ✓  node  apps/edge/src/gateway/provider.test.ts (12 tests | 1 skipped)

## Lint and type-check suppressions added in the phase
$ git diff 792557a..ca0afd1 -- apps packages scripts infra .claude | grep -E '^\+.*(eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck)'
+  // eslint-disable-next-line no-control-regex -- intentional: reject decoded control bytes in rd
# One, in apps/edge/src/auth/validate.ts: the regular expression that rejects control bytes in a return path.
# The same suppression already exists for the same reason at these places in the base commit:
$ git grep -n 'no-control-regex' 792557a -- apps packages
792557a:apps/edge/src/auth/validate.ts:13:// eslint-disable-next-line no-control-regex
792557a:apps/edge/src/serving/paths.ts:17:// eslint-disable-next-line no-control-regex

## Warnings
# ESLint and tsc print nothing but their step lines in the final run:
$ awk '/▶ lint/,/✔ lint/' logs/check-and-lint.log
▶ lint
  $ pnpm lint
$ eslint .
✔ lint passed (7s)
$ awk '/▶ typecheck/,/✔ typecheck/' logs/check-and-lint.log | grep -ciE 'warning|error'
0
# Runtime warnings printed by the test run, counted at SP-1 and at the tip (same two sources, same counts):
$ grep -c 'oidc-provider WARNING' / grep -c 'DEP0123'   logs/gate-at-first-change-dc287c7.log
7 / 1
$ grep -c 'oidc-provider WARNING' / grep -c 'DEP0123'   logs/check-and-lint.log
7 / 1
$ grep -ci 'warning' logs/check-and-lint.log   (all of them are the two sources above, plus the DEP0123 hint line)
9

## Build
$ cat logs/infra-build.log
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

Read together: no test file was deleted and none was disabled. Of 30 test titles a diff shows as removed, 25 are still there (the auth adversarial suite was wrapped so that it runs in both the single-domain and the split layout). The other five tested behavior this phase changed on purpose (an unset budget is no longer unlimited; `img-src` is no longer open) and were replaced by tests of the new behavior. One lint suppression was added, the same one the file already carries for the same kind of expression. The test run prints the same eight runtime warning lines it printed before the phase.

## 6. Review findings and their dispositions (gate step 4)

Also not one of the four standards; it answers the gate's COMPLETENESS step. Each sequence's `results/gate-iterate.md` lists every finding from that sequence's review with what was done about it. The block below counts those rows, prints in full every row that is not simply fixed, and adds the two pull-request reviews.

**output_specs/logs/review-dispositions.txt**

```text
# Review findings and their dispositions

## Sequence reviews: every row of each results/gate-iterate.md, counted by the first word of its Disposition column

$ awk -F'|' '/^\| /{print $3}' 01_spend_controls/results/gate-iterate.md | (skip the header rows) | awk '{print $1}' | sort | uniq -c
   3 Deferred
   1 Documented
  18 Fixed
rows: 22

$ awk -F'|' '/^\| /{print $3}' 02_network_egress/results/gate-iterate.md | (skip the header rows) | awk '{print $1}' | sort | uniq -c
   3 Deferred
   1 Deferred.
  14 Fixed
   1 Not
   1 Recorded
   1 Unverified
rows: 21

$ awk -F'|' '/^\| /{print $3}' 03_csp_and_headers/results/gate-iterate.md | (skip the header rows) | awk '{print $1}' | sort | uniq -c
   1 Bicep
   1 Deferred
   9 Fixed
   1 Unverified
rows: 12

$ awk -F'|' '/^\| /{print $3}' 04_domain_split/results/gate-iterate.md | (skip the header rows) | awk '{print $1}' | sort | uniq -c
   2 Documented
  12 Fixed
   1 Open;
   1 Recorded
rows: 16

## Every row that is not simply Fixed, in full (the deferral or the reason is in the row)

$ grep '^| ' 01_spend_controls/results/gate-iterate.md | grep -v -E '^\| (Finding|---)' | awk -F'|' '$3 !~ /^ Fixed/'
| S-2 dev gateway outside the ceiling | Documented as an accepted precondition (ADR-0051, rollout notes) | IT-1 |
| S-14 portal shows no cap for unset budgets | Deferred: needs the install default exposed through `GET /api/v1/config` and UI work in the portal SPA | Follow-up |
| Suggestions: `pg_temp` in the definer's `search_path`, unused `hour` column, partial index, `truncate` import location, `retry-after` time zone | Deferred: low value now; adopt when the code next changes | Follow-up |
| Testing gate: dev container cannot run the browser lane (no `xauth`, Playwright build mismatch) | Deferred: fix in `.devcontainer/Dockerfile` and `post-create.sh` | Follow-up |

$ grep '^| ' 02_network_egress/results/gate-iterate.md | grep -v -E '^\| (Finding|---)' | awk -F'|' '$3 !~ /^ Fixed/'
| R-4 residual: egress identity has Secrets User on all of kv-platform | Deferred: per-secret grants or a separate egress-only vault (`TODO.md`) | Follow-up |
| G-2 simulation gaps (`Internet` as `0.0.0.0/0` with a blanket accept; the unpinned scenario never exercises the endpoint-subnet allow; no inbound simulation) | Deferred. The inbound rows have static tests (IT-6); the other two are documented limits of the simulation | Follow-up |
| G-3 registry test's CSV parser never reads the real snapshot | Recorded: the EG-3 claim that "a layout guard fails loudly if the CSV format changes" overstates it; the coverage assertions are sound. Committing the CSVs or dropping the parser is follow-up | Follow-up |
| G-4 `egress-hosts` drops ports; platform-covered hosts show as MISSING | Deferred | Follow-up |
| G-7 firewall denial rule deploys on the infra-only first apply | Not changed: harmless (no action group yet), noted | — |
| Carried: EG-8 `AzurePlatformIMDS` decision | Deferred, now in `TODO.md` | IT-7 |
| Carried: Azure-only behaviors (EG-4, EG-5, EG-6, EG-7, EG-9, EG-10) | Unverified in Azure, listed in the feature page and the ADR-0005 probe table | — |

$ grep '^| ' 03_csp_and_headers/results/gate-iterate.md | grep -v -E '^\| (Finding|---)' | awk -F'|' '$3 !~ /^ Fixed/'
| G-2 strict parsing of non-boolean flag values; Bicep both-true | Bicep `fail()` added (deploy-time, unverified in Azure). Strict parsing not done: the repo uses `=== "true"` for every allow-polarity flag | IT-8 |
| G-4 `img-src` spike alert; `disposition` column on `csp_reports` | Deferred (`TODO.md` for the alert; the column needs a migration) | Follow-up |
| Carried: Firefox and Safari behavior, WebRTC and DNS hints, Azure env pass-through | Unverified, labeled in docs | — |

$ grep '^| ' 04_domain_split/results/gate-iterate.md | grep -v -E '^\| (Finding|---)' | awk -F'|' '$3 !~ /^ Fixed/'
| G-3 the control `*` record is absent on new split installs | Documented as unverified in Azure | IT-11 |
| G-5 leftover split environment in a dev container created with `HELIX_APPS_DOMAIN` | Documented: recreate the container | IT-11 |
| Testing: `usage.rls.integration.test.ts` failed once during IT-11 | Recorded as a rare flake (three isolated reruns and two full gates passed) | Follow-up |
| Owner question: does the configured portal control origin need its own ADR? | Open; currently in the ADR-0028 amendment and the feature docs | Owner |

## Dedicated review passes (the definer function and owner policy; the OIDC handoff change)
$ wc -l 01_spend_controls/results/sp8-review.md 04_domain_split/results/ct5-review.md
      24 01_spend_controls/results/sp8-review.md
     288 04_domain_split/results/ct5-review.md
     312 total
$ grep -n -E '^\*\*F-[0-9]+\.' 04_domain_split/results/ct5-review.md | cut -c1-110
191:**F-1. Should fix. Confirmed.** `auth/flow.integration.test.ts:117`: `loginAs` sends `/callback` with the 
197:**F-2. Should fix. Confirmed.** Test 4 (`adversarial.test.ts`, "split layout: cookie scope across domains"
209:**F-3. Should fix (fix or record). Confirmed.** Step 9 calls Test 9 "concurrent redeem race and `prompt=no
214:**F-4. Should fix. Confirmed.** `results/` contains no CT-5 records yet; only `ct4-*` files are there. The
226:**F-5. Note. Confirmed by code reading (not executed).** An app whose slug is a reserved label (`www`, `ap
234:**F-6. Note. Confirmed (revert 3c).** `FakeOidcClient.exchangeCode` (`test/fakes.ts:490`) ignores the call
239:**F-7. Note. Confirmed that the config is accepted (by reading `resolveControlDomain`); the browser impact
246:**F-8. Note. Confirmed.** Smaller gaps against the step 9 list. The behavior holds in each case, but the t
258:**F-9. Note. Confirmed.** `apps/connections-lane/src/world.ts:291`: the comment still says the edge builds
$ grep -n -i -E '^#+ .*(disposition|fix|after the review|resolution)' 04_domain_split/results/ct5-review.md 04_domain_split/results/ct5-control-apps-split.md
04_domain_split/results/ct5-review.md:272:## Resolution (coordinator, 2026-10-10)

## Pull-request reviews (obey-agent, 2026-10-10)
$ gh api repos/lancekrogers/helix/pulls/2/reviews --jq '.[] | (state, submitted_at, issue counts from the body)'
PR #2: CHANGES_REQUESTED 2026-10-10T23:12:00Z - bugs: 2 - suggestions: 0 - nits: 0
$ gh api repos/lancekrogers/helix/pulls/3/reviews --jq '.[] | (state, submitted_at, issue counts from the body)'
PR #3: CHANGES_REQUESTED 2026-10-10T23:12:01Z - bugs: 1 - suggestions: 0 - nits: 0
$ gh api repos/lancekrogers/helix/pulls/4/reviews --jq '.[] | (state, submitted_at, issue counts from the body)'
PR #4: APPROVED 2026-10-10T23:12:02Z - bugs: 0 - suggestions: 0 - nits: 0
$ gh api repos/lancekrogers/helix/pulls/5/reviews --jq '.[] | (state, submitted_at, issue counts from the body)'
PR #5: APPROVED 2026-10-10T23:12:03Z - bugs: 0 - suggestions: 0 - nits: 0
$ gh api repos/lancekrogers/helix/pulls/2/comments --jq '.[] | (path, line, first 200 characters)'
apps/edge/src/gateway/llm.ts:562 **[bug]** `EDGE_LLM_MAX_CALL_MS` defaults to 600000 and is composed into `callSignal`, but the edge-to-egress client and the egress-to-vendor dispatcher still use a 120s `headersTimeout` and `bodyTime
packages/shared/src/pricing.ts:343 **[bug]** `outputTokenCapForEstimate` returns `min(maxTokens, maxOutputTokens)` whenever the client set `maxTokens`. `openAiRequestBody` does not send that value for reasoning models; it sends `max_co
$ gh api repos/lancekrogers/helix/pulls/3/comments --jq '.[] | (path, line, first 200 characters)'
apps/egress/src/netprobe.ts:184 **[bug]** `buildChecks` has no scored deny in the configuration this template actually deploys, so `egress.netprobe_result` with `ok: true` (and `just infra net-verify` exiting 0 on job status Succeed

## The fix for each pull-request finding
$ git log --format='%h %s' -1 c41a69c ; git log --format='%h %s' -1 149ac5a   (in projects/helix)
c41a69c Review fix (PR #2): LLM call deadline governs both hops, timeouts after dispatch are charged as a cut, reasoning cap matches the request builder
149ac5a Review fix (PR #3): the probe reports whether a deny was proven, net-verify exits 3 when none was, port checks no longer count, detached-NSG simulation scenario
$ grep -n -E '^## Finding|^\*\*Confirmed' 01_spend_controls/results/pr2-review-fixes.md 02_network_egress/results/pr3-review-fixes.md | cut -c1-190
01_spend_controls/results/pr2-review-fixes.md:5:## Finding 1: the call deadline never won against the hop timeouts; a silent call that timed out was charged $0
01_spend_controls/results/pr2-review-fixes.md:7:**Confirmed.** `EDGE_LLM_MAX_CALL_MS` defaults to 600000, but the edge-to-egress hop used `EDGE_FETCH_TIMEOUT_MS` (120000) and egress-to-vendo
01_spend_controls/results/pr2-review-fixes.md:17:## Finding 2: the cut-call output estimate was clamped below what the vendor request allows for reasoning models
01_spend_controls/results/pr2-review-fixes.md:19:**Confirmed.** `outputTokenCapForEstimate` returned `min(maxTokens, maxOutputTokens)` when `maxTokens` was set, while the request builder sen
02_network_egress/results/pr3-review-fixes.md:5:## Finding: a green probe did not prove the NSG
02_network_egress/results/pr3-review-fixes.md:7:**Confirmed.** In the default configuration (`deny-list-only`, unpinned private endpoints) every scored check expected `reachable`, so `ok: tr
$ gh pr list -R lancekrogers/helix --state open --json number,reviewDecision,headRefOid --jq '.[] | (number, decision, head)'
#5 APPROVED head=ca0afd1
#4 APPROVED head=e1e071e
#3 CHANGES_REQUESTED head=149ac5a
#2 CHANGES_REQUESTED head=c41a69c
# #2 and #3 stay CHANGES_REQUESTED until the reviewer reads c41a69c and 149ac5a. No re-review has been requested.

## Tasks
$ grep -h '^fest_status' 0*/[0-9]*.md | sort | uniq -c
  50 fest_status: completed
$ fest progress | grep -E 'Overall|blocked'
Overall ████████████████████ 100% (54/54 tasks)
```

Read together: 71 rows across the four sequence reviews, 53 fixed. The other 18 are deferred with the reason in the row, documented as a limit, labeled unverified in Azure, or (one) an open question for the owner. The three pull-request findings were confirmed against the code and fixed in `c41a69c` and `149ac5a`.

**What is still open.** The reviewer has not re-reviewed #2 and #3, so GitHub still shows changes requested on both. No re-review has been requested and no reply posted; that is left to the owner, as is merging. The deferred rows above are the follow-up list in `PRESENTATION.md`.
