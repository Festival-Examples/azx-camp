# Iterate gate: sequence 02 (network egress)

All findings from the testing gate (`gate-testing.md`) and the code review (`review-02-network-egress.md`, with the coordinator addendum) are fixed, recorded as documented, or deferred with a reason. Fixes landed in two batches on their own branches, each verified by the coordinator before commit: IT-6 (rule table, Bicep, probe, simulation) and IT-7 (rollout notes, docs, parameter files).

The testing gate found no failures. The review's verdict was "not ready", for three critical findings; the coordinator added a fourth (R-4) and promoted one suggestion (G-5 → S-6). The coordinator checked R-1 and R-2 against Microsoft's [Container Apps NSG page](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration), and R-4 and S-6 against the [Manage secrets page](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets).

| Finding | Disposition | Where |
| --- | --- | --- |
| R-1 default NSG blocks edge→egress (ILB backend ports 31080/31443) | Fixed: ports added, `deny-vnet-in` enforce-only, static tests on the inbound rows, outbound-only caveat in docs, inbound row in the ADR-0005 probe table | IT-6, IT-7 |
| R-2 explicit deny on 168.63.129.16 | Fixed: row deleted; docs say `ssrf.ts` is the only control on that address | IT-6, IT-7 |
| R-3 published upgrade path attaches the NSG before the scratch test | Fixed: operator upgrade section with a step 0 hold-off (`egressNsgEnforce = 'off'`), linked from the spend section's step 6; hold-off lines in both parameter files; step 2 rolls the image only | IT-7 |
| R-4 (coordinator) pinned NSG blocks egress's own Key Vault references to kv-platform | Fixed: pinned allow includes kv-platform; the probe treats it as a positive control; kv-platform added to the honest limit | IT-6, IT-7 |
| R-4 residual: egress identity has Secrets User on all of kv-platform | Deferred: per-secret grants or a separate egress-only vault (`TODO.md`) | Follow-up |
| S-1 `deny-cgnat` in the default mode | Fixed: enforce-only | IT-6, IT-7 |
| S-2 daily canary trips the firewall denial alert | Fixed: canary host excluded from the query | IT-6 |
| S-3 unlabeled "safe on upgrade" claims and template mismatches | Fixed | IT-7 |
| S-4 reference parameter files set `allowlist` | Fixed: commented out with a new-installs note | IT-7 |
| S-5 planning decision IDs in the repository | Fixed: none remain | IT-7 |
| S-6 (from G-5) egress firewall list lacks `login.microsoft.com` | Fixed | IT-6 |
| G-1 inbound check for `net-verify` | Fixed in the small form: `net-verify` prints the edge→egress `/health` command and says the probe is outbound-only. Running `az containerapp exec` from the recipe was not attempted (interactive, unverifiable here) | IT-7 |
| G-2 simulation gaps (`Internet` as `0.0.0.0/0` with a blanket accept; the unpinned scenario never exercises the endpoint-subnet allow; no inbound simulation) | Deferred. The inbound rows have static tests (IT-6); the other two are documented limits of the simulation | Follow-up |
| G-3 registry test's CSV parser never reads the real snapshot | Recorded: the EG-3 claim that "a layout guard fails loudly if the CSV format changes" overstates it; the coverage assertions are sound. Committing the CSVs or dropping the parser is follow-up | Follow-up |
| G-4 `egress-hosts` drops ports; platform-covered hosts show as MISSING | Deferred | Follow-up |
| G-6 VNet prefix outside 10.0.0.0/16 | Fixed (doc) | IT-7 |
| G-7 garbled sentence | Fixed | IT-7 |
| G-7 misspelled `privateEndpointAddresses` keys | Fixed: `@sealed()` type; a misspelled key fails parameter validation (verified with BCP089) | IT-6 |
| G-7 firewall denial rule deploys on the infra-only first apply | Not changed: harmless (no action group yet), noted | — |
| Carried: EG-8 `AzurePlatformIMDS` decision | Deferred, now in `TODO.md` | IT-7 |
| Carried: Azure-only behaviors (EG-4, EG-5, EG-6, EG-7, EG-9, EG-10) | Unverified in Azure, listed in the feature page and the ADR-0005 probe table | — |

## Final state

`main` at `74b1484`. IT-6 passed:
- the full gate (241 of 241 test files);
- `just infra build` and the translator tests (21 of 21);
- a negative parameter test;
- `just infra net-sim` on the host, all 7 scenarios, with `kv-platform-443` reachable and `blob-pe-443` blocked under `enforce`.

IT-7 passed the full gate (docs build and format) and `just infra build`. ADR-0005's lines 1-89 are unchanged from the sequence start.
