# Context: where the work landed

## Repository and remote

- Code: `projects/helix`, remote `git@github.com:lancekrogers/helix.git` (private).
- Festival and design records: the camp repo `/Users/lancerogers/campaigns/azx` (local commits; its private remote `lancekrogers/azx-camp` has not been pushed since the festival began).
- Pre-festival base: `792557a` (merge of PR #1, the justfile change).
- Tip of the stack: `ca0afd1` (branch `hardening/04-domain-split`).

## State of the private remote now

**output_specs/logs/remote-state.txt**

```text
$ git ls-remote --heads origin main "hardening/*"
c41a69c146ce88f5f71d6c4fc6a3bb8ed2460310	refs/heads/hardening/01-spend-controls
149ac5a44e89730caa756ff25a7fea86712df4c0	refs/heads/hardening/02-network-egress
e1e071e38232478d377c55075f88109c03743df9	refs/heads/hardening/03-csp-and-headers
ca0afd1ce96fe2781426ea0ad9a82881dc2ade27	refs/heads/hardening/04-domain-split
792557ae32aa3fd22d672552fcfb497b98652b1d	refs/heads/main

$ gh pr list -R lancekrogers/helix --state all --json number,state,reviewDecision,headRefName,headRefOid,baseRefName,title --jq '.[] | "#\(.number) [\(.state)] review=\(.reviewDecision) \(.headRefName)@\(.headRefOid[0:7]) -> \(.baseRefName) | \(.title)"'
#5 [OPEN] review=APPROVED hardening/04-domain-split@ca0afd1 -> hardening/03-csp-and-headers | Hardening 4/4: control/apps domain split
#4 [OPEN] review=APPROVED hardening/03-csp-and-headers@e1e071e -> hardening/02-network-egress | Hardening 3/4: CSP and proxied-response headers
#3 [OPEN] review=CHANGES_REQUESTED hardening/02-network-egress@149ac5a -> hardening/01-spend-controls | Hardening 2/4: network egress controls
#2 [OPEN] review=CHANGES_REQUESTED hardening/01-spend-controls@c41a69c -> main | Hardening 1/4: LLM spend controls
#1 [MERGED] review= chore/justfile@11b4f14 -> main | Add modular justfile and disable automatic CI/CD

$ gh api repos/lancekrogers/helix/pulls/2/reviews --jq '.[] | "PR #2 review: \(.submitted_at) \(.user.login) \(.state) commit_id=\(.commit_id[0:7])"'
PR #2 review: 2026-10-10T23:12:00Z obey-agent CHANGES_REQUESTED commit_id=ecdc5b3

$ gh api repos/lancekrogers/helix/pulls/3/reviews --jq '.[] | "PR #3 review: \(.submitted_at) \(.user.login) \(.state) commit_id=\(.commit_id[0:7])"'
PR #3 review: 2026-10-10T23:12:01Z obey-agent CHANGES_REQUESTED commit_id=74b1484

$ gh api repos/lancekrogers/helix/pulls/4/reviews --jq '.[] | "PR #4 review: \(.submitted_at) \(.user.login) \(.state) commit_id=\(.commit_id[0:7])"'
PR #4 review: 2026-10-10T23:12:02Z obey-agent APPROVED commit_id=e1e071e

$ gh api repos/lancekrogers/helix/pulls/5/reviews --jq '.[] | "PR #5 review: \(.submitted_at) \(.user.login) \(.state) commit_id=\(.commit_id[0:7])"'
PR #5 review: 2026-10-10T23:12:03Z obey-agent APPROVED commit_id=ca0afd1

$ for c in c41a69c 955af5e 149ac5a e1e071e ca0afd1; do TZ=UTC git log -1 --date=format-local:%FT%TZ --format='%h committed %cd' $c; done
c41a69c committed 2026-10-10T23:55:11Z
955af5e committed 2026-10-11T00:02:06Z
149ac5a committed 2026-10-11T00:19:53Z
e1e071e committed 2026-10-11T00:22:22Z
ca0afd1 committed 2026-10-11T00:27:12Z

$ for t in e1e071e ca0afd1; do git merge-base --is-ancestor c41a69c $t && echo "c41a69c (the fix for the PR #2 review findings) is an ancestor of $t"; done
c41a69c (the fix for the PR #2 review findings) is an ancestor of e1e071e
c41a69c (the fix for the PR #2 review findings) is an ancestor of ca0afd1

$ gh api repos/lancekrogers/helix --jq '{visibility, default_branch}'
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
c41a69c [azx:8817364a-FE-HH0001-PH-001-SQ-01] Review fix (PR #2): LLM call deadline governs both hops, timeouts after dispatch are charged as a cut, reasoning cap matches the request builder

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
955af5e [azx:8817364a-FE-HH0001-PH-001-SQ-02] Merge hardening/01-spend-controls (PR #2 review fix) into network egress; the llm dispatcher keeps the extra SSRF block list
149ac5a [azx:8817364a-FE-HH0001-PH-001-SQ-02] Review fix (PR #3): the probe reports whether a deny was proven, net-verify exits 3 when none was, port checks no longer count, detached-NSG simulation scenario

$ git log --oneline --reverse origin/hardening/02-network-egress..origin/hardening/03-csp-and-headers
04bfd6b [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-1: strip policy and reporting headers from proxied responses
836673e [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-2: Report-Only tightened CSP, EDGE_IMG_SRC_EXTRA, and the CSP report counter
19f4ca7 [azx:8817364a-FE-HH0001-PH-001-SQ-03] CT-3: enforce tightened img-src and object-src, add EDGE_IMG_SRC_ALLOW_ALL and the EDGE_IMG_SRC_REPORT_ONLY measurement mode
1b0eef3 [azx:8817364a-FE-HH0001-PH-001-SQ-03] Iterate IT-8: refuse worker loads on the gateway, default-src none on proxied responses, keep wss origins, cap CSP report inserts, harden the smoke check
6cc3753 [azx:8817364a-FE-HH0001-PH-001-SQ-03] Iterate IT-9: image-policy hold-off as step 0, origin audit query, proxied-response and report-sink docs, residual channels
e1e071e [azx:8817364a-FE-HH0001-PH-001-SQ-03] Merge hardening/02-network-egress (PR #2 and PR #3 review fixes) into CSP and headers

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
ca0afd1 [azx:8817364a-FE-HH0001-PH-001-SQ-04] Merge hardening/03-csp-and-headers (PR #2 and PR #3 review fixes) into domain split

$ git rev-list --count 792557a..origin/hardening/04-domain-split
50

$ git rev-list --count --merges 792557a..origin/hardening/04-domain-split
3
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

## Review on the pull requests

An automated reviewer (`obey-agent`) reviewed all four PRs on 2026-10-10 at 23:12 UTC. It approved #4 and #5 with no issues, and requested changes on #2 (two charging bugs) and #3 (a green probe did not prove the NSG). Each finding was checked against the code and fixed on the PR's own branch, then merged forward so the stack stays consistent:

```text
   ecdc5b3..c41a69c  hardening/01-spend-controls      review fix for PR #2
   74b1484..955af5e  hardening/02-network-egress      merge of 01 (the llm dispatcher keeps the extra SSRF block list)
   955af5e..149ac5a  hardening/02-network-egress      review fix for PR #3
   6cc3753..e1e071e  hardening/03-csp-and-headers     merge of 02
   97b3fe1..ca0afd1  hardening/04-domain-split        merge of 03
```

The fix records are `01_spend_controls/results/pr2-review-fixes.md` and `02_network_egress/results/pr3-review-fixes.md`. #2 and #3 still show changes requested until the reviewer looks at the new commits. GitHub's API attributes the approvals on #4 and #5 to the current heads, `e1e071e` and `ca0afd1` (`commit_id` in the block above). That cannot be what the reviewer read. Both commits contain `c41a69c`, which was written to fix the findings in the review of #2, and that review was submitted two and three seconds before the two approvals. So the approvals cover those branches as they stood at `6cc3753` and `97b3fe1`, and the reviewer has not seen the fix content on any of the four branches. GitHub still reports #4 and #5 as approved. No re-review has been requested; that is left to the owner.

So today: 50 commits are on the private remote (34 planned changes, 11 sequence-review fix batches, 2 PR-review fixes and 3 merge commits), on four stacked branches, in four open, ready-for-review PRs (#2 to #5). **They are not merged into `main`.** Merging is the owner's step. Merging in order with merge commits keeps the original commit objects.

## Commits per change

**git log --oneline 792557a..origin/hardening/04-domain-split | wc -l (includes 3 merge commits)**

```text
50
```

**change IDs present (one commit each), from the commit subjects**

```text
SP: 1 2 3 4 5 6 7 8 9 10 11 12 13 
EG: 1 2 3 4 5 6 7 8 9 10 11 
CT: 1 2 3 4 5 6 7 8 9 10 
IT: 1 2 3 4 5 6 7 8 9 10 11
```

## Build provenance

- All checks ran in the project's dev container (compose project `helix`: Node 24, Postgres 18, Azurite). CI is off in this fork by the owner's decision, so `./check-and-lint.sh` in the dev container is the gate.
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

Overall ████████████████████ 100% (54/54 tasks)

Time Tracking
────────────────────────────────────────────────────────────
Work time 7h 2m (agent runtime)
Duration 1 day (ongoing) (calendar time)

Time by Phase Type
  implementation   7h 2m

Content Delta
  Initial 19.6 KB (~5009 tokens)
  Current 1054.5 KB (~269961 tokens)
  Delta +1035.0 KB (~+264951 tokens)

Phases
────────────────────────────────────────────────────────────
✓ 001_IMPLEMENT 100% (54/54 tasks) | 7h 2m
```

`PHASE_GOAL.md`'s checkboxes are unchanged. `fest` has no command that ticks them (`fest task`, `fest progress` and `fest workflow` do not edit that file), and the campaign's rule is not to hand-edit fest-managed state. The completion record is the fest state above: all 50 sequence tasks, plus this gate's steps as they are approved.
