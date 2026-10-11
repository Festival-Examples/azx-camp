# IT-8: proxied-response path, origin handling, report sink, smoke guard

Fixes from `review-03-csp-and-headers.md`. Docs come in IT-9.

| Finding | Change |
| --- | --- |
| R-1 | `makeSameOriginCheck` (`apps/edge/src/auth/validate.ts`) now also refuses a `Service-Worker` header and `Sec-Fetch-Dest` values `worker`, `sharedworker` and `serviceworker`. The check guards only the three gateway handlers (`app.ts`, lines 274, 302 and 317), not assets, so an app's own Web Workers still load. A request made from inside a worker has `Sec-Fetch-Dest: empty` and still passes. The edge gateway sets `content-security-policy: default-src 'none'` on every proxied response, after copying headers. `service-worker-allowed` and `alt-svc` (G-3) join `RESPONSE_HEADER_BLOCKLIST`, which now has 20 names; the docblock was rewritten. The `app.ts` comment on the platform worker's `Service-Worker-Allowed` is now accurate. |
| R-3, G-1 | `csp.ts` splits origin handling: `connect-src` keeps `https:` and `wss:`, and `img-src` keeps `https:` only. Wildcard hosts and hostnames outside `[a-z0-9.-]` (for example a `;`) are dropped. `parseImgSrcExtra` uses the same hostname rule and refuses `wss://`. |
| S-1 | `CspReportInsertThrottle` (`apps/edge/src/serving/cspReportThrottle.ts`) allows at most 100 `csp_reports` inserts per app per 10 minutes, using the edge's in-memory counter store, so the cap is per replica (like `DenialThrottle`). The counter keeps counting past the cap with `helix.outcome` set to `recorded`, `dropped` or `failed` (`CSP_REPORT_OUTCOMES`). The portal Violations query covers the last 30 days (`CSP_VIOLATIONS_LOOKBACK_DAYS`). |
| S-2 | The smoke check uses a real 1x1 GIF served by `smoke-public` (`.claude/skills/run-helix/fixtures/pixel.gif`) as `smoke-csp`'s cross-origin image. It requires a captured `/_csp-report` POST with `disposition="enforce"` and compares `lastSeen` against the navigation start. The grant step reloads and asserts the image now loads (`naturalWidth === 1`), and removes the grant in a `finally`. The header check reads the image mode from the environment. If the second browser fails to launch, the first is closed. |
| S-4 | `parseImgSrcExtra` moved so it no longer splits the `EDGE_TRUST_PROXY` docblock; the "every every" typo is fixed. |
| G-2 (part) | `main.bicep` has a `fail()` for `imgSrcReportOnly` and `imgSrcAllowAll` both true. |

Not changed: the dev gateway's `checkOrigin` is always true (by design), so it does not refuse worker loads. Its responses are on the dev gateway's own origin, not an app origin, so a localhost page cannot register a worker from them; the `default-src 'none'` backstop applies there too. G-2's strict parsing of non-boolean values was not done: the repo's "allow polarity" convention (`=== "true"`) is used for every such flag.

## Evidence (coordinator)

- **Byte-identity, rerun:** CT-2's `csp.ts` (`836673e`) against the new measurement builders, for three `https` origin cases: identical.
- **Bicep:** the both-true `fail()` message is in the compiled template. A minimal parameter file's `build-params` failure was inconclusive, because required parameters were missing too; `fail()` fires at deploy time, unverified in Azure.
- **Gate:** `./check-and-lint.sh`, 241 of 241 test files, 3569 tests. `just infra build` passes.
- **Real-browser smoke:** 37 passed, 0 failed, 0 skipped. "enforced CSP blocks remote image and records violation for smoke-csp: 2 report(s); disposition="enforce"", and the granted origin loads the image after the grant.
- **Connections lane:** 10 passed. No leftover `tsx watch` processes.
- **Tests:**
  - 403s for the worker destinations and the `Service-Worker` header; `empty` still allowed.
  - Strip tests for the two new headers on three layers; the backstop CSP.
  - `wss:` in `connect-src` but not `img-src` in all three modes; a `;` hostname dropped; `wss://` refused in `EDGE_IMG_SRC_EXTRA`.
  - The three outcomes.
  - A 31-day-old row excluded from the Violations API.

## Executor

cursor-agent, `composer-2.5`, 129 tool calls.
