# Context: where the work landed

## Repository and remote

- Code: `projects/helix`, remote `git@github.com:lancekrogers/helix.git` (private).
- Festival and design records: the camp repo `/Users/lancerogers/campaigns/azx` (local commits; its private remote `lancekrogers/azx-camp` has not been pushed since the festival began).
- Pre-festival base: `792557a` (merge of PR #1, the justfile change).
- Last festival commit: `97b3fe1`.

## State of the private remote now

**output_specs/logs/remote-state.txt**

```text
$ git ls-remote --heads origin main "hardening/*"
ecdc5b37f4eb338b1b5bcc2a43bf3484546a62d6	refs/heads/hardening/01-spend-controls
74b148451194896a6731ec8c8fb6ddd6da34b10e	refs/heads/hardening/02-network-egress
6cc37531551ec1616e1b6fc07856af4c0845fa71	refs/heads/hardening/03-csp-and-headers
97b3fe1fc4e1a4c641614818f0c4f7a6b6ff01f4	refs/heads/hardening/04-domain-split
792557ae32aa3fd22d672552fcfb497b98652b1d	refs/heads/main

$ gh pr list -R lancekrogers/helix --state all
#5 [OPEN] Hardening 4/4: control/apps domain split | hardening/04-domain-split -> hardening/03-csp-and-headers | https://github.com/lancekrogers/helix/pull/5
#4 [OPEN] Hardening 3/4: CSP and proxied-response headers | hardening/03-csp-and-headers -> hardening/02-network-egress | https://github.com/lancekrogers/helix/pull/4
#3 [OPEN] Hardening 2/4: network egress controls | hardening/02-network-egress -> hardening/01-spend-controls | https://github.com/lancekrogers/helix/pull/3
#2 [OPEN] Hardening 1/4: LLM spend controls | hardening/01-spend-controls -> main | https://github.com/lancekrogers/helix/pull/2
#1 [MERGED] Add modular justfile and disable automatic CI/CD | chore/justfile -> main | https://github.com/lancekrogers/helix/pull/1

$ gh api repos/lancekrogers/helix --jq "{visibility, default_branch}"
{"default_branch":"main","visibility":"private"}

$ git log --oneline --reverse 792557a..origin/hardening/01-spend-controls
dc287c7 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-1: characterize egress behavior on a hang-up after the first byte
62c4059 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-2: abort the egress upstream call when the edge hangs up
e9b00b7 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-3: add the cut-stream usage estimate
26cb797 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-4: yield usage events from the provider mappers
f1b43a2 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-5: charge cut and failed LLM calls
57b8b7d [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-6: enforce an install default for an unset LLM budget
494776b [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-7: throttle and count LLM admission denials
98e7b82 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-8: add the platform LLM spend definer function
3e82db5 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-9: enforce the platform daily LLM ceiling
b793f94 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-10: add the in-flight lease store and table
f5c315d [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-11: cap concurrent LLM calls and add a call deadline
df397a2 [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-12: add an optional per-app lease cap on the fetch path
8bb294f [azx:8817364a-FE-HH0001-PH-001-SQ-01] SP-13: add ADR-0051, operator rollout notes, and spend-control docs
48f86da [azx:8817364a-FE-HH0001-PH-001-SQ-01] Iterate IT-1: fix rollout order, add lease-table startup check, abort calls before shutdown deadline
a4423eb [azx:8817364a-FE-HH0001-PH-001-SQ-01] Iterate IT-2: bound cut-call charges by model limits and raise the default platform ceiling
52ab612 [azx:8817364a-FE-HH0001-PH-001-SQ-01] Iterate IT-3: classify new LLM grants and app-creation capabilities, keep create response compatible
be1e6aa [azx:8817364a-FE-HH0001-PH-001-SQ-01] Iterate IT-4: close hang-up windows, fix egress hang-up telemetry, bound lease lock waits
ecdc5b3 [azx:8817364a-FE-HH0001-PH-001-SQ-01] Iterate IT-5: make spend-control tests prove their behavior, declare the visibilityGroupIds default

$ git log --oneline --reverse origin/hardening/01-spend-controls..origin/hardening/02-network-egress
00e626e [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-1: block Azure platform and special-purpose ranges in the SSRF filter
d6043ff [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-2: add a deployment-supplied extra SSRF block list
d819e8e [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-3: test the SSRF block list against the IANA special-purpose registries
7528396 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-4: add opt-in fixed private-endpoint addresses
edbadc2 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-5: add the egress subnet NSG from a shared rule table, deny-list-only by default
daab135 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-6: split firewall platform lists per subnet and default threat intel to Deny
4b6bcc6 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-7: add the firewall allow-list tier, denial alert, and egress-hosts drift check
a8ca07a [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-8: network probe entry point for egress; host-node checks informational (NSGs do not filter them)
e78b716 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-9: scheduled network probe job, netControls output and probe alerts
03a9d23 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-10: local network simulation and net-verify recipe
96e54b3 [azx:8817364a-FE-HH0001-PH-001-SQ-02] EG-11: network egress docs, ADR amendments and rollout notes
0f4e5de [azx:8817364a-FE-HH0001-PH-001-SQ-02] Iterate IT-6: open the ILB backend ports, drop the 168.63.129.16 deny, allow egress's own Key Vault, keep the CGNAT deny out of the default mode
74b1484 [azx:8817364a-FE-HH0001-PH-001-SQ-02] Iterate IT-7: network upgrade section with NSG hold-off, outbound-only probe caveat, kv-platform limit, corrected docs and parameter files

$ git log --oneline --reverse origin/hardening/02-network-egress..origin/hardening/03-csp-and-headers
04bfd6b [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-1: strip policy and reporting headers from proxied responses
836673e [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-2: Report-Only tightened CSP, EDGE_IMG_SRC_EXTRA, and the CSP report counter
19f4ca7 [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_ONLY measurement mode
1b0eef3 [azx:8817364a-FE-HH0001-PH-001-SQ-03] Iterate IT-8: refuse worker loads on the gateway, default-src none on proxied responses, keep wss origins, cap CSP report inserts, harden the smoke check
6cc3753 [azx:8817364a-FE-HH0001-PH-001-SQ-03] Iterate IT-9: image-policy hold-off as step 0, origin audit query, proxied-response and report-sink docs, residual channels

$ git log --oneline --reverse origin/hardening/03-csp-and-headers..origin/hardening/04-domain-split
44b4744 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-4: second loopback dev domain (HELIX_APPS_DOMAIN)
1aa32c8 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-5: edge control/apps domain split with adversarial tests
715a772 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-6: portal control origin (CONTROL_PUBLIC_BASE) for the vendor callback URL
7902a6e [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-7: split-mode smoke (cross-domain login, Sec-Fetch-Site, cookie scope, silent refresh) and split connections lane
c3f75df [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-8: legacy app-host redirect (EDGE_LEGACY_APP_REDIRECT) with the sunset counter
f7ef250 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-9: Bicep, DNS and certbot for a separate hosted-apps domain (default off)
5c56761 [azx:8817364a-FE-HH0001-PH-001-SQ-04] CT-10: domain-split docs, ADR-0028/0019/0044 amendments and hosted-app containment rollout notes
8661102 [azx:8817364a-FE-HH0001-PH-001-SQ-04] Iterate IT-10: hostedAppsLive separates apps-domain provisioning from cutover; domain guards, apps-cert probe, NS output, stricter split smoke
97b3fe1 [azx:8817364a-FE-HH0001-PH-001-SQ-04] Iterate IT-11: provision/verify/cutover rollout with rollback, containment step 0, callback check, docs aligned with the split boot rules
```

## What "merged on the private remote" means today

During the phase, every change was fast-forwarded onto `main` locally after its checks, and `main` was pushed to the private remote at each sequence boundary. The push output recorded in the executing session was:

```text
sequence 02:  ecdc5b3..74b1484  main -> main
sequence 03:  74b1484..6cc3753  main -> main
sequence 04:  6cc3753..97b3fe1  main -> main
```

(Sequence 01 was pushed the same way, ending at `ecdc5b3`. These lines are from the session transcript, not from a saved log.)

On 2026-10-10, after sequence 04 closed, the owner asked for pull requests and chose to rewind `main` and open real PRs. The four sequence branches were pushed first, then `main` was force-pushed with a lease back to `792557a`:

```text
 * [new branch]      ecdc5b3 -> hardening/01-spend-controls
 * [new branch]      74b1484 -> hardening/02-network-egress
 * [new branch]      6cc3753 -> hardening/03-csp-and-headers
 * [new branch]      97b3fe1 -> hardening/04-domain-split
 + 97b3fe1...792557a 792557a -> main (forced update)
```

So today: all 45 commits (34 planned changes and 11 review-fix batches) are on the private remote, on four stacked branches, in four open, ready-for-review PRs (#2 to #5). **They are not merged into `main`.** Merging is the owner's step. Merging in order with merge commits restores `main` with the same commit objects.

## Commits per change

**git log --oneline 792557a..origin/hardening/04-domain-split | wc -l**

```text
45
```

**change IDs present (one commit each), from the commit subjects**

```text
SP: 1 2 3 4 5 6 7 8 9 10 11 12 13 
EG: 1 2 3 4 5 6 7 8 9 10 11 
CT: 1 2 3 4 5 6 7 8 9 10 
IT: 1 2 3 4 5 6 7 8 9 10 11
```

## Build provenance

- All checks ran in the project's dev container (compose project `helix`: Node 24, a Postgres 18 database service, Azurite; the `psql` line below is the client inside the app container). CI is off in this fork by the owner's decision, so `./check-and-lint.sh` in the dev container is the gate.
- The network simulation ran on the macOS host's Docker daemon, because the dev container has no Docker socket.
- No image was built or published, and nothing was applied to Azure or to any live install.

**versions**

```text
node v24.21.0
pnpm 11.5.3
psql (PostgreSQL) 15.19 (Debian 15.19-0+deb12u1)
azure-cli 2.91.0
Bicep CLI version 0.48.1 (cec7951cf6)
```

## Festival state

**output_specs/logs/fest-progress.txt**

```text
$ fest progress
FESTIVAL PROGRESS
─────────────────
Festival helix-hardening-HH0001
────────────────────────────────────────────────────────────

Overall ██████████████████░░ 92% (50/54 tasks)
■ 1 task(s) blocked

Time Tracking
────────────────────────────────────────────────────────────
Work time 7h 2m (agent runtime)
Duration 1 day (ongoing) (calendar time)

Time by Phase Type
  implementation   7h 2m

Content Delta
  Initial 19.6 KB (~5009 tokens)
  Current 937.7 KB (~240046 tokens)
  Delta +918.1 KB (~+235036 tokens)

Phases
────────────────────────────────────────────────────────────
● 001_IMPLEMENT  92% (50/54 tasks) | 7h 2m
```

`PHASE_GOAL.md`'s checkboxes are unchanged. `fest` has no command that ticks them (`fest task`, `fest progress` and `fest workflow` do not edit that file), and the campaign's rule is not to hand-edit fest-managed state. The completion record is the fest state above: 4 of 4 sequences and 50 of 54 tasks, the remaining 4 being this gate's steps.
