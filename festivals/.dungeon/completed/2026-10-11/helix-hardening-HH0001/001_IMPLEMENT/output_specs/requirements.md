# Requirements: each required outcome with the raw output that verifies it

Required outcomes are from `PHASE_GOAL.md`. Every fenced block below is pasted from a log file or a command run, not retyped. Sequence-gate logs are in each sequence's `results/` folder; the final verification at the last commit is in `output_specs/logs/`.

Each sequence section ends with **Outcome against SEQUENCE_GOAL.md**: one row per required deliverable in that file, with the commits, the result records, and whether the result differs from the goal's wording.

**Status of "merged on the private remote":** each change was fast-forwarded onto `main` and pushed to the private remote at its sequence boundary. On 2026-10-10 the owner asked for pull requests, so `main` was moved back to `792557a` and the work now sits on four stacked branches in open, ready-for-review PRs (#2 to #5). The automated reviewer approved #4 and #5 and requested changes on #2 and #3, all at 23:12 UTC. The fixes for #2 and #3 were pushed afterwards (`c41a69c`, `149ac5a`) and merged forward through the stack, so every branch now has commits the reviewer has not seen: #2 and #3 await re-review, and the approvals on #4 and #5 were given before the merge commits that brought the fixes into them (GitHub's API lists those approvals against the current heads; `context.md` explains why that cannot be what was read). The commits are on the private remote; merging them into `main` is the owner's step and has not happened yet. See `context.md`.

## Final verification at the last commit (covers all four outcomes)

**output_specs/logs/head.txt**

```text
HEAD ca0afd1ce96fe2781426ea0ad9a82881dc2ade27
branch hardening/04-domain-split
modified files before runs: 0
```

**output_specs/logs/summary.txt (exit code of each command)**

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

**./check-and-lint.sh (logs/check-and-lint.log), last 12 lines**

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

**just infra build (logs/infra-build.log)**

```text
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

**adversarial telemetry suites with OTEL_SDK_DISABLED=1 (logs/adversarial-otel-off.log), last 6 lines**

```text

 Test Files  4 passed (4)
      Tests  50 passed (50)
   Start at  00:29:29
   Duration  2.13s (transform 1.24s, setup 0ms, import 1.97s, tests 746ms, environment 0ms)

```

**just dev smoke, single-domain, real browser (logs/smoke-single-domain.log), last 25 lines**

```text

egress — mechanism plane (attested instruction verification)
  ✓ health is liveness-only
  ✓ missing instruction headers → 400
  ✓ forged instruction is refused before dialing the target

portal SPA — vite build, served by the portal
  ✓ vite production build  1731 modules
  ✓ portal serves the built index.html  2 hashed assets
  ✓ hashed assets resolve with correct content types  2 ok
  ✓ SPA deep link falls through to index (client routing)

browser — real Chromium over CDP
  ✓ signed-out shell renders without page errors  /tmp/helix-smoke-AVuOVQ/signed-out.png
  ✓ authenticated dashboard renders  /tmp/helix-smoke-AVuOVQ/dashboard.png
  ✓ authenticated apps-list renders  /tmp/helix-smoke-AVuOVQ/apps-list.png
  ✓ enforced CSP blocks remote image and records violation for smoke-csp  25 report(s); disposition="enforce"
  ✓ granted origin appears in smoke-csp CSP  https://smoke-public.local.helix.azxlabs.io:9080

helix CLI — esbuild bundle driven against the live portal
  ✓ esbuild bundle  built
  ✓ CLI reads versions from the live portal  smoke-public: 53 versions

────────────────────────────────────────────────────────────
37 passed, 0 failed, 0 skipped
```

**just dev smoke, HELIX_APPS_DOMAIN=helix-apps.localhost, real browser (logs/smoke-split.log), split group and summary**

```text
split-tls — split cert, Node fetch, and Chromium on the apps domain
  ✓ split TLS cert and key exist  local-helix-split.pem
split — cross-domain login, Sec-Fetch-Site, cookies, silent refresh
  ✓ HTTP login across control and apps domains  smoke-internal on helix-apps.localhost
  ✓ legacy control host redirects to apps origin  https://smoke-internal.helix-apps.localhost:9080/
  ✓ browser login lands on the app host  https://smoke-internal.helix-apps.localhost:9080/
  Sec-Fetch-Site on the handoff: none
  ✓ Sec-Fetch-Site on handoff and credentialed fetches  handoff=none, me=same-origin, sibling=same-site, control=cross-site
  ✓ app-set cookies do not reach the control host  no probe or session on control host
  ✓ silent refresh through auth host  silent=1 chain completed
47 passed, 0 failed, 0 skipped
```

**just dev smoke, same-site pair HELIX_APPS_DOMAIN=apps.local.helix.azxlabs.io (logs/smoke-same-site-pair.log), split group and summary**

```text
split — cross-domain login, Sec-Fetch-Site, cookies, silent refresh
  Sec-Fetch-Site on the handoff: none
  ✓ Sec-Fetch-Site on handoff and credentialed fetches  handoff=none, me=same-origin, sibling=same-site, control=same-site
  ✓ app-set cookies do not reach the control host  fallback pair: probe_ctl reached auth (expected without PSL)
47 passed, 0 failed, 0 skipped
```

**just check lane, single-domain (logs/lane-single-domain.log)**

```text
  ✓   1 src/failures.spec.ts:24:1 › timeout — completion at/after expiry cannot establish a connection, and the app's wait ends legibly (672ms)
  ✓   2 src/failures.spec.ts:69:1 › lost completion signaling — the completion response lost in flight: no fabricated success, and the saved connection serves the next call (750ms)
  ✓   3 src/failures.spec.ts:127:1 › forged success from the app's own window is rejected — never reads as successful consent (525ms)
  ✓   4 src/failures.spec.ts:162:1 › forged success from the vendor's page is rejected by the origin rule (491ms)
  ✓   5 src/journeys.spec.ts:25:1 › explicit successful consent — the full journey, Bearer placement (623ms)
  ✓   6 src/journeys.spec.ts:77:1 › explicit successful consent — named-header placement reaches the API destination (579ms)
  ✓   7 src/journeys.spec.ts:122:1 › blocked opening — the REAL popup blocker returns `blocked` for the gesture's second popup, with no navigation and no retry (497ms)
  ✓   8 src/journeys.spec.ts:150:1 › denial — distinct outcome, keyboard-completable popup with managed focus (525ms)
  ✓   9 src/journeys.spec.ts:184:1 › cancellation — closing the popup mid-journey acknowledges the cancel and resolves `cancelled` (672ms)
  ✓  10 src/my-connections.spec.ts:16:1 › disconnect through the real My Connections page — the next delegated call answers connection_required (1.7s)
  10 passed (12.6s)
```

**just check lane, HELIX_APPS_DOMAIN=helix-apps.localhost (logs/lane-split.log)**

```text
  ✓   1 src/failures.spec.ts:24:1 › timeout — completion at/after expiry cannot establish a connection, and the app's wait ends legibly (664ms)
  ✓   2 src/failures.spec.ts:69:1 › lost completion signaling — the completion response lost in flight: no fabricated success, and the saved connection serves the next call (721ms)
  ✓   3 src/failures.spec.ts:127:1 › forged success from the app's own window is rejected — never reads as successful consent (666ms)
  ✓   4 src/failures.spec.ts:162:1 › forged success from the vendor's page is rejected by the origin rule (546ms)
  ✓   5 src/journeys.spec.ts:25:1 › explicit successful consent — the full journey, Bearer placement (604ms)
  ✓   6 src/journeys.spec.ts:77:1 › explicit successful consent — named-header placement reaches the API destination (562ms)
  ✓   7 src/journeys.spec.ts:122:1 › blocked opening — the REAL popup blocker returns `blocked` for the gesture's second popup, with no navigation and no retry (529ms)
  ✓   8 src/journeys.spec.ts:150:1 › denial — distinct outcome, keyboard-completable popup with managed focus (490ms)
  ✓   9 src/journeys.spec.ts:184:1 › cancellation — closing the popup mid-journey acknowledges the cancel and resolves `cancelled` (891ms)
  ✓  10 src/my-connections.spec.ts:16:1 › disconnect through the real My Connections page — the next delegated call answers connection_required (1.5s)
  10 passed (12.9s)
```

**node --test infra/netsim/translate.test.mjs (logs/netsim-static.log), summary lines**

```text
ℹ tests 21
ℹ suites 0
ℹ pass 21
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 38.014391
```

**just infra net-sim on the Docker host (logs/netsim.log), scenario table**

```text
scenario	result	detail
off	PASS	exit 0 (want 0)
deny-list-only	PASS	exit 0 (want 0)
enforce	PASS	exit 0 (want 0)
deny-list-only-unpinned	PASS	exit 0 (want 0)
break-kv	PASS	exit 1 (want 1)
break-order	PASS	exit 1 (want 1)
broken-closing-deny	PASS	exit 1 (want 1)
nsg-detached	PASS	exit 1 (want 1)
```

An earlier run of this verification, at the previous tip `97b3fe1`, hit one flaky test on its first full-gate run and passed on the rerun. Those two logs are kept in `logs/earlier-run-at-97b3fe1/`. The run above, at `ca0afd1`, passed first time.

## Required outcome: 01_spend_controls (SP-1 to SP-13)

Landed on branch `hardening/01-spend-controls`, PR #2.

**git log --oneline --reverse 792557a..origin/hardening/01-spend-controls**

```text
dc287c7 SP-1: characterize egress behavior on a hang-up after the first byte
62c4059 SP-2: abort the egress upstream call when the edge hangs up
e9b00b7 SP-3: add the cut-stream usage estimate
26cb797 SP-4: yield usage events from the provider mappers
f1b43a2 SP-5: charge cut and failed LLM calls
57b8b7d SP-6: enforce an install default for an unset LLM budget
494776b SP-7: throttle and count LLM admission denials
98e7b82 SP-8: add the platform LLM spend definer function
3e82db5 SP-9: enforce the platform daily LLM ceiling
b793f94 SP-10: add the in-flight lease store and table
f5c315d SP-11: cap concurrent LLM calls and add a call deadline
df397a2 SP-12: add an optional per-app lease cap on the fetch path
8bb294f SP-13: add ADR-0051, operator rollout notes, and spend-control docs
48f86da Iterate IT-1: fix rollout order, add lease-table startup check, abort calls before shutdown deadline
a4423eb Iterate IT-2: bound cut-call charges by model limits and raise the default platform ceiling
52ab612 Iterate IT-3: classify new LLM grants and app-creation capabilities, keep create response compatible
be1e6aa Iterate IT-4: close hang-up windows, fix egress hang-up telemetry, bound lease lock waits
ecdc5b3 Iterate IT-5: make spend-control tests prove their behavior, declare the visibilityGroupIds default
c41a69c Review fix (PR #2): LLM call deadline governs both hops, timeouts after dispatch are charged as a cut, reasoning cap matches the request builder
```

### Sequence gate, as run when the sequence closed

**results/gate-testing-head.txt (commit the sequence gate ran on)**

```text
8bb294f [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-13: add ADR-0051, operator rollout notes, and spend-control docs
```

**results/gate-testing-summary.txt (exit code of each gate command)**

```text
full gate run 1 exit=1
full gate run 2 exit=0
adversarial suites (OTEL off) exit=0
infra build exit=0
smoke exit=0
smoke (EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100) exit=0
browser lane exit=3
untracked/modified files after gate: 0
```

**results/gate-testing-full-2.log, step summary**

```text
✔ typecheck passed (20s)
✔ lint passed (8s)
✔ refs passed (0s)
✔ format passed (7s)
✔ docs passed (3s)
 Test Files  236 passed (236)
      Tests  3291 passed | 1 skipped (3292)
✔ tests passed (58s)
✔ All checks passed
```

**results/gate-testing-infra-build.log**

```text
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

**results/gate-testing-smoke.log, last 3 lines**

```text

────────────────────────────────────────────────────────────
31 passed, 0 failed, 1 skipped
```

Sequence 01's summary shows two non-zero exits, both resolved at the time and written up in `results/gate-testing.md`: full gate run 1 failed on `apps/portal/src/deploy/diagnose.test.ts` (a timing bound that flaked before this work; run 2 passed), and the browser lane first exited 3 because the dev container lacked `xauth` and the lane's Chromium build. After installing them the lane passed:

**results/gate-testing-browser-lane.log, result lines**

```text
  10 passed (15.1s)
```

**results/gate-testing-smoke-browser.log, last 2 lines (real browser)**

```text
────────────────────────────────────────────────────────────
34 passed, 0 failed, 0 skipped
```

The sequence-gate logs above were taken at the sequence's close. Commits added later by PR review and the merge commits are covered by the final verification at the top.

### Outcome against 01_spend_controls/SEQUENCE_GOAL.md

| Required deliverable | Changes (commit) | Result records in `results/` | Differs from the goal's wording? |
| --- | --- | --- | --- |
| Hang-up reaches the vendor call | SP-1 dc287c7, SP-2 62c4059, IT-4 be1e6aa | `sp1-hangup-characterization.md`, `sp2-egress-upstream-abort.md`, `it4-hangup-telemetry-leases.md` | No. IT-4 also covers a client that leaves during admission: no vendor call is made and a cut row is written. |
| Cut and failed calls are charged | SP-3 e9b00b7, SP-4 26cb797, SP-5 f1b43a2, IT-2 a4423eb, PR #2 fix c41a69c | `sp3-cut-stream-usage-estimate.md`, `sp4-provider-usage-events.md`, `sp5-charge-cut-and-failed-calls.md`, `it2-charge-bounds-ceiling.md`, `pr2-review-fixes.md` | Wider than the goal text. A cut call is charged no more than a completed call could cost (sequence review R-2, owner decision). After PR review, a hop timeout after the request was sent is charged as a cut as well (a connect timeout is not). A cut with nothing relayed is charged its input estimate only; whether to add a floor for silent reasoning calls is an open owner decision. |
| No admitted app is unbounded | SP-6 57b8b7d, IT-3 52ab612 | `sp6-default-llm-budget.md`, `it3-approval-at-create.md` | One difference, recorded in decisions.md: removing an explicit cap stays an approval-required change, because the portal cannot see the edge's install default. IT-3 also sends new LLM grants and capabilities at app creation through approval. |
| Platform daily ceiling | SP-8 98e7b82, SP-9 3e82db5, IT-1 48f86da, IT-2 a4423eb | `sp8-platform-spend-definer-function.md`, `sp8-owner-role.md`, `sp8-review.md`, `sp9-platform-daily-ceiling.md`, `it1-rollout-boot-shutdown.md` | No. Unless set, the Bicep default is derived: the larger of a tenth of the monthly cap and 3 times the per-app default (150 with the defaults, from IT-2). The edge warns at boot when the ceiling is below 3 times the per-app default. |
| Concurrency caps across replicas | SP-10 b793f94, SP-11 f5c315d, SP-12 df397a2, IT-4 be1e6aa, PR #2 fix c41a69c | `sp10-inflight-lease-store.md`, `sp11-llm-concurrency-caps-and-deadline.md`, `sp12-fetch-lease-caps.md`, `it4-hangup-telemetry-leases.md`, `pr2-review-fixes.md` | No. After PR review the two hop timeouts for LLM calls are derived from the call deadline (plus 60 s and plus 120 s), so a shorter hop timeout cannot end a call the deadline still allows. |
| Records | SP-13 8bb294f, IT-1 48f86da | `sp13-adr-and-docs.md`, `it1-rollout-boot-shutdown.md` | No. IT-1 corrected the rollout order in the operator notes (the first draft would have taken LLM calls down during an upgrade). |

SP-7 (494776b, `sp7-admission-denial-throttle.md`) is not a named deliverable: it throttles the denial log line and adds the `helix.gateway.admission_denied` counter that the denial paths above report through.

Differences marked above are recorded with their reasons in `workflow/design/helix-spend-containment-egress/decisions.md` ("Changes during execution") and in the named result record.

**test files named for these deliverables, as they passed in the final gate run at ca0afd1 (lines from logs/check-and-lint.log)**

```text
✓  node  apps/egress/src/proxy.test.ts (35 tests)
✓  node  apps/egress/src/adversarial.test.ts (43 tests)
✓  node  apps/egress/src/spanAttributes.test.ts (12 tests)
✓  node  packages/shared/src/usageEstimate.test.ts (17 tests)
✓  node  packages/shared/src/pricing.test.ts (18 tests)
✓  node  apps/edge/src/gateway/llm.test.ts (73 tests)
✓  node  apps/edge/src/gateway/egressLlmProvider.test.ts (6 tests)
✓  node  packages/shared/src/approval.test.ts (80 tests)
✓  node  apps/portal/src/routes/apps.test.ts (39 tests)
✓  node  apps/edge/src/config.test.ts (87 tests)
✓  node  apps/edge/src/gateway/usage.platformSpendCheck.test.ts (5 tests)
✓  node  apps/edge/src/gateway/usage.rls.integration.test.ts (15 tests)
✓  node  apps/edge/src/registry/role-split.integration.test.ts (22 tests)
✓  node  apps/edge/src/gateway/leaseStore.test.ts (9 tests)
✓  node  apps/edge/src/gateway/leaseStore.integration.test.ts (10 tests)
✓  node  apps/edge/src/gateway/replicaGate.test.ts (3 tests)
✓  node  apps/edge/src/gateway/fetch.test.ts (66 tests)
✓  node  packages/shared/src/llmTimeouts.test.ts (1 test)
```

**files named for these deliverables: git cat-file -e ca0afd1:<path>**

```text
present  docs/adr/0051-llm-admission-control.md
present  docs/adr/0021-metering-ledger.md
present  docs/adr/0002-postgres-role-split-rls.md
present  docs/adr/0011-in-memory-rate-limiting.md
present  docs/adr/0028-deployment-model-customer-deployed.md
present  apps/docs/src/deploy/updates.md
present  TODO.md
```

**per-install settings and their defaults: git grep -n -E '<names>' ca0afd1 -- infra/azure/main.bicep**

```text
infra/azure/main.bicep:79:param llmDefaultDollarsPerDay int = 50
infra/azure/main.bicep:83:param llmPlatformDollarsPerDay int = -1
infra/azure/main.bicep:87:param llmMaxAppInFlight int = 10
infra/azure/main.bicep:91:param llmMaxUserInFlight int = 3
infra/azure/main.bicep:95:param llmMaxInFlight int = 200
infra/azure/main.bicep:100:param llmMaxCallMs int = 600000
infra/azure/main.bicep:117:param fetchMaxAppInFlight int = 0
```

**Sequence quality standards**

| Standard in SEQUENCE_GOAL.md | Where the proof is |
| --- | --- |
| Gate | Per-change `*-gate.txt` records and the sequence gate above; `constraints.md` standards 1 and 2. |
| Telemetry and adversarial tests ship with the seam | `constraints.md` standard 3 (`logs/tests-with-seams.txt`, the OTEL-off run). |
| Edge database surface is pinned | `role-split.integration.test.ts` in the test lines above; ADR-0002 amended (36 lines added, `git diff --stat` in `context.md`). |
| Azure honesty | `constraints.md` standard 4; `logs/infra-build.log`. |

**no task skipped or left open: grep -H '^fest_status' 01_spend_controls/[0-9]*.md**

```text
01_sp1_hangup_characterization_test.md:fest_status: completed
02_sp2_egress_upstream_abort.md:fest_status: completed
03_sp3_cut_stream_usage_estimate.md:fest_status: completed
04_sp4_provider_usage_events.md:fest_status: completed
05_sp5_charge_cut_and_failed_calls.md:fest_status: completed
06_sp6_default_llm_budget.md:fest_status: completed
07_sp7_admission_denial_throttle.md:fest_status: completed
08_sp8_platform_spend_definer_function.md:fest_status: completed
09_sp9_platform_daily_ceiling.md:fest_status: completed
10_sp10_inflight_lease_store.md:fest_status: completed
11_sp11_llm_concurrency_caps_and_deadline.md:fest_status: completed
12_sp12_fetch_lease_caps.md:fest_status: completed
13_sp13_adr_and_docs.md:fest_status: completed
14_testing.md:fest_status: completed
15_review.md:fest_status: completed
16_iterate.md:fest_status: completed
17_fest_commit.md:fest_status: completed
```

The testing, review, iterate and commit gates are the last four tasks above. Their records are `results/gate-testing.md`, `results/review-01-spend-controls.md` and `results/gate-iterate.md` (each review finding with its disposition).

**ls 01_spend_controls/results/*.md**

```text
00-baseline-gate.md
gate-iterate.md
gate-testing.md
it1-rollout-boot-shutdown.md
it2-charge-bounds-ceiling.md
it3-approval-at-create.md
it4-hangup-telemetry-leases.md
it5-test-quality.md
pr2-review-fixes.md
review-01-spend-controls.md
sp1-hangup-characterization.md
sp10-inflight-lease-store.md
sp11-llm-concurrency-caps-and-deadline.md
sp12-fetch-lease-caps.md
sp13-adr-and-docs.md
sp2-egress-upstream-abort.md
sp3-cut-stream-usage-estimate.md
sp4-provider-usage-events.md
sp5-charge-cut-and-failed-calls.md
sp6-default-llm-budget.md
sp7-admission-denial-throttle.md
sp8-owner-role.md
sp8-platform-spend-definer-function.md
sp8-review.md
sp9-platform-daily-ceiling.md
```

## Required outcome: 02_network_egress (EG-1 to EG-11)

Landed on branch `hardening/02-network-egress`, PR #3.

**git log --oneline --reverse origin/hardening/01-spend-controls..origin/hardening/02-network-egress**

```text
00e626e EG-1: block Azure platform and special-purpose ranges in the SSRF filter
d6043ff EG-2: add a deployment-supplied extra SSRF block list
d819e8e EG-3: test the SSRF block list against the IANA special-purpose registries
7528396 EG-4: add opt-in fixed private-endpoint addresses
edbadc2 EG-5: add the egress subnet NSG from a shared rule table, deny-list-only by default
daab135 EG-6: split firewall platform lists per subnet and default threat intel to Deny
4b6bcc6 EG-7: add the firewall allow-list tier, denial alert, and egress-hosts drift check
a8ca07a EG-8: network probe entry point for egress; host-node checks informational (NSGs do not filter them)
e78b716 EG-9: scheduled network probe job, netControls output and probe alerts
03a9d23 EG-10: local network simulation and net-verify recipe
96e54b3 EG-11: network egress docs, ADR amendments and rollout notes
0f4e5de Iterate IT-6: open the ILB backend ports, drop the 168.63.129.16 deny, allow egress's own Key Vault, keep the CGNAT deny out of the default mode
74b1484 Iterate IT-7: network upgrade section with NSG hold-off, outbound-only probe caveat, kv-platform limit, corrected docs and parameter files
955af5e Merge hardening/01-spend-controls (PR #2 review fix) into network egress; the llm dispatcher keeps the extra SSRF block list
149ac5a Review fix (PR #3): the probe reports whether a deny was proven, net-verify exits 3 when none was, port checks no longer count, detached-NSG simulation scenario
```

### Sequence gate, as run when the sequence closed

**results/gate-testing-head.txt (commit the sequence gate ran on)**

```text
96e54b3 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-11: network egress docs, ADR amendments and rollout notes
```

**results/gate-testing-summary.txt (exit code of each gate command)**

```text
full gate run 1 exit=0
full gate run 2 exit=0
adversarial suites (OTEL off) exit=0
infra build exit=0
smoke exit=0
browser lane exit=0
untracked/modified files after gate: 0
net-sim (host) exit=0
```

**results/gate-testing-full-2.log, step summary**

```text
✔ typecheck passed (13s)
✔ lint passed (6s)
✔ refs passed (0s)
✔ format passed (5s)
✔ docs passed (3s)
 Test Files  241 passed (241)
      Tests  3491 passed | 1 skipped (3492)
✔ tests passed (54s)
✔ All checks passed
```

**results/gate-testing-infra-build.log**

```text
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

**results/gate-testing-smoke.log, last 3 lines**

```text

────────────────────────────────────────────────────────────
31 passed, 0 failed, 1 skipped
```

**results/gate-testing-browser-lane.log, result lines**

```text
  10 passed (11.9s)
```

**results/gate-testing-netsim.log, scenario table**

```text
scenario	result	detail
off	PASS	exit 0 (want 0)
deny-list-only	PASS	exit 0 (want 0)
enforce	PASS	exit 0 (want 0)
deny-list-only-unpinned	PASS	exit 0 (want 0)
break-kv	PASS	exit 1 (want 1)
break-order	PASS	exit 1 (want 1)
broken-closing-deny	PASS	exit 1 (want 1)
```

The sequence-gate logs above were taken at the sequence's close. Commits added later by PR review and the merge commits are covered by the final verification at the top.

### Outcome against 02_network_egress/SEQUENCE_GOAL.md

| Required deliverable | Changes (commit) | Result records in `results/` | Differs from the goal's wording? |
| --- | --- | --- | --- |
| Complete block list | EG-1 00e626e, EG-3 d819e8e | `eg1-block-list-additions.md`, `eg3-registry-completeness.md` | No. |
| Deployment-supplied extra block list | EG-2 d6043ff, merge 955af5e | `eg2-extra-block-list.md`, `pr3-review-fixes.md` | No. The PR #2 fix split the egress dispatcher in two; the merge into this branch passes the extra list to the new LLM dispatcher too, with a test that fails without it. |
| NSG on `snet-egress` on every install | EG-4 7528396, EG-5 edbadc2, IT-6 0f4e5de | `eg4-fixed-pe-addresses.md`, `eg5-nsg-module.md`, `it6-nsg-table-fixes.md` | Yes, four recorded differences. Pinned private-endpoint addresses are opt-in (`pinPrivateEndpointAddresses`, default false). The default mode is `deny-list-only`, outbound only. The inbound allow includes the load balancer's backend ports 31080 and 31443, and the rule denying 168.63.129.16 is gone, because Microsoft documents that NSGs do not filter it and that it must not be denied. With pinning on, egress may reach the platform Key Vault, which it needs for its own secrets. |
| Firewall tiers | EG-6 daab135, EG-7 4b6bcc6 | `eg6-firewall-platform-lists.md`, `eg7-firewall-allowlist.md` | No. Compile-checked only; firewall behavior is unverified in Azure. |
| Posture probe | EG-8 a8ca07a, EG-9 e78b716, IT-6 0f4e5de, PR #3 fix 149ac5a | `eg8-probe-entry-point.md`, `eg9-probe-job.md`, `pr3-review-fixes.md` | Yes. The wire-server and IMDS checks are informational, because an NSG cannot block them. The platform Key Vault is expected reachable. After PR review the probe says whether any deny was proven, and port-only checks no longer count as proof. |
| Local proof | EG-10 03a9d23, IT-6 0f4e5de, PR #3 fix 149ac5a | `eg10-netsim.md`, `it6-nsg-table-fixes.md`, `pr3-review-fixes.md` | No. Eight scenarios now, including an unpinned install and a detached NSG; `just infra net-verify` exits 3 when the probe could not prove a deny. See the net-sim table and translator tests in the final verification above. |
| Records | EG-11 96e54b3, IT-7 74b1484 | `eg11-docs-and-adrs.md`, `it7-network-docs.md` | No. IT-7 added an upgrade section that tells existing installs to hold the NSG off until a scratch-copy test. |

Differences marked above are recorded with their reasons in `workflow/design/helix-spend-containment-egress/decisions.md` ("Changes during execution") and in the named result record.

**test files named for these deliverables, as they passed in the final gate run at ca0afd1 (lines from logs/check-and-lint.log)**

```text
✓  node  apps/egress/src/ssrf.test.ts (116 tests)
✓  node  apps/egress/src/ssrfRegistry.test.ts (37 tests)
✓  node  apps/egress/src/adversarial.test.ts (43 tests)
✓  node  apps/egress/src/config.test.ts (38 tests)
✓  node  apps/portal/src/netControls/egressHosts.test.ts (8 tests)
✓  node  apps/portal/src/netControls/egressHosts.integration.test.ts (1 test)
✓  node  apps/egress/src/netprobe.test.ts (64 tests)
```

**files named for these deliverables: git cat-file -e ca0afd1:<path>**

```text
present  infra/azure/nsg-egress-rules.json
present  infra/azure/modules/nsg.bicep
present  infra/azure/modules/firewall.bicep
present  infra/azure/modules/firewall-diagnostics.bicep
present  apps/egress/src/netprobe.ts
present  infra/azure/modules/netprobe-job.bicep
present  infra/azure/modules/alerts-netprobe.bicep
present  infra/netsim/translate.mjs
present  infra/netsim/run.mjs
present  .justfiles/infra.just
present  docs/adr/0005-ssrf-egress-controls.md
present  docs/adr/0028-deployment-model-customer-deployed.md
present  docs/adr/0046-azure-ai-foundry-keyless-llm-backend.md
present  docs/features/network-controls.md
present  infra/azure/README.md
```

**per-install settings and their defaults: git grep -n -E '<names>' ca0afd1 -- infra/azure/main.bicep**

```text
infra/azure/main.bicep:72:param pinPrivateEndpointAddresses bool = false
infra/azure/main.bicep:426:param egressFqdnMode string = 'any'
infra/azure/main.bicep:429:param egressAllowedFqdns array = []
infra/azure/main.bicep:434:param threatIntelMode string = 'Deny'
infra/azure/main.bicep:439:param egressNsgEnforce string = 'deny-list-only'
infra/azure/main.bicep:448:param deployNetprobe bool = true
infra/azure/main.bicep:457:param netprobeClosingDenyTarget string = ''
```

**Sequence quality standards**

| Standard in SEQUENCE_GOAL.md | Where the proof is |
| --- | --- |
| Gate | Per-change `*-gate.txt` records and the sequence gate above. |
| Azure honesty | `constraints.md` standard 4; the ADR-0005 probe-results table reads "not yet run on a real install" in every row. |
| Where each proof runs | `logs/netsim-static.log` ran in the dev container, `logs/netsim.log` on the host's Docker daemon (`logs/summary.txt` names both). |
| Telemetry ships with the seam | `netprobe.test.ts` in the test lines above; both log events are listed in `docs/design/logging.md` line 139. |
| Stricter behavior is per install | Parameter defaults at the tip, pasted above. |
| No live-install change | Nothing was applied to Azure. This cannot be shown by output; the session had no access to the installs or their deployments repo. |

**no task skipped or left open: grep -H '^fest_status' 02_network_egress/[0-9]*.md**

```text
01_eg1_block_list_additions_and_boundary_tests.md:fest_status: completed
02_eg2_deployment_supplied_extra_block_list.md:fest_status: completed
03_eg3_special_purpose_registry_completeness_test.md:fest_status: completed
04_eg4_fixed_private_endpoint_addresses.md:fest_status: completed
05_eg5_nsg_module_and_subnet_attachment.md:fest_status: completed
06_eg6_firewall_platform_lists_and_threat_intel.md:fest_status: completed
07_eg7_firewall_allow_list_tier_and_drift_tooling.md:fest_status: completed
08_eg8_probe_entry_point.md:fest_status: completed
09_eg9_probe_job_posture_output_and_alerts.md:fest_status: completed
10_eg10_local_network_simulation_and_net_verify.md:fest_status: completed
11_eg11_docs_and_adr_amendments.md:fest_status: completed
12_testing.md:fest_status: completed
13_review.md:fest_status: completed
14_iterate.md:fest_status: completed
15_fest_commit.md:fest_status: completed
```

The testing, review, iterate and commit gates are the last four tasks above. Their records are `results/gate-testing.md`, `results/review-02-network-egress.md` and `results/gate-iterate.md` (each review finding with its disposition).

**ls 02_network_egress/results/*.md**

```text
eg1-block-list-additions.md
eg10-netsim.md
eg11-docs-and-adrs.md
eg2-extra-block-list.md
eg3-registry-completeness.md
eg4-fixed-pe-addresses.md
eg5-nsg-module.md
eg6-firewall-platform-lists.md
eg7-firewall-allowlist.md
eg8-probe-entry-point.md
eg9-probe-job.md
gate-iterate.md
gate-testing.md
it6-nsg-table-fixes.md
it7-network-docs.md
pr3-review-fixes.md
review-02-network-egress.md
```

## Required outcome: 03_csp_and_headers (CT-1 to CT-3)

Landed on branch `hardening/03-csp-and-headers`, PR #4.

**git log --oneline --reverse origin/hardening/02-network-egress..origin/hardening/03-csp-and-headers**

```text
04bfd6b CT-1: strip policy and reporting headers from proxied responses
836673e CT-2: Report-Only tightened CSP, EDGE_IMG_SRC_EXTRA, and the CSP report counter
19f4ca7 CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_ONLY measurement mode
1b0eef3 Iterate IT-8: refuse worker loads on the gateway, default-src none on proxied responses, keep wss origins, cap CSP report inserts, harden the smoke check
6cc3753 Iterate IT-9: image-policy hold-off as step 0, origin audit query, proxied-response and report-sink docs, residual channels
e1e071e Merge hardening/02-network-egress (PR #2 and PR #3 review fixes) into CSP and headers
```

### Sequence gate, as run when the sequence closed

**results/gate-testing-head.txt (commit the sequence gate ran on)**

```text
19f4ca7 [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_ONLY measurement mode
```

**results/gate-testing-summary.txt (exit code of each gate command)**

```text
full gate run 1 exit=0
full gate run 2 exit=0
adversarial suites (OTEL off) exit=0
infra build exit=0
smoke exit=0
smoke (HELIX_SMOKE_CHROME=/home/node/.cache/ms-playwright/chromium-1248/chrome-linux-arm64/chrome) exit=0
browser lane exit=0
untracked/modified files after gate: 0
```

**results/gate-testing-full-2.log, step summary**

```text
✔ typecheck passed (13s)
✔ lint passed (6s)
✔ refs passed (0s)
✔ format passed (6s)
✔ docs passed (2s)
 Test Files  241 passed (241)
      Tests  3551 passed | 1 skipped (3552)
✔ tests passed (55s)
✔ All checks passed
```

**results/gate-testing-infra-build.log**

```text
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

**results/gate-testing-smoke.log, last 3 lines**

```text

────────────────────────────────────────────────────────────
32 passed, 0 failed, 1 skipped
```

**results/gate-testing-browser-lane.log, result lines**

```text
  10 passed (12.1s)
```

**results/gate-testing-smoke-extra.log (real browser), last 2 lines**

```text
────────────────────────────────────────────────────────────
37 passed, 0 failed, 0 skipped
```

The sequence-gate logs above were taken at the sequence's close. Commits added later by PR review and the merge commits are covered by the final verification at the top.

### Outcome against 03_csp_and_headers/SEQUENCE_GOAL.md

| Required deliverable | Changes (commit) | Result records in `results/` | Differs from the goal's wording? |
| --- | --- | --- | --- |
| Extended header blocklist | CT-1 04bfd6b, IT-8 1b0eef3 | `ct1-header-blocklist.md`, `it8-fetch-path-and-csp-fixes.md` | Wider than the goal text. IT-8 added `service-worker-allowed` and `alt-svc`, sets `content-security-policy: default-src 'none'` on proxied responses, and refuses worker and service-worker loads of the fetch route. |
| Report-Only tightened policy and report counter | CT-2 836673e, IT-8 1b0eef3 | `ct2-report-only-csp.md`, `it8-fetch-path-and-csp-fixes.md` | Delivered by CT-2, then changed by CT-3 as the goal intends: the Report-Only policy is no longer the default. It remains available as the measurement mode (next row). IT-8 caps report inserts at 100 per app per 10 minutes. |
| Enforced policy and the relaxation | CT-3 19f4ca7, IT-8 1b0eef3 | `ct3-enforce-img-src.md`, `it8-fetch-path-and-csp-fixes.md` | One recorded difference. The goal says the Report-Only header is retired. It is retired by default, but `EDGE_IMG_SRC_REPORT_ONLY` (default false) brings back the measurement headers, so an existing install can measure before enforcing with one image. Setting it together with `EDGE_IMG_SRC_ALLOW_ALL` refuses to boot. The blocked-image, violation and grant path is checked in the real-browser smoke run. |
| Records and agent guidance | CT-1 04bfd6b, CT-2 836673e, CT-3 19f4ca7, IT-9 6cc3753 | `ct3-enforce-img-src.md`, `it9-csp-docs.md` | No. IT-9 added the image-policy hold-off as step 0 of the upgrade notes and an audit query for image origins. |

Differences marked above are recorded with their reasons in `workflow/design/helix-spend-containment-egress/decisions.md` ("Changes during execution") and in the named result record.

**test files named for these deliverables, as they passed in the final gate run at ca0afd1 (lines from logs/check-and-lint.log)**

```text
✓  node  packages/shared/src/fetch.test.ts (30 tests)
✓  node  apps/edge/src/gateway/fetch.test.ts (66 tests)
✓  node  apps/egress/src/proxy.test.ts (35 tests)
✓  node  apps/edge/src/serving/csp.test.ts (24 tests)
✓  node  apps/edge/src/serving/cspReport.test.ts (22 tests)
✓  node  apps/edge/src/serving/serviceWorker.test.ts (31 tests)
✓  node  apps/edge/src/spanRedaction.test.ts (20 tests)
✓  node  apps/edge/src/traceBoundary.test.ts (10 tests)
✓  node  apps/portal/src/routes/csp.test.ts (5 tests)
✓  node  apps/edge/src/config.test.ts (87 tests)
```

**files named for these deliverables: git cat-file -e ca0afd1:<path>**

```text
present  docs/adr/0009-relaxed-csp.md
present  SECURITY.md
present  docs/platform-architecture.md
present  docs/features/edge-serving.md
present  docs/features/observability.md
present  docs/features/fetch-proxy.md
present  apps/edge/README.md
present  apps/docs/src/deploy/configuration.md
present  packages/deploy-skill/SKILL.md
```

**per-install settings and their defaults: git grep -n -E '<names>' ca0afd1 -- infra/azure/main.bicep**

```text
infra/azure/main.bicep:497:param imgSrcExtra string = ''
infra/azure/main.bicep:500:param imgSrcReportOnly bool = false
infra/azure/main.bicep:503:param imgSrcAllowAll bool = false
```

**Sequence quality standards**

| Standard in SEQUENCE_GOAL.md | Where the proof is |
| --- | --- |
| Gate | Per-change `*-gate.txt` records and the sequence gate above. |
| Telemetry ships with the change | `INSTR_CSP_REPORTS` in the constants list in `constraints.md` standard 3; `spanRedaction.test.ts` and `traceBoundary.test.ts` in the test lines above. |
| Stricter behavior is per install | Parameter defaults at the tip, pasted above. |
| Azure honesty | `constraints.md` standard 4. |

**no task skipped or left open: grep -H '^fest_status' 03_csp_and_headers/[0-9]*.md**

```text
01_ct1_proxied_response_header_blocklist.md:fest_status: completed
02_ct2_report_only_csp_and_report_counter.md:fest_status: completed
03_ct3_enforce_img_src_and_object_src.md:fest_status: completed
04_testing.md:fest_status: completed
05_review.md:fest_status: completed
06_iterate.md:fest_status: completed
07_fest_commit.md:fest_status: completed
```

The testing, review, iterate and commit gates are the last four tasks above. Their records are `results/gate-testing.md`, `results/review-03-csp-and-headers.md` and `results/gate-iterate.md` (each review finding with its disposition).

**ls 03_csp_and_headers/results/*.md**

```text
ct1-header-blocklist.md
ct2-report-only-csp.md
ct3-enforce-img-src.md
gate-iterate.md
gate-testing.md
it8-fetch-path-and-csp-fixes.md
it9-csp-docs.md
review-03-csp-and-headers.md
```

## Required outcome: 04_domain_split (CT-4 to CT-10)

Landed on branch `hardening/04-domain-split`, PR #5.

**git log --oneline --reverse origin/hardening/03-csp-and-headers..origin/hardening/04-domain-split**

```text
44b4744 CT-4: second loopback dev domain (HELIX_APPS_DOMAIN)
1aa32c8 CT-5: edge control/apps domain split with adversarial tests
715a772 CT-6: portal control origin (CONTROL_PUBLIC_BASE) for the vendor callback URL
7902a6e CT-7: split-mode smoke (cross-domain login, Sec-Fetch-Site, cookie scope, silent refresh) and split connections lane
c3f75df CT-8: legacy app-host redirect (EDGE_LEGACY_APP_REDIRECT) with the sunset counter
f7ef250 CT-9: Bicep, DNS and certbot for a separate hosted-apps domain (default off)
5c56761 CT-10: domain-split docs, ADR-0028/0019/0044 amendments and hosted-app containment rollout notes
8661102 Iterate IT-10: hostedAppsLive separates apps-domain provisioning from cutover; domain guards, apps-cert probe, NS output, stricter split smoke
97b3fe1 Iterate IT-11: provision/verify/cutover rollout with rollback, containment step 0, callback check, docs aligned with the split boot rules
ca0afd1 Merge hardening/03-csp-and-headers (PR #2 and PR #3 review fixes) into domain split
```

### Sequence gate, as run when the sequence closed

**results/gate-testing-head.txt (commit the sequence gate ran on)**

```text
5c56761 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-10: domain-split docs, ADR-0028/0019/0044 amendments and hosted-app containment rollout notes
```

**results/gate-testing-summary.txt (exit code of each gate command)**

```text
full gate run 1 exit=0
full gate run 2 exit=0
adversarial suites (OTEL off) exit=0
infra build exit=0
smoke exit=0
smoke (HELIX_SMOKE_CHROME=/home/node/.cache/ms-playwright/chromium-1248/chrome-linux-arm64/chrome) exit=0
browser lane exit=0
untracked/modified files after gate: 0
split smoke (helix-apps.localhost) exit=0
split smoke (apps.local.helix.azxlabs.io) exit=0
browser lane split exit=0
untracked/modified after split runs: 0
```

**results/gate-testing-full-2.log, step summary**

```text
✔ typecheck passed (13s)
✔ lint passed (6s)
✔ refs passed (0s)
✔ format passed (5s)
✔ docs passed (3s)
 Test Files  242 passed (242)
      Tests  3667 passed | 1 skipped (3668)
✔ tests passed (55s)
✔ All checks passed
```

**results/gate-testing-infra-build.log**

```text
az bicep build --file infra/azure/main.bicep --stdout > /dev/null
az bicep build-params --file infra/azure/main.bicepparam --stdout > /dev/null
az bicep build-params --file infra/azure/main.bootstrap.bicepparam --stdout > /dev/null
az bicep build --file infra/entra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/entra/main.bicepparam --stdout > /dev/null
```

**results/gate-testing-smoke.log, last 3 lines**

```text

────────────────────────────────────────────────────────────
32 passed, 0 failed, 1 skipped
```

**results/gate-testing-browser-lane.log, result lines**

```text
  10 passed (11.8s)
```

**results/gate-testing-smoke-extra.log (real browser), last 2 lines**

```text
────────────────────────────────────────────────────────────
37 passed, 0 failed, 0 skipped
```

**results/gate-testing-smoke-split-helix-apps.localhost.log, last 2 lines**

```text
────────────────────────────────────────────────────────────
47 passed, 0 failed, 0 skipped
```

**results/gate-testing-smoke-split-apps.local.helix.azxlabs.io.log, last 2 lines**

```text
────────────────────────────────────────────────────────────
47 passed, 0 failed, 0 skipped
```

**results/gate-testing-browser-lane-split.log, result lines**

```text
  10 passed (12.3s)
```

The sequence-gate logs above were taken at the sequence's close. Commits added later by PR review and the merge commits are covered by the final verification at the top.

### Outcome against 04_domain_split/SEQUENCE_GOAL.md

| Required deliverable | Changes (commit) | Result records in `results/` | Differs from the goal's wording? |
| --- | --- | --- | --- |
| A second loopback dev domain | CT-4 44b4744, CT-7 7902a6e | `ct4-second-dev-domain.md`, `ct7-split-smoke-and-lane.md` | No. Proven by the split smoke and lane runs in the final verification above. |
| The edge control/apps split | CT-5 1aa32c8 | `ct5-control-apps-split.md`, `ct5-review.md` | No. The review pass's findings were fixed on the same change (`ct5-review.md`). `ct5-control-apps-split.md` lists the two existing assertions that had to move. |
| A recorded dedicated review pass on the handoff change | CT-5 1aa32c8 | `ct5-review.md` | No. |
| The portal control origin | CT-6 715a772 | `ct6-portal-control-origin.md` | No. Whether the setting deserves its own ADR is an open owner decision. |
| Split mode proven in a real browser, locally | CT-7 7902a6e | `ct7-split-smoke-and-lane.md` | No. Chromium only. The `.localhost` pair is cross-site and the same-site pair is same-site, both in the final verification above. |
| The legacy redirect | CT-8 c3f75df, IT-10 8661102 | `ct8-legacy-redirect.md`, `it10-split-cutover-and-checks.md` | No. |
| Bicep, DNS and certbot for the apps domain | CT-9 f7ef250, IT-10 8661102 | `ct9-bicep-apps-domain.md`, `it10-split-cutover-and-checks.md` | One addition. The review found the template could not prepare the apps domain's certificate before moving apps, so IT-10 added a fourth parameter, `hostedAppsLive` (default false), that separates provisioning from cutover. Compile-checked only. |
| Docs, ADR amendments and operator rollout notes | CT-10 5c56761, IT-11 97b3fe1 | `ct10-docs-and-rollout.md`, `it11-split-rollout-docs.md` | No. IT-11 rewrote the rollout as provision, verify, cut over, with a rollback. |

Differences marked above are recorded with their reasons in `workflow/design/helix-spend-containment-egress/decisions.md` ("Changes during execution") and in the named result record.

**test files named for these deliverables, as they passed in the final gate run at ca0afd1 (lines from logs/check-and-lint.log)**

```text
✓  node  apps/edge/src/auth/adversarial.test.ts (73 tests)
✓  node  apps/edge/src/routing/hosts.test.ts (13 tests)
✓  node  apps/edge/src/auth/validate.test.ts (22 tests)
✓  node  apps/edge/src/auth/flow.integration.test.ts (11 tests)
✓  node  apps/edge/src/auth/gate.test.ts (28 tests)
✓  node  apps/edge/src/config.test.ts (87 tests)
✓  node  apps/portal/src/deployment.test.ts (34 tests)
✓  node  apps/portal/src/routes/providers.test.ts (31 tests)
✓  node  apps/portal/src/routes/config.test.ts (11 tests)
✓  node  apps/edge/src/routing/legacyRedirect.test.ts (17 tests)
✓  node  apps/edge/src/spanRedaction.test.ts (20 tests)
✓  node  apps/edge/src/traceBoundary.test.ts (10 tests)
```

**files named for these deliverables: git cat-file -e ca0afd1:<path>**

```text
present  scripts/stack-env.mjs
present  .claude/skills/run-helix/smoke.mjs
present  .claude/skills/run-helix/cdp.mjs
present  infra/azure/main.bicep
present  docs/adr/0028-deployment-model-customer-deployed.md
present  docs/adr/0019-subdomain-per-app-isolation.md
present  docs/adr/0044-declarative-wildcard-tls-bindings.md
present  apps/docs/src/deploy/updates.md
present  docs/features/authentication.md
present  docs/features/connection-providers.md
```

**per-install settings and their defaults: git grep -n -E '<names>' ca0afd1 -- infra/azure/main.bicep**

```text
infra/azure/main.bicep:476:param hostedAppsDomain string = ''
infra/azure/main.bicep:479:param hostedAppsTlsBound bool = false
infra/azure/main.bicep:482:param hostedAppsLive bool = false
infra/azure/main.bicep:485:param legacyAppRedirect bool = false
```

**Sequence quality standards**

| Standard in SEQUENCE_GOAL.md | Where the proof is |
| --- | --- |
| Gate | Per-change `*-gate.txt` records and the sequence gate above; the lane ran in both modes. |
| The old layout is the first test | Single-domain smoke 37/37 and the single-domain lane in the final verification above; `ct5-control-apps-split.md` lists the edits to existing tests and `ct9-bicep-apps-domain.md` holds the annotated template diff. |
| Telemetry ships with the change | `INSTR_LEGACY_APP_REDIRECTS` and `SPAN_LEGACY_APP_REDIRECT` in the constants list in `constraints.md` standard 3. |
| Stricter behavior is per install | Parameter defaults at the tip, pasted above. |
| Azure and browser honesty | `constraints.md` standard 4; `PRESENTATION.md`, Limits. |

**no task skipped or left open: grep -H '^fest_status' 04_domain_split/[0-9]*.md**

```text
01_ct4_second_loopback_dev_domain.md:fest_status: completed
02_ct5_edge_control_and_apps_domain_split.md:fest_status: completed
03_ct6_portal_control_origin.md:fest_status: completed
04_ct7_smoke_runner_split_mode_and_connections_lane.md:fest_status: completed
05_ct8_legacy_app_host_redirect.md:fest_status: completed
06_ct9_bicep_dns_and_certbot_for_apps_domain.md:fest_status: completed
07_ct10_docs_adr_amendments_and_rollout_notes.md:fest_status: completed
08_testing.md:fest_status: completed
09_review.md:fest_status: completed
10_iterate.md:fest_status: completed
11_fest_commit.md:fest_status: completed
```

The testing, review, iterate and commit gates are the last four tasks above. Their records are `results/gate-testing.md`, `results/review-04-domain-split.md` and `results/gate-iterate.md` (each review finding with its disposition).

**ls 04_domain_split/results/*.md**

```text
ct10-docs-and-rollout.md
ct4-second-dev-domain.md
ct5-control-apps-split.md
ct5-review.md
ct6-portal-control-origin.md
ct7-split-smoke-and-lane.md
ct8-legacy-redirect.md
ct9-bicep-apps-domain.md
gate-iterate.md
gate-testing.md
it10-split-cutover-and-checks.md
it11-split-rollout-docs.md
review-04-domain-split.md
```
