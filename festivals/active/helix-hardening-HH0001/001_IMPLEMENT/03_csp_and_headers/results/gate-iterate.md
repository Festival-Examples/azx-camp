# Iterate gate: sequence 03 (CSP and headers)

All findings from the testing gate (`gate-testing.md`) and the code review (`review-03-csp-and-headers.md`) are fixed, recorded, or deferred with a reason. The fixes landed in two batches, each verified by the coordinator before commit: IT-8 (code, tests, smoke runner) and IT-9 (rollout notes and docs). The testing gate found no failures; the review's verdict was "not ready", with three critical findings.

| Finding | Disposition | Where |
| --- | --- | --- |
| R-1 proxied responses: no CSP, `Service-Worker-Allowed` relayed, worker loads not refused (pre-existing) | Fixed: the gateway refuses worker, shared-worker and service-worker destinations and `Service-Worker` requests; `default-src 'none'` on proxied responses; `service-worker-allowed` stripped; docs | IT-8, IT-9 |
| R-2 `updates.md` enforces before the hold-off; an environment-variable hold-off is undone by a full apply | Fixed: step 0 in the parameter file, cross-references from "Roll the apps" and spend steps 3 and 6, enforce by parameter change | IT-9 |
| R-3 `wss:` origins dropped from `connect-src` | Fixed: `connect-src` keeps `https:` and `wss:`, `img-src` keeps `https:`; audit query in the rollout; the decisions.md byte-identity claim corrected (`https` origins only) | IT-8, IT-9 |
| S-1 report sink unbounded | Fixed: per-app insert cap (100 per 10 minutes, per replica), `helix.outcome` on the counter, 30-day Violations window, documented exposure. Retention job deferred (`TODO.md`) | IT-8, IT-9 |
| S-2 smoke check could pass with enforcement broken | Fixed: real cross-origin image, required report POST, `lastSeen` check, grant proven by image load, `finally` cleanup | IT-8 |
| S-3 docs versus code (five places) | Fixed | IT-9 |
| S-4 `config.ts` docblock placement and typo | Fixed | IT-8 |
| G-1 `;` in an approved hostname reaches the CSP | Fixed: strict hostname rule in `originSources` and `parseImgSrcExtra` | IT-8 |
| G-2 strict parsing of non-boolean flag values; Bicep both-true | Bicep `fail()` added (deploy-time, unverified in Azure). Strict parsing not done: the repo uses `=== "true"` for every allow-polarity flag | IT-8 |
| G-3 `alt-svc` relayed | Fixed: on the blocklist | IT-8 |
| G-4 `img-src` spike alert; `disposition` column on `csp_reports` | Deferred (`TODO.md` for the alert; the column needs a migration) | Follow-up |
| Carried: Firefox and Safari behavior, WebRTC and DNS hints, Azure env pass-through | Unverified, labeled in docs | — |

## Final state

`main` at `6cc3753`.
- IT-8 passed the full gate (3569 tests) and `just infra build`. The real-browser smoke passed 37 of 37, with the remote image blocked, `disposition="enforce"`, and the grant proven by the image loading. The connections lane passed 10 of 10. The measurement mode is byte-identical to CT-2 for `https` origins.
- IT-9 passed the full gate and `just infra build`. The audit query was validated on the dev database and on sample values.
