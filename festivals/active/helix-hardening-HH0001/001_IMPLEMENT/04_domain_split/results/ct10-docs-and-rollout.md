# CT-10 result: docs, ADR amendments and rollout notes

**Result: done, with one carried defect (below) for the sequence review.**

## Where each setting is documented

| Setting | Doc locations |
| --- | --- |
| `EDGE_CONTROL_DOMAIN` | `apps/edge/README.md`, `apps/docs/src/deploy/configuration.md`, `docs/features/authentication.md`, `docs/features/edge-serving.md` |
| `hostedAppsDomain` | `configuration.md`, `getting-started.md`, `updates.md`, `infra/azure/README.md` |
| `hostedAppsTlsBound` | `configuration.md`, `updates.md`, `infra/azure/README.md`, ADR-0044 |
| `legacyAppRedirect` / `EDGE_LEGACY_APP_REDIRECT` | the edge README, `configuration.md`, `updates.md`, `edge-serving.md`, `observability.md` (the counter, from CT-8) |
| `CONTROL_PUBLIC_BASE` | `configuration.md`, `infra/azure/README.md`, `authentication.md`, the ADR-0028 amendment |
| `EDGE_IMG_SRC_EXTRA`, `EDGE_IMG_SRC_ALLOW_ALL`, `EDGE_IMG_SRC_REPORT_ONLY` | already in the edge README, `configuration.md` and `updates.md` (CSP sequence); not duplicated |
| `HELIX_APPS_DOMAIN` | `README.md`, `.claude/skills/run-helix/SKILL.md`, `apps/connections-lane/README.md` |

## Rollout notes

`apps/docs/src/deploy/updates.md` gains "Upgrading to hosted-app containment":
- **Part 3, response headers:** no setting; `Link` passes.
- **Part 2, CSP:** points at the existing image-policy section and its step 0, instead of duplicating it.
- **Part 1, domain split:**
  - New install: delegate both zones, set the parameters, run both certbot jobs, flip both TLS gates.
  - Existing install: keep the current domain as control and move apps, with a staging-app cross-browser sign-in check marked **operator-run**.
  - Data migration and compatibility notes.

The Public Suffix List requirement for a delegated apps subdomain is marked operator-run. The firewall prerequisite (the per-subnet platform lists before the second certbot run) is included. The routine update links to the section.

**Coordinator fixes:** the firewall prerequisite now comes before the certbot run it gates (it was step 4, after step 3's run). The operator text names the metric `helix.session.gate_denied`, not the code constant.

## ADRs

- **ADR-0028:** extended the existing `## Amendment (2026-10-09): admission controls are per-install settings` with the domain lines. There is still one amendment section.
- **ADR-0019:** a dated pointer to the ADR-0028 section.
- **ADR-0044:** a dated amendment: one certificate name and binding pair per domain, the second gate parameter, and the what-if canary applies to both bindings.
- **ADR-0009:** verified that the CSP sequence's amendment matches the shipped CSP; no second amendment.
- **ADR-0035, ADR-0021, ADR-0037:** no change. The split adds no egress seam, ledger change or telemetry beyond CT-8's counter, which is already in the observability inventory.
- **Owner question (open):** whether the configured-not-derived portal control origin deserves its own ADR. It currently lives in the ADR-0028 amendment and the feature docs.

## Design correction: the legacy-redirect sunset

The design says to delete the control wildcard DNS record **and its certificate binding**. The binding cannot go: `auth.<control>` terminates TLS through the edge's `*.<control>` binding, and certbot re-binds it on every run. The notes say instead:
- set `legacyAppRedirect` to false and re-apply;
- delete the control zone's `*` A record by hand (a re-apply does not delete records);
- keep the binding and the `auth`, `portal` and `dev-api` records.

## Tested and untested

- **Tested locally**, in the dev container with Chromium 156:
  - host classification, the handoff, and the Origin and Fetch Metadata checks;
  - the legacy-redirect rules and the split adversarial and integration suites;
  - the CT-7 `Sec-Fetch-Site` finding: `cross-site` for the `.localhost` pair, `same-site` for the same-site pair, with the cookie negative control.
- **Untested:** Safari ITP, Firefox ETP and Chrome bounce-tracking mitigations on real domains, a real Public Suffix List entry and DNS delegation, certificate issuance and two wildcard bindings on one Container App, and the two-binding TLS canary. These are the operator's checks.

## Carried defect (from CT-9; for the sequence review and iterate)

The existing-install steps tell the operator to stage the apps-domain certificate before moving apps (step 3), then flip `hostedAppsDomain` and the portal and edge variables together (step 5). The template cannot stage. In `infra/azure/main.bicep`, `certbotHosted` and `dnsHosted` are gated on `hostedSplit`, which comes from `hostedAppsDomain`, and the same parameter switches `EDGE_BASE_DOMAIN` and `APP_PUBLIC_BASE`. Setting it moves the apps before their certificate exists, so apps are unreachable over TLS until the second certbot job runs, and old hosts 404 or redirect into that gap. The design intended DNS and certificates first and the flip last. The fix is a template change: separate "provision the apps domain" from "cut over".

## Evidence (coordinator)

- `./check-and-lint.sh`: 242 of 242 test files, docs build and format included (`ct10-gate.txt`).
- One ADR-0028 amendment section.
- No plan change IDs or code constants in the operator docs.

## Executor

cursor-agent, `composer-2.5`, 100 tool calls. Coordinator fixes as listed.
