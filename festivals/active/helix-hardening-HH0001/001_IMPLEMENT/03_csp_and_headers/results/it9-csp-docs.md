# IT-9: rollout notes and docs

Doc and parameter-file fixes from `review-03-csp-and-headers.md`, written against the IT-8 code.

| Finding | Change |
| --- | --- |
| R-2 | `apps/docs/src/deploy/updates.md`, "Upgrading to the tightened image policy", is rewritten as steps 0 to 3. Step 0 holds `imgSrcReportOnly = true` in the parameter file before rolling the edge image or any full apply, and says a hand-set environment variable is overwritten by the next full apply. "Roll the apps" and spend steps 3 and 6 link to step 0. Step 3 enforces by changing a parameter (apply or a scoped `az containerapp update --set-env-vars`), not by rolling an image. Both parameter files carry the hold-off wording. |
| R-3 | Step 1 is a read-only audit query that lists approved origins dropping out of the CSP (not `https:` or `wss:`, or a wildcard host), plus a note on unusual hostnames. |
| S-3 | `EDGE_IMG_SRC_EXTRA` is described per mode in `configuration.md` and the edge README. "Request URLs to permitted CDN hosts (Hypothesis)" is added to every residual-channel list (`SECURITY.md`, ADR-0009, architecture, `edge-serving.md`, the `csp.ts` module comment). `SKILL.md` states the schemes kept per directive and the proxy's worker refusal and `default-src 'none'`, and the service-worker sentence now covers the bundle and the proxy. |
| R-1 docs | `SECURITY.md`, ADR-0009 and `fetch-proxy.md` state the proxied-response CSP, the worker refusal and the stripped `Service-Worker-Allowed`. The blocklist description adds `service-worker-allowed` and `alt-svc`. |
| S-1 docs | Observability: `helix.edge.csp_reports` gains `helix.outcome`. `edge-serving.md`: the per-app cap constants, the 30-day Violations window, and that a blocked URI can carry data admins then see. `TODO.md` defers a `csp_reports` retention job and the `img-src` spike alert. |

## Evidence (coordinator)

- The audit query runs read-only on the dev database (0 rows: no approved origins there). Run over sample values, it flags `http://`, the wildcard host and `ws://`, and passes `https://`, `wss://` and uppercase `HTTPS://` (`it9-gate.txt`).
- `./check-and-lint.sh`: 241 of 241 test files (docs build and format). `just infra build` passes.
- No plan change IDs in the edited docs.

## Executor

cursor-agent, `composer-2.5`, 65 tool calls.
