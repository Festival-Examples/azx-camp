---
fest_type: festival
fest_id: HH0001
fest_name: helix-hardening
fest_status: planning
fest_created: 2026-10-08T19:45:32.304864-06:00
fest_tracking: true
---

# helix-hardening

**Status:** Planned | **Created:** 2026-10-08T19:45:32-06:00

## Festival Objective

**Primary Goal:** Close the AI spend leak, add network egress control behind the SSRF filter, tighten the hosted-app CSP, and let hosted apps run on their own domain, as decided in workflow/design/helix-spend-containment-egress

**Vision:** A Helix install where an abandoned or hostile AI call cannot spend money the ledger does not see, where the egress plane cannot reach internal or platform addresses even if its SSRF filter has a bug, and where a hosted app cannot read or send out more than its design allows. Every stricter behavior is a per-install setting with a safe default, so installs on AZX's documented one-org model can relax it. All of it is proven in the dev container; anything only Azure can prove is labeled unverified in Azure.

## Success Criteria

### Functional Success

- [ ] A client hang-up at any point stops the egress upstream call (LLM and fetch), and every cut or failed LLM call writes a ledger row with measured or estimated cost (SP-1 to SP-5)
- [ ] Unset budgets get an install default, a platform-wide daily ceiling is enforced, and per-app and per-user concurrency caps hold across edge replicas (SP-6 to SP-13)
- [ ] The SSRF block list covers the missing platform and special-purpose ranges; every install gets NSGs; firewall installs can opt into an FQDN allow-list; a probe reports the posture (EG-1 to EG-11)
- [ ] Proxied responses cannot set dangerous headers, and the tighter `img-src` plus `object-src 'none'` run in Report-Only and then enforced (CT-1 to CT-3)
- [ ] Hosted apps can be served from their own registrable domain while auth and the portal stay on the control domain, as a per-install setting (CT-4 to CT-10)

<!-- Add more functional outcomes as needed -->

### Quality Success

- [ ] `./check-and-lint.sh` passes with zero failures in the dev container after every task
- [ ] Every change to a running service passes the smoke runner (`just dev smoke`)
- [ ] Every security-relevant change ships adversarial tests, and every new seam ships its telemetry with a test (`projects/helix/AGENTS.md`)
- [ ] Every Azure-only claim is labeled unverified in Azure in the code comments, docs, and operator rollout notes

<!-- Add more quality criteria as needed -->

## Progress Tracking

### Phase Completion

- [ ] 001_IMPLEMENT: four sequences, spend controls, network egress, CSP and headers, domain split, in that order

<!-- Add phases as they're created -->

## Complete When

- [ ] All phases completed
- [ ] Operator rollout notes exist for each design, and the ADR amendments listed in the designs are written

<!-- Add more completion criteria as needed -->