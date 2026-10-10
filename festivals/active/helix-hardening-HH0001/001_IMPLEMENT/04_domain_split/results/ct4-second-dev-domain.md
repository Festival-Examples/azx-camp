# CT-4 result: second loopback dev domain

**Result: done.** `HELIX_APPS_DOMAIN` switches the dev stack to split mode. Hosted apps live on `<slug>.<apps domain>` (for example `helix-apps.localhost`), while the control domain stays `local.helix.azxlabs.io`. With the variable unset, nothing changes.

- `.devcontainer/post-create.sh`: a second guarded mkcert block writes `local-helix-split.pem` and its key, with six SANs. That covers the control domain, `*.helix-apps.localhost`, and `*.apps.local.helix.azxlabs.io` for the same-site fallback pair.
- `.devcontainer/docker-compose.yml`: substitutions select the apps and control domains, the portal bases and the TLS pair from the one variable.
- `scripts/stack-env.mjs`:
  - validates the domain, exiting 2 with a message on a bad value;
  - returns `appsDomain`, `controlDomain` and `split`;
  - emits the split environment at every offset;
  - builds the dev IdP redirect list and the dev-api base from the control domain.
- `.claude/skills/run-helix/cdp.mjs`: CT-2's `baseDomain` rule is generalized into a `hostRules` list (one `--host-resolver-rules` flag).
- `.claude/skills/run-helix/smoke.mjs`:
  - a loopback `lookup` for the apps domain, because glibc does not resolve arbitrary `*.localhost` names;
  - an undici global dispatcher loaded from `apps/edge` via `createRequire`, which worked, so the `dns.lookup` patch was not needed;
  - a pre-boot check for the split certificate;
  - a `split-tls` group.
- `.claude/skills/run-helix/SKILL.md`: a "Split-domain mode" section.

Until the edge and portal read the control domain (CT-5, CT-6), split mode is not a working login stack; `--only split-tls` is the supported check. The compose comment and `SKILL.md` say so, without plan IDs.

## Coordinator fixes

- The `split-tls` group was called on every run and printed "SKIP — HELIX_APPS_DOMAIN is unset" in single-domain mode, which the task forbids. It is now called only in split mode or with an explicit `--only split-tls`, which already exits 2 without the variable.
- "CT-5/CT-6" appeared in the `smoke.mjs` header, `SKILL.md` and the compose comment. These are replaced with what actually has to happen ("until the edge and portal read `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE`").

## Evidence (coordinator)

- `stack-env.mjs` single-domain `--env` and `--ports`, at offsets 0 and 1000, against `HEAD`: identical. `HELIX_APPS_DOMAIN="https://x.example:443"` exits 2 with "must be a bare hostname".
- Compose `config` (agent; the coordinator checked the file parses after the comment edit):
  - Unset: today's five values; `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE` are empty.
  - Set: `EDGE_BASE_DOMAIN=helix-apps.localhost` and `EDGE_CONTROL_DOMAIN=local.helix.azxlabs.io`, with the matching `APP_PUBLIC_BASE`, `CONTROL_PUBLIC_BASE` and split TLS files.
  - The dev container was not recreated, so the hand-installed browser-lane dependencies are kept.
- SANs (openssl): `*.local.helix.azxlabs.io`, `local.helix.azxlabs.io`, `*.helix-apps.localhost`, `helix-apps.localhost`, `*.apps.local.helix.azxlabs.io`, `apps.local.helix.azxlabs.io`. mkcert accepted the `.localhost` wildcard. The cert files are gitignored.
- `./check-and-lint.sh`: 241 of 241 test files.
- Smoke with a real browser:
  - Single-domain: 37 passed, 0 failed, 0 skipped.
  - `HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke --only split-tls`: 8 passed, 0 failed, 0 skipped. That includes "TLS handshake authorizes apps-domain SNI", "fetch reaches the edge on the apps domain (404)" and "Chromium reaches the apps domain without cert errors" (`ct4-gate.txt`).

## Untested

- Safari's handling of `*.localhost`.
- Whether any browser treats the two dev domains as cross-site (CT-7).
- The host-OS browser on `helix-apps.localhost` (the in-container Chromium passed).
- The `dns.lookup` fallback, which was not needed.

No Azure behavior is involved.

## Executor

cursor-agent, `composer-2.5`, 46 tool calls. Coordinator fixes as listed.
