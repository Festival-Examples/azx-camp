# Phase 001_IMPLEMENT: summary and decisions for the owner

## Result

All 34 planned changes are implemented, reviewed and on the private remote: SP-1 to SP-13, EG-1 to EG-11 and CT-1 to CT-10, plus 11 review-fix batches (IT-1 to IT-11), 45 commits in total. They sit in four open, ready-for-review pull requests, stacked in order:

| PR | Sequence | Commits |
| --- | --- | --- |
| #2 | 01 spend controls | 18 |
| #3 | 02 network egress | 13 |
| #4 | 03 CSP and headers | 5 |
| #5 | 04 domain split | 9 |

**They are not merged into `main` yet.** `PHASE_GOAL.md` words each required outcome as "merged on the private remote". The commits were on the remote's `main` until the owner asked for pull requests on 2026-10-10; `main` was then moved back to `792557a` so the PRs could be real. Merging #2 to #5 is the owner's step. See `context.md`.

## What was built

- **Spend controls.** A client hang-up aborts the vendor call. Cut and failed calls are charged for what was used. Unset budgets get an install default. There is a platform-wide daily ceiling, and per-app and per-user concurrency caps that hold across replicas.
- **Network egress.** The SSRF block list covers Azure's platform address and the special-purpose ranges, tested against the IANA registries. An NSG sits on the egress subnet. Firewall installs can opt into an FQDN allow-list. A probe job with alerts reports the posture, and a local simulation tests the rule table.
- **CSP and headers.** Proxied responses cannot set policy or reporting headers, or be loaded as a worker or a document. The tight image policy is enforced, with a measurement mode for existing installs.
- **Domain split.** Hosted apps can be served from their own domain while sign-in, the portal and the dev gateway stay on the control domain. It is a per-install setting; the default is the single-domain layout.

## How it was checked

Each change was written by an executor agent, then verified by the coordinator before commit: the full gate, smoke for service changes, and a reading of the diff. Each sequence then had a testing gate, an independent read-only review, and fix batches for the findings. The OIDC handoff change had a dedicated review pass with revert checks. Raw output is in `requirements.md` and `constraints.md`.

The reviews found real defects, all fixed before each sequence closed:

- Sequence 01: the rollout order would have taken down LLM calls; one tenant could trip the shared ceiling.
- Sequence 02: the default NSG would have blocked edge-to-egress on every install (ILB backend ports); a rule denied an address Microsoft says must not be denied; pinned installs would have cut egress off from its own Key Vault secrets.
- Sequence 03: a pre-existing path let an app register a service worker through the fetch proxy and reach the login handoff token; approved `wss:` origins were dropped.
- Sequence 04: the template could not prepare the apps domain's certificate before moving apps; fixed with a separate cutover flag and a staged rollout with a rollback.

## Decisions for the owner

1. **Merge the pull requests.** #2, then #3, #4, #5, each with a merge commit (not squash or rebase) so the original commits are kept. Deleting each branch after merging retargets the next PR to `main`.
2. **ADR for the portal's control origin?** `CONTROL_PUBLIC_BASE` replaced the earlier "derived, never configured" rule. It is recorded in the ADR-0028 amendment and the feature docs; whether it deserves its own ADR is open (`04_domain_split/results/gate-iterate.md`).
3. **Egress and the platform Key Vault.** The egress identity holds Key Vault Secrets User on all of kv-platform, and the network layer cannot stop an egress compromise from reading it. Narrowing the grant (per-secret assignments or a separate egress vault) is deferred in `TODO.md`. It is a design gap worth raising with whoever runs the installs.
4. **Push the camp repo?** The festival and design records are committed locally; `lancekrogers/azx-camp` has not been pushed since the festival began.

## Limits

- **Nothing was applied to Azure or to a live install.** Azure-only behavior is labeled unverified in Azure (54 mentions across 23 files), and each rollout section lists the operator's checks.
- **Browser evidence is Chromium only**, in the dev container. Safari and Firefox tracking protection on real domains, and a real Public Suffix List entry, are untested.
- **`PHASE_GOAL.md` checkboxes are unchanged.** `fest` has no command that ticks them, and the campaign rule is not to hand-edit fest-managed state. `fest progress` (in `context.md`) is the completion record.
- **Four flaky tests** were seen during the phase, none touched by it; each passed on rerun (`constraints.md`, standard 1). The final verification's first full-gate run hit one of them.

## Deferred follow-ups

Recorded in `workflow/design/helix-spend-containment-egress/plan.md` and each sequence's `gate-iterate.md`:
- the kv-platform grant;
- whether an `AzurePlatformIMDS` service-tag deny is safe on the Container Apps subnet;
- a retention job and a spike alert for CSP reports, and a `disposition` column;
- the dev-container image lacks the browser-lane dependencies (`xauth` and the lane's Chromium build were installed by hand);
- the portal does not show the install-default budget;
- simulation fidelity gaps;
- the flaky tests above.
