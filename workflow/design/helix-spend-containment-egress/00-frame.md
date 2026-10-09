# Frame: three problems, confirmed against the code

_Repository:_ `projects/helix` at `main` = `792557a` (2026-10-08). _Source:_ [workflow/explore/helix-repo-exploration/findings.md](../../explore/helix-repo-exploration/findings.md), blockers 5, 6, 7, and 10. Every anchor below was re-opened for this step.

## Problem 1: AI spend escapes the budget

**What happens today.**

1. The edge refuses a new LLM call only when the app has a daily budget and is already over it. With no `dollarsPerDay` set there is no check at all (`apps/edge/src/gateway/llm.ts:186-216`, `if (cap !== undefined)` at line 188). The comment states the rule: "An in-flight request is never cut" (line 185), which is ADR-0021's block-new design.
2. When the app hangs up, the edge does notice. It listens on the response's `close`, aborts its own call to egress, and marks the span (`llm.ts:232-243`).
3. Egress never learns about it. LLM calls and fetch calls both go through egress `POST /proxy` (`apps/edge/src/gateway/egressProvider.ts:87`). Egress calls the upstream with `request(target.href, { method, headers, body, dispatcher })` and no `signal` (`apps/egress/src/proxy.ts:606-611`), and no egress source file listens for `close` on the inbound request or response. The vendor call runs to completion and the vendor bills for it. `TODO.md:58` records the same gap.
4. The ledger records a cut stream at $0. The cost is computed from `finalUsage` (`llm.ts:268`), which is filled only from the provider's final `done` event (`llm.ts:342`). A hang-up throws first, so `recordOnce("error", { errorDetail: CLIENT_DISCONNECTED })` writes zero tokens (`llm.ts:356-358`).
5. The token counts exist before the end. The Anthropic stream parser reads input tokens at `message_start` and the running output count at each `message_delta` (`apps/edge/src/gateway/provider.ts:113-136`), but only hands them to the handler inside `done`.

**Also in scope** (from SEC-4 and OPS-14): budgets are optional, per app, and checked only before a call starts; there is no per-user cap, no concurrency cap, and no platform-wide ceiling.

**Effect.** An app that opens streams and drops them spends vendor money that never reaches the ledger, so the spend gate never moves. The cost comes from the vendor's bill, not from Helix's accounting.

**Correction from the REVIEW step.** Point 3 overstates the gap. Once the upstream response headers arrive, egress streams the body through `capBody`, which joins the upstream body and the cap with `pipeline(source, cap)` and tears down in both directions (`packages/shared/src/bodyCap.ts`, the `pipeline` call at line 85). When the edge hangs up, Fastify destroys the response stream, and the upstream body is destroyed with it. So a hang-up after the first byte probably already stops the vendor call (Hypothesis until the characterization test in 01-spend-controls.md runs). What is confirmed: before the headers arrive there is no abort path at all, and the ledger records any cut stream at $0. The input tokens are billed by the vendor either way.

## Problem 2: hosted apps are not fully contained

**Shared registrable domain.** The edge serves apps at `<slug>.<baseDomain>` from one `EDGE_BASE_DOMAIN` setting (`apps/edge/src/config.ts:115-116, 745`). The Bicep puts the login host at `auth.<appsDomain>` and the portal at `portal.<appsDomain>` under the same `appsDomain` (`infra/azure/main.bicep:55, 886-902`). ADR-0019 records the gap as issue #16 and proposes a separate registrable domain for apps (`docs/adr/0019-subdomain-per-app-isolation.md:25-31`). ADR-0028 later made the deployment model single-tenant and customer-deployed, which turned #16 into a per-install choice; the reference deployment still keeps the shared domain.

**Open CSP channels.** Every app response gets `img-src https: data: blob:`, script from `'self' 'unsafe-inline' 'unsafe-eval'` plus five public CDNs, and `form-action 'self'` (`apps/edge/src/serving/csp.ts:23-29, 63-77`). `connect-src` is limited to approved origins. The module's own comment says "Open HTTPS images and navigation remain possible data-exfiltration channels" (`csp.ts:10-11`).

**Effect.** Session theft between apps is closed by per-app hosts and `__Host-` cookies. What remains is cookie-bomb denial of service and lookalike phishing against the login and portal hosts, and an app sending out anything its signed-in viewer can read, through an image URL or a navigation.

## Problem 3: no network-level egress control

- **No NSGs.** No `Microsoft.Network/networkSecurityGroups` resource exists anywhere under `infra/azure` (grep returns nothing).
- **The firewall allows every hostname.** The egress subnet's rule is `targetFqdns: ['*']` on HTTPS (`infra/azure/modules/firewall.bicep:100-108`), and threat intelligence is `Alert`, not `Deny` (`firewall.bicep:84`).
- **The live installs run without it.** The template defaults `deployFirewall = true` (`infra/azure/main.bicep:372`, `main.bicepparam:47`), but ADR-0005 records that both production installs run with `deployFirewall = false`, a cost decision, with the details in the operator's private deployments repo (`docs/adr/0005-*.md:79-87`).
- **Only the application filter controls destinations.** `apps/egress/src/ssrf.ts` resolves, checks every address against a block list (`ssrf.ts:42-52` for IPv4, line 120 for IPv6 ULA, mapped forms from line 135), and pins the socket. The list has no entry for Azure's platform address `168.63.129.16`. Whether that address is reachable from the egress container, and what it exposes there, is not yet checked (Hypothesis, SEC-7).

**Effect.** If the SSRF filter has a gap, nothing behind it stops the egress container, which holds every connection secret, from reaching internal or platform addresses.

## Constraints every design must respect

- **Repository rules** (`projects/helix/AGENTS.md`): the edge stays dependency-minimal with hand-written SQL; a change that adds a seam adds its telemetry in the same change, with names in `packages/shared/src/telemetry.ts`, tests via `startRecordingTelemetry`, and the inventory in `docs/features/observability.md`; egress span attributes are a hardcoded allowlist and egress spans record no exception; no whole URLs in telemetry; auth changes ship with adversarial tests; `./check-and-lint.sh` must pass in the dev container.
- **ADR-0021:** the `gateway_calls` ledger is append-only and quotas block the next request, not the one in flight. A design that cuts streams in flight changes this decision and needs an ADR amendment.
- **ADR-0019 and ADR-0028:** one subdomain per app with host-only `__Host-` cookies; one independent install per customer, on the customer's own domain and identity provider. A domain split must be a per-install setting, not a single hard-coded layout.
- **ADR-0005:** resolve, validate, and pin in egress; the firewall is the reference posture's "primary" control, and the live installs have an accepted exception.
- **ADR-0009 and ADR-0035:** the CSP is shared by every app and by the platform's offline worker; `'unsafe-inline'` stays because the fetch shim and offline registration are inlined.
- **ADR-0037:** OTLP-only telemetry boundary, inert by default.
- **Rollout:** the two live installs' parameters live in a private deployments repo this fork does not have. Any change to their domain or network needs that access or a hand-off to their operator.
- **No CI gate:** automatic CI is off, so each change must be proven with `./check-and-lint.sh` in the dev container.

## Decisions only the owner can make

1. **Audience.** One trusted organization per install, or outside app authors whose apps may be hostile? This sets how far problem 2 must go and whether a platform-wide spend ceiling is required or optional.
2. **Live installs.** Will the fix be rolled out to the two existing installs (which needs the deployments repo and Azure access), or only to new installs from this fork?
3. **Network cost.** The live installs turned the firewall off for cost. Is a cheaper control acceptable (NSGs plus a tightened SSRF list), or is a real FQDN allow-list worth the firewall's running cost?
4. **Cut-stream charging.** When a stream is cut, charge the tokens counted so far, charge a conservative estimate, or both?
5. **App compatibility.** Tightening `img-src` and script sources will break some generated apps that load images or scripts from arbitrary hosts. How much breakage is acceptable, and is a per-app approval path for extra origins enough?
6. **Domain.** If apps move to their own registrable domain, which domain does each install use, and who owns its DNS?
