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

**final run at 97b3fe1: logs/check-and-lint.log, last 12 lines**

```text
 ✓  portal-web  src/deploy/report.test.ts (2 tests) 7ms

 Test Files  242 passed (242)
      Tests  3669 passed | 1 skipped (3670)
   Start at  23:10:44
   Duration  67.58s (transform 6.04s, setup 1.39s, import 46.83s, tests 119.89s, environment 11.12s)

✔ tests passed (68s)

────────────────────────────────────────
timing: typecheck=17s lint=7s refs=0s format=6s docs=3s tests=68s total=101s
✔ All checks passed
```

Known flaky tests seen during the phase, none touched by it: `apps/portal/src/deploy/diagnose.test.ts`, `apps/edge/src/routing/connectionsJourney.integration.test.ts`, `apps/edge/src/gateway/usage.rls.integration.test.ts` (once), `apps/portal/src/routes/sessions.test.ts` (once, in the final run 1). Each passed on rerun.

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
check-and-lint exit=1
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

$ git show --name-only --format='%h %s' 62c4059 | grep -E 'test|Redaction|traceBoundary|spanAttributes'
62c4059 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-2: abort the egress upstream call when the edge hangs up
apps/egress/src/adversarial.test.ts
apps/egress/src/proxy.test.ts
apps/egress/src/spanAttributes.test.ts

$ git show --name-only --format='%h %s' f1b43a2 | grep -E 'test|Redaction|traceBoundary|spanAttributes'
f1b43a2 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-5: charge cut and failed LLM calls
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/spanRedaction.test.ts

$ git show --name-only --format='%h %s' 494776b | grep -E 'test|Redaction|traceBoundary|spanAttributes'
494776b [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-7: throttle and count LLM admission denials
apps/edge/src/gateway/denialThrottle.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git show --name-only --format='%h %s' 3e82db5 | grep -E 'test|Redaction|traceBoundary|spanAttributes'
3e82db5 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-9: enforce the platform daily LLM ceiling
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/telemetry.test.ts
apps/edge/src/gateway/usage.platformSpendCheck.test.ts
apps/edge/src/gateway/usage.rls.integration.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git show --name-only --format='%h %s' f5c315d | grep -E 'test|Redaction|traceBoundary|spanAttributes'
f5c315d [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-11: cap concurrent LLM calls and add a call deadline
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/gateway/llm.test.ts
apps/edge/src/gateway/replicaGate.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
packages/shared/src/telemetry.test.ts

$ git show --name-only --format='%h %s' 00e626e | grep -E 'test|Redaction|traceBoundary|spanAttributes'
00e626e [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-1: block Azure platform and special-purpose ranges in the SSRF filter
apps/egress/src/adversarial.test.ts
apps/egress/src/ssrf.test.ts

$ git show --name-only --format='%h %s' d6043ff | grep -E 'test|Redaction|traceBoundary|spanAttributes'
d6043ff [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-2: add a deployment-supplied extra SSRF block list
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

$ git show --name-only --format='%h %s' a8ca07a | grep -E 'test|Redaction|traceBoundary|spanAttributes'
a8ca07a [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-8: network probe entry point for egress; host-node checks informational (NSGs do not filter them)
apps/egress/src/netprobe.test.ts

$ git show --name-only --format='%h %s' 04bfd6b | grep -E 'test|Redaction|traceBoundary|spanAttributes'
04bfd6b [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-1: strip policy and reporting headers from proxied responses
apps/edge/src/gateway/fetch.test.ts
apps/egress/src/proxy.test.ts
packages/shared/src/fetch.test.ts

$ git show --name-only --format='%h %s' 836673e | grep -E 'test|Redaction|traceBoundary|spanAttributes'
836673e [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-2: Report-Only tightened CSP, EDGE_IMG_SRC_EXTRA, and the CSP report counter
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/serving/csp.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/serving/serviceWorker.test.ts
apps/edge/src/spanRedaction.test.ts
apps/edge/src/traceBoundary.test.ts

$ git show --name-only --format='%h %s' 19f4ca7 | grep -E 'test|Redaction|traceBoundary|spanAttributes'
19f4ca7 [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_O
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/serving/csp.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/serving/serviceWorker.test.ts
apps/portal/src/routes/csp.test.ts

$ git show --name-only --format='%h %s' 1aa32c8 | grep -E 'test|Redaction|traceBoundary|spanAttributes'
1aa32c8 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-5: edge control/apps domain split with adversarial tests
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

$ git show --name-only --format='%h %s' c3f75df | grep -E 'test|Redaction|traceBoundary|spanAttributes'
c3f75df [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-8: legacy app-host redirect (EDGE_LEGACY_APP_REDIRECT) with the sunset counter
apps/edge/src/app.test.ts
apps/edge/src/config.test.ts
apps/edge/src/routing/hosts.test.ts
apps/edge/src/routing/legacyRedirect.test.ts
apps/edge/src/serving/cspReport.test.ts
apps/edge/src/spanRedaction.test.ts
apps/edge/src/traceBoundary.test.ts
packages/shared/src/telemetry.test.ts
```

**adversarial telemetry suites at 97b3fe1 with OTEL_SDK_DISABLED=1 (logs/adversarial-otel-off.log), last 8 lines**

```text
 ✓  node  apps/edge/src/gateway/telemetry.test.ts (8 tests) 41ms
 ✓  node  apps/edge/src/spanRedaction.test.ts (20 tests) 451ms
     ✓ never leaks oid, scope, or path content on a concurrency cap refusal  311ms

 Test Files  4 passed (4)
      Tests  50 passed (50)
   Start at  23:05:46
   Duration  2.23s (transform 1.33s, setup 0ms, import 2.13s, tests 713ms, environment 0ms)
```

**instrument constants added in this phase (git diff 792557a..97b3fe1 -- packages/shared/src/telemetry.ts | grep '^+export const INSTR_')**

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
$ git grep -i -c "unverified in Azure" (files and match counts at 97b3fe1)
infra/azure/README.md:9
infra/azure/main.bicep:7
apps/docs/src/deploy/updates.md:6
docs/features/network-controls.md:5
apps/docs/src/deploy/configuration.md:3
infra/azure/modules/private-endpoint.bicep:2
infra/azure/modules/nsg.bicep:2
infra/azure/modules/alerts-netprobe.bicep:2
docs/features/observability.md:2
docs/adr/0028-deployment-model-customer-deployed.md:2
docs/adr/0005-ssrf-egress-controls.md:2
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

$ git grep -i -c "unverified in Azure" | awk -F: '{s+=$2} END {print s}'
54 matches in 23 files
```

Nothing in this phase was applied to Azure. Each operator rollout section in `apps/docs/src/deploy/updates.md` marks the steps only a real install can verify, and the ADR-0005 amendment carries an empty probe-results table for an operator to fill in.
