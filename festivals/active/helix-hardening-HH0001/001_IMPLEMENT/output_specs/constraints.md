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
