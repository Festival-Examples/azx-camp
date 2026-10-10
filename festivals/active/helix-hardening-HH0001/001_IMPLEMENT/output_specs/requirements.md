# Requirements: each required outcome with the raw output that verifies it

Required outcomes are from `PHASE_GOAL.md`. Every block below is pasted from a log file or a command run, not retyped. Sequence-gate logs are in each sequence's `results/` folder; the final verification at the last commit is in `output_specs/logs/`.

**Status of "merged on the private remote":** each change was fast-forwarded onto `main` and pushed to the private remote at its sequence boundary. On 2026-10-10 the owner asked for pull requests, so `main` was moved back to `792557a` and the same 45 commits now sit on four stacked branches in open, ready-for-review PRs (#2 to #5). They are on the private remote; merging them into `main` is the owner's step and has not happened yet. See `context.md`.

## Final verification at the last commit (covers all four outcomes)

**output_specs/logs/head.txt**

```text
HEAD 97b3fe1fc4e1a4c641614818f0c4f7a6b6ff01f4
branch hardening/04-domain-split
modified files before runs: 0
```

**output_specs/logs/summary.txt (exit code of each command)**

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

`check-and-lint exit=1` in that summary is run 1: one test failed, `apps/portal/src/routes/sessions.test.ts` ("is idempotent: a second revoke reports zero"). No commit in this phase touches that file. It passed 6 of 6 when rerun alone, and the full gate passed on the rerun. Both logs are kept.

**./check-and-lint.sh, run 1 (logs/check-and-lint-run1-one-flaky-failure.log)**

```text
✔ typecheck passed (15s)
✔ lint passed (7s)
✔ refs passed (0s)
✔ format passed (6s)
✔ docs passed (3s)
 FAIL   node  apps/portal/src/routes/sessions.test.ts > POST /api/v1/sessions/revoke > is idempotent: a second revoke reports zero and still records the attempt
 Test Files  1 failed | 241 passed (242)
      Tests  1 failed | 3668 passed | 1 skipped (3670)
✗ tests FAILED (60s)
✗ 1 step(s) failed: tests
```

**sessions.test.ts rerun alone, six times (logs/sessions-test-reruns.log)**

```text
      Tests  14 passed (14)
      Tests  14 passed (14)
      Tests  14 passed (14)
      Tests  14 passed (14)
      Tests  14 passed (14)
      Tests  14 passed (14)
```

**./check-and-lint.sh, run 2 (logs/check-and-lint.log), last 12 lines**

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
   Start at  23:05:46
   Duration  2.23s (transform 1.33s, setup 0ms, import 2.13s, tests 713ms, environment 0ms)

```

**just dev smoke, single-domain, real browser (logs/smoke-single-domain.log), last 25 lines**

```text

egress — mechanism plane (attested instruction verification)
  ✓ health is liveness-only
  ✓ missing instruction headers → 400
  ✓ forged instruction is refused before dialing the target

portal SPA — vite build, served by the portal
  ✓ vite production build  1730 modules
  ✓ portal serves the built index.html  2 hashed assets
  ✓ hashed assets resolve with correct content types  2 ok
  ✓ SPA deep link falls through to index (client routing)

browser — real Chromium over CDP
  ✓ signed-out shell renders without page errors  /tmp/helix-smoke-BrblJQ/signed-out.png
  ✓ authenticated dashboard renders  /tmp/helix-smoke-BrblJQ/dashboard.png
  ✓ authenticated apps-list renders  /tmp/helix-smoke-BrblJQ/apps-list.png
  ✓ enforced CSP blocks remote image and records violation for smoke-csp  22 report(s); disposition="enforce"
  ✓ granted origin appears in smoke-csp CSP  https://smoke-public.local.helix.azxlabs.io:9080

helix CLI — esbuild bundle driven against the live portal
  ✓ esbuild bundle  built
  ✓ CLI reads versions from the live portal  smoke-public: 47 versions

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
  ✓   1 src/failures.spec.ts:24:1 › timeout — completion at/after expiry cannot establish a connection, and the app's wait ends legibly (748ms)
  ✓   2 src/failures.spec.ts:69:1 › lost completion signaling — the completion response lost in flight: no fabricated success, and the saved connection serves the next call (708ms)
  ✓   3 src/failures.spec.ts:127:1 › forged success from the app's own window is rejected — never reads as successful consent (584ms)
  ✓   4 src/failures.spec.ts:162:1 › forged success from the vendor's page is rejected by the origin rule (544ms)
  ✓   5 src/journeys.spec.ts:25:1 › explicit successful consent — the full journey, Bearer placement (609ms)
  ✓   6 src/journeys.spec.ts:77:1 › explicit successful consent — named-header placement reaches the API destination (581ms)
  ✓   7 src/journeys.spec.ts:122:1 › blocked opening — the REAL popup blocker returns `blocked` for the gesture's second popup, with no navigation and no retry (533ms)
  ✓   8 src/journeys.spec.ts:150:1 › denial — distinct outcome, keyboard-completable popup with managed focus (510ms)
  ✓   9 src/journeys.spec.ts:184:1 › cancellation — closing the popup mid-journey acknowledges the cancel and resolves `cancelled` (643ms)
  ✓  10 src/my-connections.spec.ts:16:1 › disconnect through the real My Connections page — the next delegated call answers connection_required (1.5s)
  10 passed (12.7s)
```

**just check lane, HELIX_APPS_DOMAIN=helix-apps.localhost (logs/lane-split.log)**

```text
  ✓   1 src/failures.spec.ts:24:1 › timeout — completion at/after expiry cannot establish a connection, and the app's wait ends legibly (807ms)
  ✓   2 src/failures.spec.ts:69:1 › lost completion signaling — the completion response lost in flight: no fabricated success, and the saved connection serves the next call (747ms)
  ✓   3 src/failures.spec.ts:127:1 › forged success from the app's own window is rejected — never reads as successful consent (575ms)
  ✓   4 src/failures.spec.ts:162:1 › forged success from the vendor's page is rejected by the origin rule (567ms)
  ✓   5 src/journeys.spec.ts:25:1 › explicit successful consent — the full journey, Bearer placement (567ms)
  ✓   6 src/journeys.spec.ts:77:1 › explicit successful consent — named-header placement reaches the API destination (642ms)
  ✓   7 src/journeys.spec.ts:122:1 › blocked opening — the REAL popup blocker returns `blocked` for the gesture's second popup, with no navigation and no retry (576ms)
  ✓   8 src/journeys.spec.ts:150:1 › denial — distinct outcome, keyboard-completable popup with managed focus (536ms)
  ✓   9 src/journeys.spec.ts:184:1 › cancellation — closing the popup mid-journey acknowledges the cancel and resolves `cancelled` (867ms)
  ✓  10 src/my-connections.spec.ts:16:1 › disconnect through the real My Connections page — the next delegated call answers connection_required (1.5s)
  10 passed (13.1s)
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
ℹ duration_ms 36.332899
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
```

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
```

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

Per-change "Done when" evidence: one result file per change in `01_spend_controls/results/`, with the review and its dispositions in `gate-iterate.md`.

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
```

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

Per-change "Done when" evidence: one result file per change in `02_network_egress/results/`, with the review and its dispositions in `gate-iterate.md`.

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
```

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

Per-change "Done when" evidence: one result file per change in `03_csp_and_headers/results/`, with the review and its dispositions in `gate-iterate.md`.

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
```

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

Per-change "Done when" evidence: one result file per change in `04_domain_split/results/`, with the review and its dispositions in `gate-iterate.md`.

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
