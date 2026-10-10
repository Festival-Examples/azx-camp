# CT-7 result: split mode in a real browser, locally

**Result: done.** With `HELIX_APPS_DOMAIN` set, the smoke runner gains a `split` group, and the connections lane runs with the opener on the apps domain.

## The answer: are `helix-apps.localhost` and `local.helix.azxlabs.io` different sites?

**Yes, in Chromium 156** (`Chrome/156.0.8078.4`, headless, in the dev container). The evidence is a page-initiated navigation from an app page to `auth.<control>/health`:

| Pair | Handoff (recorded) | `/_api/me` | Sibling app | App → control |
| --- | --- | --- | --- | --- |
| `helix-apps.localhost` + `local.helix.azxlabs.io` | `none` | `same-origin` | `same-site` | **`cross-site`** |
| `apps.local.helix.azxlabs.io` + `local.helix.azxlabs.io` (same-site pair) | `none` | `same-origin` | `same-site` | **`same-site`** |

The same probe reports `same-site` for the same-site pair, so it discriminates; the `.localhost` result is not an artifact. The raw records are `ct7-sec-fetch-site-localhost-pair.json` and `ct7-sec-fetch-site-same-site-pair.json`. The handoff value is recorded, not asserted. It arrives through a redirect chain that crosses the dev IdP (`http://localhost:<port>`), so it is cross-site in either pair, and a login the browser starts reports `none`.

**Coordinator correction.** The agent's version recorded `none` for the sibling and app-to-control probes, accepted `none` in its assertions, and concluded that the hypothesis was "not confirmed". Those probes used CDP `Page.navigate`, a browser-initiated navigation that always reports `none`, so they measured nothing. A `fetch()` probe from the app page would be blocked by the app CSP (`connect-src 'self'`) before it is sent. The probes are now page-initiated (`location.assign` from the app page), and the assertions require `same-site` for the sibling and `cross-site` (or `same-site` in the fallback pair) for app to control.

## Split-mode checks (`split` group)

- **HTTP login across domains:** app → `auth.<control>/start` → dev IdP → `auth.<control>/callback` → `<slug>.<apps>/_auth/complete` → page. Each `Location` is asserted against its expected origin. Login journeys use `smoke-internal`, because public apps do not sign in.
- **Browser login** lands on `https://smoke-internal.helix-apps.localhost:9080/`.
- **Cookie scope:**
  - Positive control: an app-set `Domain=<apps>` cookie reaches a sibling app.
  - In the `.localhost` pair, no probe cookie and no `__Host-session` reach `auth.<control>`.
  - In the same-site pair, the negative control holds: a `Domain=<control>` cookie set from the app host reaches `auth.<control>`. That is why a delegated apps subdomain needs a Public Suffix List entry (CT-10 documents it).
- **Silent refresh** with a short `EDGE_SESSION_REFRESH_MS`: the `auth.<control>/start?silent=1` chain completes back on the app page.
- **Single-domain mode** runs none of this and passes unchanged.

## Other changes

- `scripts/stack-env.mjs` sets `EDGE_OIDC_ISSUER` and `PORTAL_OIDC_ISSUER` to `http://localhost:<idp port>` for port-offset stacks, in both modes. Before this, an offset stack's edge pointed at the container default (`:3002`), so its `/start` could not run discovery. Single-domain smoke never exercised it. This was found in CT-5's boot check.
- The connections lane reads `HELIX_APPS_DOMAIN`. `world.ts` builds the split topology: `APP_PUBLIC_BASE`, `CONTROL_PUBLIC_BASE`, the edge config domains and the TLS SANs. `playwright.config.ts` adds the apps domain to `--host-resolver-rules`. The README is updated.
- **The consent popup in split mode runs in the connections lane, not the smoke runner.** The smoke runner has no consent-popup driver, so the design's sentence "the smoke runner completes a connections consent popup" is met in the lane, with the opener on the apps domain and the popup and callback on the control domain.
- The compose caveat ("split mode is not a working login stack") is removed: it works now.

## Evidence (coordinator)

- **Gate:** `./check-and-lint.sh`, 241 of 241 test files, 3648 tests.
- **Smoke with a real browser:**
  - single-domain: 37 of 37, 0 skipped;
  - full split (`helix-apps.localhost`): 46 of 46, 0 skipped;
  - `--only split` in the `.localhost` pair: 13 of 13;
  - `--only split` in the same-site pair: 13 of 13.
- **Connections lane:**
  - single-domain: 10 of 10;
  - split: 10 of 10, twice. The agent saw one flaky zip failure on its first split run; it did not recur.
- **No SKIPs** in any counted run (`ct7-gate.txt`).

## Not verified

Firefox (ETP), Safari (ITP, and its `*.localhost` handling), a real Public Suffix List entry or delegated zone, production certificates, and Azure. Only one browser engine was measured.

## Executor

cursor-agent, `composer-2.5`, 106 tool calls. The coordinator rewrote the Sec-Fetch-Site probes and assertions.
