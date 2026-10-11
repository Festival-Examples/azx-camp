# Execution plan

_Step:_ PLAN. _Scope:_ the three decided designs, [01-spend-controls.md](01-spend-controls.md), [02-app-containment.md](02-app-containment.md), and [03-egress-network-control.md](03-egress-network-control.md), against `projects/helix` (private `lancekrogers/helix`). Decisions are in [decisions.md](decisions.md); review notes in [review.md](review.md).

## What gets built

34 changes in four phases, each change sized for one pull request. The phases follow the agreed order: spend first, then network egress, then the CSP and header tightening, then the domain split last because it touches the login handoff.

| Phase | Changes | Outcome |
| --- | --- | --- |
| 1. Spend controls | SP-1 to SP-13 | A hang-up stops the vendor call at any point; cut and failed streams are charged; unset budgets get an install default; a platform-wide daily ceiling and per-app and per-user concurrency caps hold across edge replicas. |
| 2. Network egress | EG-1 to EG-11 | The SSRF block list covers the missing platform and special-purpose ranges with boundary tests; every install gets NSGs behind the filter; firewall installs can opt into an FQDN allow-list; a probe reports the network posture. |
| 3. CSP and headers | CT-1 to CT-3 | Proxied responses cannot set dangerous headers; the tighter `img-src` and `object-src 'none'` run in Report-Only, then enforced. |
| 4. Domain split | CT-4 to CT-10 | Hosted apps can be served from their own registrable domain while login and the portal stay on the control domain, as a per-install setting, with adversarial tests on the handoff. |

### Phase 1: spend controls

| ID | Change | Depends on |
| --- | --- | --- |
| SP-1 | Characterization test: does a hang-up after the first response byte already tear down the vendor call? | none |
| SP-2 | Propagate the edge's hang-up into the egress upstream call | SP-1 |
| SP-3 | Cut-stream usage estimate in `packages/shared` | none |
| SP-4 | `usage` events from the provider mappers | none |
| SP-5 | Charge cut and failed LLM calls | SP-3, SP-4 |
| SP-6 | Install default for an unset `dollarsPerDay` | none |
| SP-7 | Throttle and count admission denials | SP-6 |
| SP-8 | Platform spend definer function and migration | none |
| SP-9 | Enforce the platform daily ceiling | SP-7, SP-8 |
| SP-10 | Lease store and `inflight_leases` migration | none |
| SP-11 | Concurrency caps and the call deadline in the LLM handler | SP-5, SP-7, SP-10 |
| SP-12 | Optional lease caps on the fetch path | SP-10, SP-11 |
| SP-13 | ADR-0051, remaining docs, and `TODO.md` | SP-11 |

### Phase 2: network egress

| ID | Change | Depends on |
| --- | --- | --- |
| EG-1 | Block-list additions and boundary tests | none |
| EG-2 | Deployment-supplied extra block list | EG-1 |
| EG-3 | Special-purpose registry completeness test | EG-1, EG-2 |
| EG-4 | Fixed private-endpoint addresses for the Key Vaults | none |
| EG-5 | NSG module and subnet attachment | EG-2, EG-4 |
| EG-6 | Firewall platform lists and threat intelligence | EG-5 |
| EG-7 | Firewall allow-list tier and drift tooling | EG-6 |
| EG-8 | Probe entry point | EG-1, EG-5 |
| EG-9 | Probe job, posture output, and alerts | EG-7, EG-8 |
| EG-10 | Local network simulation and `just infra net-verify` | EG-5, EG-8, EG-9 |
| EG-11 | Documentation and ADR amendments | EG-10 |

### Phase 3: CSP and headers

| ID | Change | Depends on |
| --- | --- | --- |
| CT-1 | Extend the proxied-response header blocklist | none |
| CT-2 | Report-Only tightened CSP and the report counter | CT-1 (order only) |
| CT-3 | Enforce the tighter `img-src` and `object-src` | CT-2 |

### Phase 4: domain split

| ID | Change | Depends on |
| --- | --- | --- |
| CT-4 | Second loopback domain in the dev environment | none |
| CT-5 | Edge control/apps domain split, with its adversarial tests | CT-4 |
| CT-6 | Portal control origin | CT-5 |
| CT-7 | Smoke runner in split mode and the connections lane | CT-5, CT-6 |
| CT-8 | Legacy redirect from old app hosts | CT-5 |
| CT-9 | Bicep, DNS, and certbot instances for the apps domain | CT-5, CT-6, and EG-6 when an install runs the firewall |
| CT-10 | Documentation, ADR amendments, and operator rollout notes | CT-5 to CT-9 |

Each change's files, acceptance criteria, and evidence are in the "Work breakdown" section of its design.

## Rules for every change

- **Gate:** `./check-and-lint.sh` (or `just check`) passes in the dev container, where Postgres and Azurite run. CI stays off, so this is the only gate.
- **Running services:** changes to the edge, portal, or egress also pass the smoke runner (`just dev smoke`).
- **Telemetry and tests ship with the change** (`projects/helix/AGENTS.md`): constants in `packages/shared/src/telemetry.ts`, assertions with `startRecordingTelemetry`, rows in `docs/features/observability.md`, and adversarial tests for anything security-relevant. Check new constant names against the ones earlier phases added.
- **Azure:** Bicep is compile-checked with `just infra build`. Anything only Azure can prove is labeled **unverified in Azure** in the change and in the operator rollout notes.
- **Commits:** `fest commit` inside the festival, on a branch per change in the private remote.

## Cross-phase dependencies

- **Certificates and the firewall.** CT-9's second certbot instance needs the ACME, ARM, and DNS hosts that EG-6 adds to the apps subnet's firewall list. On an install that runs the firewall, EG-6 must land first.
- **One ADR-0028 amendment.** EG-11 and CT-10 both amend ADR-0028. The second to land extends the first one's amendment rather than adding another.
- **Edge database surface.** SP-8 and SP-10 widen what `helix_edge` can do (a definer function and a lease table). Both must extend `role-split.integration.test.ts` and record an ADR-0002 amendment.

## Not settled by the plan

These are answered inside a specific change or left to AZX's operators:

- **SP-8:** confirm the production migration owner role in `infra/azure/sql/01-roles.sql` before writing the definer function's policy.
- **Starting values** ($50 per app, $100 per day platform, 10 per app, 3 per user, 10-minute deadline, 3 bytes per token): guesses until real traffic exists; each is a setting or a named constant.
- **CT-7:** whether browsers treat two `.localhost` names as cross-site; if not, the split-domain browser tests fall back to a same-site pair.
- **CT-9, unverified in Azure:** whether one Container App can bind two wildcard domains on different certificates, and whether two certbot instances collide on names.
- **EG-7:** existing firewall installs stay on `any` after a template update; switching to `allowlist` is their operator's call.
- **Added without a decision:** CT-3 adds `EDGE_IMG_SRC_ALLOW_ALL` (default off), the per-install way to put `https:` back in `img-src` for one-org installs. It follows the rule that every stricter behavior has a per-install relaxation.
- **Deferred:** a portal note telling approvers that a new origin needs an operator step on firewall installs, an `ssrf.reason` span attribute, a rate limit on CSP reports, and an NSG on the shared apps subnet.

## Execution vehicle

**Proposed: one festival, `helix-hardening`, with the four phases above.** By the camp's sizing rules this is festival work: four phases, 34 changes, and it will outlive this session. Camp intents fit single changes, not a dependent sequence of this size.

Planning follows the camp's festival rules: create it, then drive `fest next` and answer what it asks, rather than scaffolding every phase and task up front. Each task document points at its change in the design's work breakdown, names the files it touches, and states the failure paths. The design documents stay the source of detail.

Nothing is created until the owner agrees.

## Follow-ups recorded during sequence 01

From the sequence 01 iterate gate (`festivals/active/helix-hardening-HH0001/001_IMPLEMENT/01_spend_controls/results/gate-iterate.md`): the portal does not show the install default for unset budgets (S-14); app creation with `visibility: public` skips the visibility classifier; the dev container cannot run the browser lane without `xauth` and the lane's Playwright build; a duplicated output-token default between `pricing.ts` and `provider.ts`; lock-timeout refusals share the `concurrency_app` reason; model limits in `pricing.ts` unverified against vendor docs; and low-value hardening (`pg_temp`, unused `hour`, partial index, `truncate` location, `retry-after` time zone).

## Follow-ups recorded during sequence 02

- From EG-8 (`festivals/active/helix-hardening-HH0001/001_IMPLEMENT/02_network_egress/results/eg8-probe-entry-point.md`): the EG-5 rule-table notes for `deny-wire-server` and `deny-link-local` were corrected in EG-11, and EG-11's ADR-0005 amendment says the application block list is the only control on WireServer and IMDS. Still open: decide whether an `AzurePlatformIMDS` service-tag deny is safe on the Container Apps subnet; that is unverified, and it could break managed identity.
- From the sequence 02 iterate gate (`festivals/active/helix-hardening-HH0001/001_IMPLEMENT/02_network_egress/results/gate-iterate.md`):
  - Narrow egress's kv-platform grant: per-secret role assignments, or a separate egress-only vault for its three secrets.
  - The `AzurePlatformIMDS` decision.
  - Simulation fidelity: the `Internet` tag, the unpinned endpoint-subnet allow, inbound rows.
  - The registry test's parser should read the real snapshot.
  - `egress-hosts` should report ports.
  - Before turning any of this on, an operator needs the scratch-copy `net-verify` run plus the edge→egress `/health` check.

## Follow-ups recorded during pull-request review

- From the PR #2 fix (`festivals/active/helix-hardening-HH0001/001_IMPLEMENT/01_spend_controls/results/pr2-review-fixes.md`): a reasoning-model call that stays silent until its deadline or a hop timeout is charged its input estimate only. Charging a floor on deadline and timeout cuts, not on client hang-ups, is an owner decision.
- From the PR #3 fix (`festivals/active/helix-hardening-HH0001/001_IMPLEMENT/02_network_egress/results/pr3-review-fixes.md`): feed the private endpoints' assigned addresses into the NSG at deploy time, so an install without pinned addresses can prove its deny rules. Until then `just infra net-verify` exits 3 there.
- From the phase gate: `usage.rls.integration.test.ts` (the platform-sum cases added in sequence 01) failed once during IT-11 after its IT-5 rework. The cause was not established.
