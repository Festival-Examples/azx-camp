# Review of the three designs

_Step:_ REVIEW, 2026-10-08. _Reviewer:_ the coordinating session, against `projects/helix` at `main` = `792557a`. The designs were drafted by three Claude Sonnet subagents from one brief.

## Result

All three designs have every required section, and every claim their recommendations depend on matched the code, with one exception that changes the problem statement (the spend leak is narrower than reported). Citation errors were fixed in place. No cross-design conflict was found, but four dependencies need to be respected when the work is sequenced.

## Claims re-opened

**01-spend-controls.md**

- Egress catch branch logs `upstream request failed` at `warn` and replies 502 (`apps/egress/src/proxy.ts:693, 707-716`), so an abort would write to a dead socket today. Matches.
- Egress already marks `ATTR_CLIENT_DISCONNECTED` from `!reply.raw.writableEnded` in its `finally` (`proxy.ts:798`). Matches; no new egress attribute is needed.
- The edge fetch path uses the `reply.raw` `close` plus `writableEnded` pattern the design copies (`apps/edge/src/gateway/fetch.ts:330-341`). Matches.
- **Post-header propagation.** The design says a hang-up after the upstream headers arrive is probably already propagated. `capBody` joins the upstream body and the cap with `pipeline(source, cap, () => {})` (`packages/shared/src/bodyCap.ts:85`), whose comment says teardown is wired both ways, and egress sends the capped stream with `reply.send(cappedBody)` (`proxy.ts:686-692`). The claim is plausible and correctly marked as needing a characterization test first.
- The $50 default equals the approval baseline `BASELINE_DOLLARS_PER_DAY = 50` (`packages/shared/src/approval.ts:206`). Matches.
- `gateway_calls` has `ENABLE` and `FORCE ROW LEVEL SECURITY` with an edge partition policy (`apps/portal/prisma/migrations/20260721033820_rls_gateway_calls_collection_items/migration.sql:37-45`), which is why a cross-app sum needs a definer function. Matches.

**02-app-containment.md**

- `classifyHost(hostHeader, baseDomain)` takes one domain (`apps/edge/src/routing/hosts.ts:20`) and is called with `config.baseDomain` (`apps/edge/src/app.ts:372`). Matches.
- The CSP is set on the service-worker response (`app.ts:791`) and on assets (`apps/edge/src/serving/assets.ts:114`). Matches.
- `RESPONSE_HEADER_BLOCKLIST` is at `packages/shared/src/fetch.ts:110`; the `externalOrigins` classifier treats an added origin as elevated (`packages/shared/src/approval.ts:406-410`). Matches.
- The portal's "Derived, never configured" auth-base comment (`apps/portal/src/deployment.ts:66-68`) and the published CSP block in the agent skill (`packages/deploy-skill/SKILL.md:49`). Matches.

**03-egress-network-control.md**

- Two Container Apps environments, `appsEnv` and `egressEnv` (`infra/azure/main.bicep:752, 765`), on subnets `10.0.2.0/23` and `10.0.4.0/23` (`infra/azure/modules/network.bicep:32-36`). Matches; this corrects the brief's assumption of one shared environment.
- The platform allow-list includes `*.blob.core.windows.net` and `login.microsoftonline.com` (`infra/azure/modules/firewall.bicep:48, 62`). Matches.
- The firewall cost comments (`main.bicep:347-351`, about 920 USD per month for Standard) and the Basic-tier note (`infra/azure/README.md:96-98`). Matches; the design quotes only the repository's own figures.
- `ssrf.ts` has no entry for `168.63.129.16` or the IPv4 documentation ranges (grep returns nothing). Matches.
- The allow-list sources are the fetch-proxy origins (`capabilities.fetch.origins`) and connection-provider hosts, not the browser-side CSP `externalOrigins`. Correct; the two must not be conflated.

## Changes made in this step

| File | Change |
| --- | --- |
| `00-frame.md` | Added a correction to Problem 1: after the first response byte, the hang-up probably already stops the vendor call; the confirmed gaps are the pre-header window and the $0 ledger row. |
| `03-egress-network-control.md` | Six citations said `README.md` but meant `infra/azure/README.md`; fixed. Renamed the proposed recipes to fit the existing `just` modules: `just infra egress-hosts`, `just infra net-verify`. |
| `workflow/explore/helix-repo-exploration/findings.md` | Corrected blocker 7 to match the narrowed spend-leak statement. |
| `workflow/explore/helix-repo-exploration/notes/04-known-problems.md` | Added a coordinator note under KP-2 with the same correction. |

## Cross-design dependencies

1. **Certificates and the firewall.** The containment design adds a second certbot instance for the apps domain. Certbot runs in `appsEnv`, and the egress design notes that the apps subnet's firewall list lacks ACME, ARM, and Graph (Hypothesis). If an install turns the firewall on, those platform hosts must be added before the second certbot instance runs, or certificate issuance fails silently. The containment design also flags a possible name collision when certbot is instantiated twice (Hypothesis).
2. **ADR-0028 is amended by two designs.** Containment adds the control and app domain split; egress adds that the allow-list is per-install configuration. Write one amendment.
3. **New database surface for the edge.** The spend design gives `helix_edge` `EXECUTE` on a `SECURITY DEFINER` aggregate and grants on a new `inflight_leases` table. Both widen a role the repository keeps deliberately narrow. The design records an ADR-0002 amendment and extends `role-split.integration.test.ts`; the definer function must pin `search_path` and return only sums. This deserves the same dedicated review the auth code gets.
4. **Shared telemetry and docs.** All three add constants to `packages/shared/src/telemetry.ts` and rows to `docs/features/observability.md`, and two update `SECURITY.md`. Land them in separate changes, but check names for collisions when the second and third land.

ADR numbering: only the spend design claims a number (new ADR-0051). The other two propose optional new ADRs without numbers; assign numbers when they are written.

## Still Hypothesis after review

These need a test in Azure or a browser before the plan depends on them:

- Whether an NSG can be attached to a populated Container Apps subnet without recreating the environment (egress design, open question 2).
- Whether `168.63.129.16` is reachable from the egress container and what it exposes there.
- Whether a CSP `sandbox` without `allow-top-navigation` stops a top-level page from navigating itself (containment design says it does not; untested).
- Whether the post-header hang-up already stops the vendor call (spend design, Part 1 characterization test).
