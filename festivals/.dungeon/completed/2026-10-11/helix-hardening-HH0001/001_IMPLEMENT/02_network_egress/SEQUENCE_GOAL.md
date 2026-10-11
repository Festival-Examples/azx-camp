---
fest_type: sequence
fest_id: 02_network_egress
fest_name: network egress
fest_parent: 001_IMPLEMENT
fest_order: 2
fest_status: completed
fest_created: 2026-10-08T20:22:03.992025-06:00
fest_updated: 2026-10-10T05:01:02.980996-06:00
fest_tracking: true
---


# Sequence Goal: 02_network_egress

**Sequence:** 02_network_egress | **Phase:** 001_IMPLEMENT | **Status:** Pending | **Created:** 2026-10-08T20:22:03-06:00

## Sequence Objective

**Primary Goal:** Put network-level control behind the egress SSRF filter, delivered as 11 reviewable changes (EG-1 to EG-11 in `workflow/design/helix-spend-containment-egress/03-egress-network-control.md`): a block list that covers the missing platform and special-purpose ranges, an NSG on `snet-egress` on every install, an opt-in FQDN allow-list for installs that run the firewall, and a probe that reports the network posture.

**Contribution to Phase Goal:** The phase goal lists "02_network_egress: EG-1 to EG-11 merged, each meeting its Done when in 03-egress-network-control.md". This sequence delivers that outcome. It is second in the order (spend first, then egress, then CSP, then the domain split), and its firewall platform lists are a precondition for the second certbot instance in `04_domain_split` on installs that run the firewall.

## Success Criteria

The sequence goal is achieved when:

### Required Deliverables

- [ ] **Complete block list**: `168.63.129.16/32`, the three IPv4 documentation ranges, `192.88.99.0/24`, `3fff::/20`, `5f00::/16` and the IPv4-translated IPv6 form are blocked, each with first, last and outside-neighbor boundary tests and all embedded spellings; a dated snapshot of the IANA IPv4 and IPv6 special-purpose registries is checked against the list by a test that names every exception.
- [ ] **Deployment-supplied extra block list**: `EGRESS_EXTRA_BLOCKED_CIDRS` is parsed once at boot, refuses to start on a malformed value, is an explicit parameter of every function that blocks an address, and is bypassed by `allowPrivate` like the built-in list (which still refuses to boot in production).
- [ ] **NSG on `snet-egress` on every install**: one rule table (`infra/azure/nsg-egress-rules.json`) read by both `infra/azure/modules/nsg.bicep` and the local simulation, fixed private-endpoint addresses for the three vaults and Blob, `egressNsgEnforce` (`off`, `deny-list-only`, `enforce`) and `egressAllowedPorts` as per-install settings, and `EGRESS_EXTRA_BLOCKED_CIDRS` set on the egress app from the VNet prefix.
- [ ] **Firewall tiers**: per-subnet platform host lists with the missing apps-subnet hosts added, threat intelligence `Deny` as a parameter, `egressFqdnMode` (`any` or `allowlist`) with `egressAllowedFqdns`, firewall logs in Log Analytics with an alert on application-rule denials from the egress subnet, and `just infra egress-hosts` to show the operator what the allow-list is missing.
- [ ] **Posture probe**: `apps/egress/src/netprobe.ts` (Node built-ins only) classifies each destination as blocked, reachable or unresolved and exits non-zero on a surprise; a daily and on-demand `<prefix>-netprobe` job in the egress environment with a role-less identity; a `netControls` output of `main.bicep`; alerts on probe failure and on no recent success.
- [ ] **Local proof**: `just infra net-sim` applies the rule table as `iptables` filters in Docker networks that mirror the subnets, passes the `off`, `deny-list-only` and `enforce` columns, and fails on deliberately broken tables; `just infra net-verify` is the operator recipe for the real install.
- [ ] **Records**: the ADR-0005 amendment, the ADR-0028 line in the shared amendment, the ADR-0046 note, the corrected "no outbound internet route" statements, `docs/features/network-controls.md` with the operator rollout notes, and the rewritten verification section in `infra/azure/README.md`.

### Quality Standards

- [ ] **Gate**: `./check-and-lint.sh` passes in the dev container before every commit; `just dev smoke` passes for every change to egress or portal code (EG-1, EG-2, EG-3, EG-7, EG-8); `just infra build` passes for every Bicep change (EG-4 to EG-7, EG-9, EG-10). `just infra build` is the only Azure check available.
- [ ] **Azure honesty**: NSG and firewall behavior cannot be checked here (decision V4). Everything only Azure can prove is labeled unverified in Azure in module headers, parameter text, docs and the rollout notes, and listed in the ADR-0005 probe-results table as "not yet run on a real install".
- [ ] **Where each proof runs**: the vitest suites and `node --test infra/netsim` run in the dev container; `just infra net-sim` needs a Docker daemon, which the dev container does not have, so it runs on a host with Docker. Evidence from each is saved under `results/`.
- [ ] **Telemetry ships with the seam**: layers 2 to 4 add no span or metric; the probe's two log events (`egress.netprobe_check`, `egress.netprobe_result`) are asserted in `netprobe.test.ts`, listed in `docs/design/logging.md`, and read by the two probe alerts; the firewall-denial and probe alerts are listed in `docs/features/observability.md`. No whole URL, secret or personal identifier appears in any probe line.
- [ ] **Stricter behavior is per install**: every new control has a strict default and a relaxation (`EGRESS_EXTRA_BLOCKED_CIDRS` empty, `egressNsgEnforce = off` or `deny-list-only`, `egressFqdnMode = any`, `deployNetprobe = false`). Existing firewall installs stay on `egressFqdnMode = any` after a template update.
- [ ] **No live-install change**: nothing here is applied to Azure or to the two live installs; their adoption steps are operator rollout notes.

### Completion Criteria

- [ ] All tasks in sequence completed successfully
- [ ] Quality verification tasks passed
- [ ] Code review completed and issues addressed (the SSRF filter change and the NSG rule order get a careful read: a wrong priority silently cuts DNS or Postgres)
- [ ] Documentation updated

## Task Alignment

> **Note:** Task files define HOW. Each task maps to one change in the design's "Work breakdown" section.

| Task | Task Objective | Contribution to Sequence Goal |
|------|----------------|-------------------------------|
| 01_eg1_block_list_additions_and_boundary_tests.md | Block `168.63.129.16`, the IPv4 documentation and 6to4-relay ranges, two IPv6 ranges and the IPv4-translated form, with boundary tests and an end-to-end refusal (EG-1). | Closes the known gaps in the only layer that knows the app's intent; the cheapest change and the base the others test against. |
| 02_eg2_deployment_supplied_extra_block_list.md | Add `EGRESS_EXTRA_BLOCKED_CIDRS`, parsed at boot and passed as an explicit parameter to every blocking function (EG-2). | Covers a VNet outside RFC 1918 and gives every install a per-install knob, with a boot refusal on a bad value. |
| 03_eg3_special_purpose_registry_completeness_test.md | Test the block list against a dated snapshot of the IANA special-purpose registries, with an explicit exceptions list (EG-3). | Keeps the list complete over time: a missing range now fails a test instead of waiting for a review. |
| 04_eg4_fixed_private_endpoint_addresses.md | Give the vault and Blob private endpoints fixed, overridable addresses and lift the subnet constants into `main.bicep` (EG-4). | Lets the NSG name the two vaults egress needs instead of the whole endpoint subnet. |
| 05_eg5_nsg_module_and_subnet_attachment.md | Add the NSG module, the shared rule table, the `egressNsgEnforce` modes and the extra-CIDR wiring on the egress app (EG-5). | Layer 2: removes the largest reach of an SSRF bug, VNet-local targets the firewall never sees, with the firewall off. |
| 06_eg6_firewall_platform_lists_and_threat_intel.md | Make threat intelligence `Deny` a parameter, split the platform host list per subnet and add the missing apps-subnet hosts (EG-6). | Makes the firewall tier usable for the platform's own dependencies and unblocks certificate issuance in `04_domain_split` on firewall installs. |
| 07_eg7_firewall_allow_list_tier_and_drift_tooling.md | Add `egressFqdnMode` and `egressAllowedFqdns`, firewall logs with a denial alert, and `just infra egress-hosts` (EG-7). | Layer 3: an allow-list instead of `*` for installs that choose it, with the drift tooling that keeps the manual step visible. |
| 08_eg8_probe_entry_point.md | Write `apps/egress/src/netprobe.ts`, a built-ins-only probe that classifies blocked, reachable and unresolved and exits non-zero on a surprise (EG-8). | The code half of layer 4, run both by the Azure job and by the local simulation. |
| 09_eg9_probe_job_posture_output_and_alerts.md | Run the probe as a scheduled, on-demand job in the egress environment, publish `netControls`, and alert on failure and on absence (EG-9). | Turns the probe into evidence an install can show: declared posture, last result, and an alarm when either is missing. |
| 10_eg10_local_network_simulation_and_net_verify.md | Simulate the rule table with Docker networks and `iptables`, and add the `net-verify` operator recipe (EG-10). | The only local proof of rule order and logic, with deliberate-break scenarios; the operator step that settles the Azure hypotheses. |
| 11_eg11_docs_and_adr_amendments.md | Write the ADR-0005, ADR-0028 and ADR-0046 amendments, fix the "no outbound internet route" statements, add the feature page and rollout notes, and rewrite the verification section (EG-11). | Leaves the decisions, the honest limits, the unverified rows and the upgrade steps on record for operators of existing installs. |

## Dependencies

### Prerequisites (from other sequences)

- None. Every task here can start without another sequence. One soft link: `01_spend_controls` (task `13_sp13_adr_and_docs.md`) writes the first ADR-0028 amendment, and `11_eg11_docs_and_adr_amendments.md` extends it instead of adding a second; if it has not landed, `11_eg11` creates the section with the same heading so the spend and domain-split tasks extend it. This sequence adds no telemetry constant to `packages/shared/src/telemetry.ts`, so it has nothing to collide with from `01_spend_controls`.

### Provides (to other sequences)

- **Firewall platform host additions** (Graph, the ACME server host, Azure Resource Manager, the Key Vault service tag, `login.microsoft.com`, from `06_eg6`): used by `04_domain_split` (CT-9), whose second certbot instance needs them on any install that runs the firewall.
- **The ADR-0028 amendment** (one section, network lines added by `11_eg11`): used by `04_domain_split` (CT-10), which extends the same section.
- **The `main.bicep` pattern for subnet constants, per-install parameters and the `netControls` output**: reused by `04_domain_split` for its Bicep and DNS parameters.

## Working Directory

Target project: `projects/helix` (relative to campaign root)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| An NSG rule that is missing a required Container Apps flow leaves a revision unable to start or failing health probes, or an NSG cannot be attached to a populated subnet at all. | Med | High | `egressNsgEnforce` starts at `deny-list-only`, the probe runs before `enforce`, `off` rolls the attachment back; scratch-copy test first (decision N1); fallback of recreating the egress environment is in the rollout notes. Labeled unverified in Azure. |
| The NSG blocks DNS, so every target fails to resolve. | Med | High | The DNS allow (130) is numbered below the wire-server deny (200); the probe has a DNS positive control; `net-sim` has a `break-dns` scenario that must fail. |
| A required allow rule is too narrow and a vendor on a non-standard port breaks. | Med | Med | `egressAllowedPorts` is a parameter; the failure shows as a connect timeout and a 502 class error; rollout note step 3 lists live manifests first. |
| The firewall allow-list is missing a host and the drop is silent at the app. | Med | Med | Firewall-denial alert, `just infra egress-hosts` drift command, existing firewall installs stay on `any`, and the mode is per install. |
| The probe job cannot start or its schedule is disabled, which produces no failure line at all. | Low | Med | The alert fires on no recent success, not only on failure. |
| A probe false negative hides an open path (a reset read as a block). | Low | High | Only a connect timeout counts as `blocked`; a refusal or reset is `reachable`; an unexpected error is a fourth value that never matches. A firewall that drops after the TCP handshake is probed with a TLS handshake (a hypothesis). |
| Changing the SSRF function signatures leaves a test fixture on `undefined` because the fixtures cast the config object and typecheck cannot see the gap. | Med | Med | `02_eg2` lists every fixture and call site and ends with a grep check. |
| The design and the code differ in places this plan found: the exchange and provider clients never build a connector, the apps environment is external so its static IP is public, the dev container has no Docker, and the egress image pulls from GHCR. | High | Low | Each task records the difference in `results/` and follows the code. |
| Fixed private-endpoint addresses collide with the addresses Azure already assigned on an existing install, or the endpoint update disrupts the vaults for a moment. | Med | Med | `privateEndpointAddresses` overrides each address; rollout note step 4 reads the current addresses first; labeled unverified in Azure. |
| An operator moves to `enforce` and approved origins on ports other than 80 and 443 stop working. | Med | Low | Stated in the parameter text, the docs and rollout note step 3; the strict value is the default for new installs only. |

## Progress Tracking

### Milestones

- [ ] **Milestone 1**: Application layer landed (01_eg1 to 03_eg3): the block list is complete, the per-install extra list works, and the registry test guards it.
- [ ] **Milestone 2**: Subnet and firewall layers landed (04_eg4 to 07_eg7): fixed endpoint addresses, the NSG on `snet-egress`, the firewall platform lists and the allow-list tier with its drift tooling, all compile-checked.
- [ ] **Milestone 3**: Verification and records landed (08_eg8 to 11_eg11): the probe, its job, outputs and alerts, the local simulation passing positive and negative scenarios, and the documentation with the ADR amendments.

## Quality Gates

### Testing and Verification

- [ ] All unit tests pass
- [ ] Integration tests complete (Postgres and Azurite, in the dev container; the `egress-hosts` database test is one of them)
- [ ] Performance benchmarks met: not applicable. The probe's cost is a handful of bounded connects per day; the simulation's positive and negative scenario output is recorded in `results/`.

### Code Review

- [ ] Code review conducted
- [ ] Review feedback addressed
- [ ] Standards compliance verified

### Iteration Decision

- [ ] Need another iteration? Decided at the iterate gate
- [ ] If yes, new tasks created: None until the iterate gate decides