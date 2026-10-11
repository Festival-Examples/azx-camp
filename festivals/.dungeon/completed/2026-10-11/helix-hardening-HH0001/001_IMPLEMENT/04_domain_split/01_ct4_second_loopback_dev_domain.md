---
fest_type: task
fest_id: 01_ct4_second_loopback_dev_domain.md
fest_name: ct4 second loopback dev domain
fest_parent: 04_domain_split
fest_order: 1
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.357589-06:00
fest_updated: 2026-10-10T06:52:15.246474-06:00
fest_tracking: true
---


# Task: ct4 second loopback dev domain

## Objective

Give the dev container a second domain for hosted apps that resolves to 127.0.0.1, switched on by one variable (`HELIX_APPS_DOMAIN`), so later tasks can test the control/apps split locally; with the variable unset nothing changes. Implements CT-4 from 02-app-containment.md.

## Requirements

- [ ] **No change when unset.** With `HELIX_APPS_DOMAIN` unset or blank, `.devcontainer/docker-compose.yml` hands every service the same values it does today (`EDGE_BASE_DOMAIN`, `APP_PUBLIC_BASE`, `DEV_API_PUBLIC_BASE`, `EDGE_TLS_CERT_FILE`, `EDGE_TLS_KEY_FILE`), `resolveStack()` returns the same `env` map it does today, and `just dev smoke` passes as before.
- [ ] **How the second domain gets to 127.0.0.1.** Three layers, none of which depends on `getaddrinfo` or on a DNS server:
  - Browser, in the dev container's smoke run: Chromium is launched with `--host-resolver-rules` that map the apps domain and its subdomains to 127.0.0.1. (Chromium and Firefox also resolve `*.localhost` to loopback by themselves; the rule makes the smoke run independent of that.)
  - Node, in the smoke runner: a custom `lookup` function that returns 127.0.0.1 for the apps domain and anything under it, used by `rawGet` (`node:https`) and by global `fetch` (through an undici `Agent`). glibc does not resolve arbitrary `*.localhost` names, so the runner must not rely on it.
  - Host browser of a developer: nothing to configure for `*.localhost`; the control domain `*.local.helix.azxlabs.io` is already a platform-owned DNS wildcard that points at 127.0.0.1.
- [ ] **Two domains, one switch.** `HELIX_APPS_DOMAIN=helix-apps.localhost` makes apps live at `<slug>.helix-apps.localhost` while the control domain stays `local.helix.azxlabs.io`. The two registrable domains differ (`azxlabs.io` against `helix-apps.localhost`), which is what the later cross-site tests need. Whether a browser really treats them as cross-site is **not** decided here; CT-7 reads `Sec-Fetch-Site` and records the answer.
- [ ] **A second certificate.** `post-create.sh` skips mkcert when `local-helix.pem` exists, so existing dev containers never pick up new names. Add a second guarded block that writes `local-helix-split.pem` and `local-helix-split-key.pem` with these SANs: `*.local.helix.azxlabs.io`, `local.helix.azxlabs.io`, `*.helix-apps.localhost`, `helix-apps.localhost`, `*.apps.local.helix.azxlabs.io`, `apps.local.helix.azxlabs.io`. The last two are for the same-site fallback pair CT-7 may need (`apps.local.helix.azxlabs.io` beside `local.helix.azxlabs.io`): a TLS wildcard covers one label only, so `*.local.helix.azxlabs.io` does **not** cover `demo.apps.local.helix.azxlabs.io`. (The design lists four SANs; the fallback pair needs these two more.)
- [ ] **Compose selects the cert, the domains and the portal bases from the one variable.** When `HELIX_APPS_DOMAIN` is set: `EDGE_BASE_DOMAIN` is the apps domain, `EDGE_CONTROL_DOMAIN` is `local.helix.azxlabs.io`, `APP_PUBLIC_BASE` is the apps origin, `CONTROL_PUBLIC_BASE` and `DEV_API_PUBLIC_BASE` are control origins, and the TLS files are the split pair. `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE` are read by code that CT-5 and CT-6 add; until then the edge and portal ignore them.
- [ ] **`stack-env.mjs` exposes both domains** (`appsDomain`, `controlDomain`, `split`) and, in split mode, emits the split environment at every port offset, including 0. The dev IdP's redirect list and the dev-api base are built from the **control** domain (the auth host does not move). `--ports` and `--env` output for single-domain mode is byte-for-byte what it is today (`package.json` and `apps/portal-web/vite.config.ts` read it).
- [ ] **Failure paths.**
  - A malformed `HELIX_APPS_DOMAIN` (scheme, port, path, spaces, uppercase is lowercased) makes `stack-env.mjs` exit with a clear message instead of booting a stack with a broken base.
  - If the split cert is missing when `HELIX_APPS_DOMAIN` is set, the smoke runner stops before booting with the exact command that creates it (the edge would otherwise fail later with a TLS file error).
  - If mkcert is not installed, the new block is skipped the same way the existing one is, and the smoke runner reports the missing cert.
- [ ] **Until CT-5 and CT-6 land, split mode is not a working stack.** With the variable set, the edge serves apps on the new domain but still builds the auth host as `auth.<apps domain>`, and the dev IdP only knows `auth.<control domain>`, so sign-in cannot complete. The supported check in this task is the new `split-tls` smoke group (below), run with `--only split-tls`. Say this in the compose comment and in the run-helix `SKILL.md`.
- [ ] Depends on: nothing before it in this sequence. It lands after `03_csp_and_headers/` (CT-3), which edits `smoke.mjs`, `cdp.mjs` and the test fixtures too; re-open each file before editing.

## Implementation

Line numbers below are at commit 792557a of `projects/helix`. Earlier sequences (CT-2 especially, which touches `smoke.mjs` and `cdp.mjs`) shift them, so search for the named symbol and read the file again before editing.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-4-second-loopback-dev-domain`.

2. Read first: `.devcontainer/docker-compose.yml:86-98` (the domain comment, `EDGE_BASE_DOMAIN`, `APP_PUBLIC_BASE`, `DEV_API_PUBLIC_BASE`) and `:110-114` (TLS files, `NODE_EXTRA_CA_CERTS`); `.devcontainer/post-create.sh:49-56` (the mkcert block); `scripts/stack-env.mjs` (all of it); `.claude/skills/run-helix/cdp.mjs:37-55` (`launchBrowser` and its Chromium arguments); `.claude/skills/run-helix/smoke.mjs:56` (`resolveStack`), `:95` (`BASE_DOMAIN`), `:190` (`EDGE`), `:202-223` (`rawGet`); `.claude/skills/run-helix/SKILL.md`. Also open what CT-2 did to `launchBrowser` (it may have added an opt-in `ignoreCertErrors` option and a `--host-resolver-rules` argument for `*.${BASE_DOMAIN}`); build on that, do not add a second mechanism.

3. `.devcontainer/post-create.sh`. After the existing block (`:51-56`), add a second one. Same guard style, same `CAROOT`, so the new cert is signed by the CA that `NODE_EXTRA_CA_CERTS` already trusts:

   ```bash
   # Split-domain dev (HELIX_APPS_DOMAIN): one cert for the control domain and both
   # candidate apps domains. A TLS wildcard covers a single label, so the same-site
   # fallback pair (apps.local.helix.azxlabs.io) needs its own wildcard SAN.
   if [ ! -f "$CERT_DIR/local-helix-split.pem" ] && command -v mkcert >/dev/null; then
     mkdir -p "$CAROOT"
     mkcert -cert-file "$CERT_DIR/local-helix-split.pem" \
            -key-file "$CERT_DIR/local-helix-split-key.pem" \
            "*.local.helix.azxlabs.io" local.helix.azxlabs.io \
            "*.helix-apps.localhost" helix-apps.localhost \
            "*.apps.local.helix.azxlabs.io" apps.local.helix.azxlabs.io
   fi
   ```

   `post-create.sh` only runs when the container is created. For an existing container, run just this block by hand (`CAROOT=/workspace/.devcontainer/certs/caroot mkcert ...` with the same arguments). Check the SANs: `openssl x509 -in .devcontainer/certs/local-helix-split.pem -noout -ext subjectAltName` must list all six. If mkcert refuses a name under `.localhost`, record the error in `results/` and stop: the design marks mkcert's handling of these names as a hypothesis.

4. `.devcontainer/docker-compose.yml`. Compose substitutes `${VAR:-default}` and `${VAR:+replacement}`. Replace the single-valued lines with substitutions that give today's value when the variable is unset, and add the pass-through so processes inside the container can read it:

   ```yaml
   HELIX_APPS_DOMAIN: ${HELIX_APPS_DOMAIN:-}
   EDGE_BASE_DOMAIN: ${HELIX_APPS_DOMAIN:-local.helix.azxlabs.io}
   # Empty when unset; the edge treats blank as unset (CT-5).
   EDGE_CONTROL_DOMAIN: ${HELIX_APPS_DOMAIN:+local.helix.azxlabs.io}
   APP_PUBLIC_BASE: https://${HELIX_APPS_DOMAIN:-local.helix.azxlabs.io}:8080
   CONTROL_PUBLIC_BASE: ${HELIX_APPS_DOMAIN:+https://local.helix.azxlabs.io:8080}
   DEV_API_PUBLIC_BASE: https://dev-api.local.helix.azxlabs.io:8082
   EDGE_TLS_CERT_FILE: /workspace/.devcontainer/certs/local-helix${HELIX_APPS_DOMAIN:+-split}.pem
   EDGE_TLS_KEY_FILE: /workspace/.devcontainer/certs/local-helix${HELIX_APPS_DOMAIN:+-split}-key.pem
   ```

   `DEV_API_PUBLIC_BASE` is already a control-domain value and stays literal. Extend the comment at `:86-89` to say what the variable does, that unset means single-domain dev, that the variable is read by Docker Compose when the dev container is created (export it in the shell that starts the container, or put it in `.devcontainer/.env`, which Compose reads for substitution; `.env.local` is only an `env_file` for the container and does **not** feed substitution), and the "not a working login until CT-5 and CT-6" caveat. Do not name any domain other than the two dev domains.

   Check, inside a rebuilt container with the variable unset: `env | grep -E '^(EDGE_BASE_DOMAIN|APP_PUBLIC_BASE|DEV_API_PUBLIC_BASE|EDGE_TLS_CERT_FILE|EDGE_TLS_KEY_FILE)='` prints exactly today's five values, and `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE` are empty. Save the output in `results/`.

5. `scripts/stack-env.mjs`.
   - Near `:53` (`const baseDomain = ...`): read the switch and derive the two domains.

     ```js
     const rawApps = (env.HELIX_APPS_DOMAIN ?? "").trim().toLowerCase();
     if (rawApps && !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(rawApps)) {
       throw new Error(`HELIX_APPS_DOMAIN must be a bare hostname, got: ${rawApps}`);
     }
     const split = rawApps !== "";
     const baseDomain = split ? rawApps : (env.EDGE_BASE_DOMAIN || DEFAULT_BASE_DOMAIN).toLowerCase();
     const controlDomain = split
       ? (env.EDGE_CONTROL_DOMAIN || DEFAULT_BASE_DOMAIN).toLowerCase()
       : baseDomain;
     ```

     `baseDomain` is the **apps** domain (what `EDGE_BASE_DOMAIN` means), `controlDomain` equals `baseDomain` when not split. Return `appsDomain: baseDomain`, `controlDomain` and `split` beside `baseDomain` (the return shape is documented at `:41-47`; update that comment). The CLI block at the bottom of the file handles an invalid domain by printing the error and exiting 2 instead of a stack trace.
   - Offset 0 today returns `env: {}` (`:59-61`). Keep that for single-domain mode. When `split`, build the split keys and include them at every offset: `EDGE_BASE_DOMAIN`, `EDGE_CONTROL_DOMAIN`, `APP_PUBLIC_BASE` (apps origin with `ports.edge`), `CONTROL_PUBLIC_BASE` (control origin with `ports.edge`), `EDGE_TLS_CERT_FILE` and `EDGE_TLS_KEY_FILE` (the split pair, resolved from the repo root, not from `/workspace`). At offset 0 these equal what Compose already sets, so they are harmless.
   - In the existing `out` map (`:79-93`) the lines `DEV_API_PUBLIC_BASE: https://dev-api.${baseDomain}:...` and both `IDP_EDGE_REDIRECT_URIS` entries (`auth.${baseDomain}`) must use `controlDomain`. In single-domain mode the two are equal, so the output does not change. Capture `node scripts/stack-env.mjs --env --offset 1000` and `--ports` before your edit and diff after: identical.

6. `.claude/skills/run-helix/cdp.mjs`, `launchBrowser`. Add an optional `hostRules` array of domains and turn it into one `--host-resolver-rules` argument with a `MAP *.<domain> 127.0.0.1` and a `MAP <domain> 127.0.0.1` entry per domain. If CT-2 already added a rule keyed to `BASE_DOMAIN`, extend that code to take the list rather than adding a second flag (Chromium honors one `--host-resolver-rules`). Do not change the default when `hostRules` is absent. If CT-2 added `ignoreCertErrors`, reuse it for the browser check; a browser that ignores certificate errors proves nothing about the certificate's names, which is why step 8 checks them with Node and openssl, not the browser.

7. `.claude/skills/run-helix/smoke.mjs`, resolution helpers only (the host replacements for auth URLs belong to CT-7).
   - Read the domains from the stack: `const APPS_DOMAIN = STACK.appsDomain; const CONTROL_DOMAIN = STACK.controlDomain;` beside `BASE_DOMAIN` (`:95`). Leave `BASE_DOMAIN` and every existing use of it alone.
   - Add a loopback resolver, used only when `STACK.split`:

     ```js
     // glibc does not resolve arbitrary *.localhost names, so never rely on getaddrinfo for the apps domain.
     const isAppsHost = (h) => h === APPS_DOMAIN || h.endsWith(`.${APPS_DOMAIN}`);
     const loopbackLookup = (hostname, opts, cb) => {
       if (!STACK.split || !isAppsHost(hostname)) return dns.lookup(hostname, opts, cb);
       return opts?.all ? cb(null, [{ address: "127.0.0.1", family: 4 }]) : cb(null, "127.0.0.1", 4);
     };
     ```

     (`import dns from "node:dns"`.)
   - `rawGet` (`:202`): pass `lookup: loopbackLookup` in the `request` options.
   - Global `fetch`: Node's built-in `fetch` uses undici's global dispatcher. `undici` is not resolvable from the repo root (it is a dependency of `apps/edge`, pnpm does not hoist it, and `node_modules/undici` does not exist at the root), so do not `import "undici"`. Load it from the edge package without adding a dependency: `const require = createRequire(join(ROOT, "apps/edge/package.json")); const { Agent, setGlobalDispatcher } = require("undici"); setGlobalDispatcher(new Agent({ connect: { lookup: loopbackLookup } }));`, only when `STACK.split`. Prove it with a one-line check before relying on it: after installing the dispatcher, `fetch("https://smoke-x.<apps domain>:<edge port>/")` must reach the edge (a 404 body) and not fail with `ENOTFOUND`. If Node 24's built-in `fetch` ignores the dispatcher from another undici copy, fall back to patching `dns.lookup` itself (`dns.lookup = loopbackLookup`; `net.connect` reads `dns.lookup` at call time) and write which one worked in `results/`.
   - Browser: `launchBrowser({ port: STACK.cdpPort, hostRules: STACK.split ? [APPS_DOMAIN, CONTROL_DOMAIN] : [] })` at the call in `checkBrowser`.
   - Add `"split-tls"` to `GROUPS` (`:61`) and a `checkSplitTls()` group, wired into `main()` after `checkEdge`, that runs only when `STACK.split` (it is not in the default run for single-domain mode). Checks:
     1. The split cert and key files exist, else fail with the mkcert command from step 3.
     2. A Node TLS handshake to `127.0.0.1:<edge port>` with `servername: "smoke-x." + APPS_DOMAIN` and the mkcert CA (`NODE_EXTRA_CA_CERTS` is already set by the runner at `smoke.mjs:30-37`) reports `authorized === true`, and the peer certificate's `subjectaltname` contains `*.<APPS_DOMAIN>`. Node does verify the name here, which Chromium with ignored certificate errors does not.
     3. `GET https://smoke-x.<APPS_DOMAIN>:<edge port>/` through `fetch` gets a 404 from the edge (the slug is unknown), proving name resolution and routing end to end.
     4. In Chromium (skip with a reason if there is no cached browser, as `checkBrowser` does): navigate to the same URL and assert no failed request and no certificate error.
   - Update the header comment of the file and `SKILL.md` ("Split-domain mode": the variable, that `--only split-tls` is the supported check until CT-5/CT-6, and the cert command).

8. Tests. A repo-wide search found no test for `scripts/stack-env.mjs` or the smoke runner (only their consumers), so the evidence is the smoke run. Add a vitest for `resolveStack` only if the existing vitest config already picks up a file under `scripts/` without config changes; otherwise do not invent a test setup. The assertions that matter are: single-domain `--env` and `--ports` output unchanged (diff saved), split output contains the keys named above with the control domain on the IdP list, and a bad domain exits non-zero.

9. Docs. The dev domain is described in the compose comments and `docs/platform-project-plan.md:53`; add a sentence there only if it states the dev domain as the only one (CT-10 does the full documentation pass). No telemetry changes.

10. Run, from the dev container: `./check-and-lint.sh`; `just dev smoke` (single-domain, unchanged); `HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke --only split-tls`. Save outputs in `results/`.

## Done When

- [ ] All requirements met.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just dev smoke` passes in single-domain mode with no new SKIP and no changed output apart from the wording you added.
- [ ] `HELIX_APPS_DOMAIN=helix-apps.localhost just dev smoke --only split-tls` passes: the handshake is authorized with the split cert and the SANs are listed, the Node client and (if Chromium is cached) the browser reach `https://smoke-x.helix-apps.localhost:<port>/` without relying on `getaddrinfo`. If Chromium is absent the browser leg is reported as a SKIP and written up as unverified, not as a pass.
- [ ] `results/` holds: the single-domain `docker-compose` environment check, the before/after `stack-env.mjs` output diff, the SAN listing, the smoke outputs, and which `fetch` mechanism worked (global dispatcher or `dns.lookup` patch).
- [ ] Untested, and stated as such in `results/`: mkcert and Chromium handling of a wildcard under `.localhost` if Chromium did not run; Safari's handling of `*.localhost` (the design marks it unverified); whether any browser treats the two dev domains as cross-site (that is CT-7). No Azure behavior is involved.
- [ ] Committed with `fest commit -m "CT-4: second loopback dev domain (HELIX_APPS_DOMAIN)"`.