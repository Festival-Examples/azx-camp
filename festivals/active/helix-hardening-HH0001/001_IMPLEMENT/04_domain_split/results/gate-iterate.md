# Iterate gate: sequence 04 (domain split)

All findings from the testing gate (`gate-testing.md`) and the code review (`review-04-domain-split.md`) are fixed, recorded, or deferred with a reason. The fixes landed in two batches, each verified by the coordinator before commit: IT-10 (template, smoke, tests) and IT-11 (rollout notes and docs). The testing gate found no failures; the review's verdict was "not ready", with two critical findings. CT-5's dedicated handoff review is recorded separately in `ct5-review.md`, with its resolutions.

| Finding | Disposition | Where |
| --- | --- | --- |
| R-1 the template could not stage the apps domain before cutover; the existing-install steps were unworkable (found by the coordinator in CT-10 and widened by the reviewer) | Fixed: `hostedAppsLive` separates provisioning (`hostedSplit`) from cutover (`hostedCutover`); the rollout is rewritten as provision, verify on a separate staging install, cut over, sunset, plus a rollback | IT-10, IT-11 |
| R-2 the containment section rolled the edge image before the image hold | Fixed: a section step 0 for all parts; "Roll the apps" points to it | IT-11 |
| S-1 no probe of the apps-domain certificate | Fixed: `edge-health-apps` availability target | IT-10 |
| S-2 the apps zone's name servers were not an output | Fixed: `hostedDnsNameServers` | IT-10 |
| S-3 certificate-name collision between the two domains | Fixed: `fail()` guard | IT-10 |
| S-4 docs versus code (boot rules, callback derivation, TLS-gate order, wording) | Fixed | IT-11 |
| S-5 the providers callback-URL check was missing | Fixed: documented as an operator check | IT-11 |
| S-6 the smoke cookie check could pass with no control request | Fixed | IT-10 |
| G-1 bad domain pairs and case-sensitive comparison in Bicep | Fixed: lowercase and trim, `fail()` guards mirroring the edge | IT-10 |
| G-2 no test for the normalized `/%2F_api/me` refusal | Fixed | IT-10 |
| G-3 the control `*` record is absent on new split installs | Documented as unverified in Azure | IT-11 |
| G-4 no cutover rollback | Fixed: rollback paragraph | IT-11 |
| G-5 leftover split environment in a dev container created with `HELIX_APPS_DOMAIN` | Documented: recreate the container | IT-11 |
| G-6 smoke landing and `/_api/me` checks | Fixed | IT-10 |
| Testing: `usage.rls.integration.test.ts` failed once during IT-11 | Recorded as a rare flake (three isolated reruns and two full gates passed) | Follow-up |
| Owner question: does the configured portal control origin need its own ADR? | Open; currently in the ADR-0028 amendment and the feature docs | Owner |

## Final state

`main` at `97b3fe1`.
- **IT-10:** passed the full gate (3669 tests) and `just infra build`; the split parameter files compile with `hostedAppsLive` false and true; real-browser smoke passed 37 of 37 single-domain and 47 of 47 split; the split lane passed 10 of 10.
- **IT-11:** passed the full gate twice.

The sequence testing gate before the iterate batches passed every check, including the same-site-pair negative control.
