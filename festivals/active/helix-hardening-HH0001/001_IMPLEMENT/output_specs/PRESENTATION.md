# Phase 001_IMPLEMENT: summary and decisions for the owner

## Result

All 34 planned changes are implemented, reviewed and on the private remote: SP-1 to SP-13, EG-1 to EG-11 and CT-1 to CT-10. With them are 11 fix batches from the sequence reviews (IT-1 to IT-11), 2 fixes from pull-request review, and 3 merge commits that carry those fixes up the stack: 50 commits in total. They sit in four open, ready-for-review pull requests, stacked in order:

| PR | Sequence | Commits | Branch tip | Review state |
| --- | --- | --- | --- | --- |
| #2 | 01 spend controls | 19 | `c41a69c` | changes requested, fixed, awaiting re-review |
| #3 | 02 network egress | 15 | `149ac5a` | changes requested, fixed, awaiting re-review |
| #4 | 03 CSP and headers | 6 | `e1e071e` | approved before the last merge commit |
| #5 | 04 domain split | 10 | `ca0afd1` | approved before the last merge commit |

**They are not merged into `main` yet.** `PHASE_GOAL.md` words each required outcome as "merged on the private remote". The commits were on the remote's `main` until the owner asked for pull requests on 2026-10-10; `main` was then moved back to `792557a` so the PRs could be real. Merging #2 to #5 is the owner's step. See `context.md`.

## What was built

- **Spend controls.** A client hang-up aborts the vendor call. Cut and failed calls are charged for what was used. Unset budgets get an install default. There is a platform-wide daily ceiling, and per-app and per-user concurrency caps that hold across replicas.
- **Network egress.** The SSRF block list covers Azure's platform address and the special-purpose ranges, tested against the IANA registries. An NSG sits on the egress subnet. Firewall installs can opt into an FQDN allow-list. A probe job with alerts reports the posture, and a local simulation tests the rule table.
- **CSP and headers.** Proxied responses cannot set policy or reporting headers, or be loaded as a worker or a document. The tight image policy is enforced, with a measurement mode for existing installs.
- **Domain split.** Hosted apps can be served from their own domain while sign-in, the portal and the dev gateway stay on the control domain. It is a per-install setting; the default is the single-domain layout.

`requirements.md` maps every required deliverable in the four `SEQUENCE_GOAL.md` files to its commits and result records, and says where a result differs from the goal's wording.

## How it was checked

Each change was written by an executor agent, then verified by the coordinator before commit: the full gate, smoke for service changes, and a reading of the diff. Each sequence then had a testing gate, an independent read-only review, and fix batches for the findings. The OIDC handoff change had a dedicated review pass with revert checks. Raw output is in `requirements.md` and `constraints.md`.

The final verification ran at the tip of the stack, `ca0afd1`, and passed first time: the full gate (243 test files, 3704 tests), the real-browser smoke in single-domain mode (37 of 37) and in both split modes (47 of 47 each), the connections lane in both modes (10 of 10 each), and the network simulation (8 of 8 scenarios).

The reviews found real defects, all fixed:

- Sequence 01: the rollout order would have taken down LLM calls; one tenant could trip the shared ceiling.
- Sequence 02: the default NSG would have blocked edge-to-egress on every install (ILB backend ports); a rule denied an address Microsoft says must not be denied; pinned installs would have cut egress off from its own Key Vault secrets.
- Sequence 03: a pre-existing path let an app register a service worker through the fetch proxy and reach the login handoff token; approved `wss:` origins were dropped.
- Sequence 04: the template could not prepare the apps domain's certificate before moving apps; fixed with a separate cutover flag and a staged rollout with a rollback.
- PR #2 review: the 10-minute call deadline never applied, because both network hops timed out at 2 minutes and such a call was charged nothing; the estimate for a cut reasoning-model call was capped too low.
- PR #3 review: a passing probe did not prove the NSG was attached. The probe now reports whether a deny was proven, and the operator recipe exits 3 when none was.

The executor's PR #2 fix also went beyond the findings in three places (charging a full output budget when nothing was relayed, charging connect timeouts, a 12-minute connect timeout). The coordinator reverted those; `01_spend_controls/results/pr2-review-fixes.md` lists them.

## Decisions for the owner

1. **Merge the pull requests.** #2, then #3, #4, #5, each with a merge commit (not squash or rebase) so the original commits are kept. Deleting each branch after merging retargets the next PR to `main`.
2. **Re-review before merging?** The reviewer has not seen the fix commits on #2 and #3. Its approvals on #4 and #5 were given at 23:12 UTC on 2026-10-10, before the merge commits that brought those fixes into #4 and #5. No re-review has been requested and no reply has been posted on the review threads.
3. **A charge floor for silent reasoning calls?** A reasoning-model call that produces no bytes before its deadline or a hop timeout is charged its input estimate only, though the vendor may bill reasoning tokens. Charging a floor on deadline and timeout cuts (not on client hang-ups, which would reopen the abuse path the sequence 01 review closed) is a possible follow-up.
4. **ADR for the portal's control origin?** `CONTROL_PUBLIC_BASE` replaced the earlier "derived, never configured" rule. It is recorded in the ADR-0028 amendment and the feature docs; whether it deserves its own ADR is open (`04_domain_split/results/gate-iterate.md`).
5. **Egress and the platform Key Vault.** The egress identity holds Key Vault Secrets User on all of kv-platform, and the network layer cannot stop an egress compromise from reading it. Narrowing the grant (per-secret assignments or a separate egress vault) is deferred in `TODO.md`. It is a design gap worth raising with whoever runs the installs.
6. **Push the camp repo?** The festival and design records are committed locally; `lancekrogers/azx-camp` has not been pushed since the festival began.

## Limits

- **Nothing was applied to Azure or to a live install.** Azure-only behavior is labeled unverified in Azure (56 mentions across 23 files), and each rollout section lists the operator's checks.
- **Browser evidence is Chromium only**, in the dev container. Safari and Firefox tracking protection on real domains, and a real Public Suffix List entry, are untested.
- **On an install without pinned private-endpoint addresses, the probe cannot prove the NSG is attached** in the default mode. It says so (`denyProven: false`) and `just infra net-verify` exits 3, instead of reporting success.
- **`PHASE_GOAL.md` checkboxes are unchanged.** `fest` has no command that ticks them, and the campaign rule is not to hand-edit fest-managed state. `fest progress` (in `context.md`) is the completion record.
- **Intermittent test failures.** Several tests failed intermittently during the phase and passed on rerun (`constraints.md`, standard 1). Three are in files the phase did not change or only touched in fixtures. One is in tests this phase added (`usage.rls.integration.test.ts`): it was reworked in IT-5, failed once more during IT-11, and its cause was not established.

## Deferred follow-ups

Recorded in `workflow/design/helix-spend-containment-egress/plan.md` and each sequence's `gate-iterate.md`:
- the kv-platform grant;
- feeding deploy-time private-endpoint addresses into the NSG, so an unpinned install can prove its deny rules;
- whether an `AzurePlatformIMDS` service-tag deny is safe on the Container Apps subnet;
- a retention job and a spike alert for CSP reports, and a `disposition` column;
- the dev-container image lacks the browser-lane dependencies (`xauth` and the lane's Chromium build were installed by hand);
- the portal does not show the install-default budget;
- simulation fidelity gaps;
- the intermittent tests above.
