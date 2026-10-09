---
fest_type: task
fest_id: 03_ct6_portal_control_origin.md
fest_name: ct6 portal control origin
fest_parent: 04_domain_split
fest_order: 3
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.358329-06:00
fest_tracking: true
---

# Task: ct6 portal control origin

## Objective

Give the portal an optional `CONTROL_PUBLIC_BASE` so the vendor OAuth callback URL it publishes and binds can point at the control domain when hosted apps move to a different domain, while app URLs keep coming only from `APP_PUBLIC_BASE`. Implements CT-6 from 02-app-containment.md.

## Requirements

- [ ] **New optional setting.** `CONTROL_PUBLIC_BASE` (scheme, host, port of the control domain, for example `https://control.example.test`). Unset or blank defaults to `APP_PUBLIC_BASE`, which is today's behavior: every existing portal test passes unmodified.
- [ ] **It drives one thing: the vendor callback URL.** `connectionsCallbackUrl()` becomes `<scheme>//auth.<CONTROL_PUBLIC_BASE host>/connections/callback`. The three portal consumers get the new value without edits of their own because they call the function: `connections/completion.ts:410` (the code exchange's `redirectUri`), `routes/providers.ts:514` (the callback hint administrators register with vendors) and `routes/connectionsPages.ts:78` (the nonce redemption that re-derives the authorize request). The edge builds the same URL from `EDGE_CONTROL_DOMAIN` (CT-5), and the two must agree.
- [ ] **App URLs do not change.** `appPublicUrl()`, `appPublicHost()`, `GET /api/v1/config` (`appPublicBase`), `routes/catalogue.ts:178` (`appsHost`) and `routes/dashboard.ts` keep reading `APP_PUBLIC_BASE` only. The SPA is not touched; `GET /api/v1/config` does not gain a control field (`AGENTS.md`: never reintroduce a `VITE_*` domain variable or derive the apps host from `window.location`).
- [ ] **Boot validation fails closed.** `assertDeploymentConfig` validates `CONTROL_PUBLIC_BASE` the way it validates `DEV_API_PUBLIC_BASE`: an invalid value throws at boot and names the variable. Beyond URL validity, the portal can check the pair it holds, mirroring the edge's boot rule: the control host must not be a subdomain of the apps host (an app could then set cookies that reach it), and the control origin must share scheme and port with the apps origin (the edge serves both on one listener and builds both with one public port).
- [ ] **The "derived, never configured" rule is replaced, with its reason.** The comment at `deployment.ts:67-70` argued against a second auth-base field because it could drift from the edge's. The new comment states the new rule: once apps can leave the control domain the portal can no longer derive the auth host from `APP_PUBLIC_BASE`, so it is configured; the edge and portal values come from one Bicep parameter (CT-9); and a mismatch fails at the vendor, never open.
- [ ] **Mismatch behavior is stated honestly.** The portal cannot see the edge's environment, so it cannot fail at boot when only one of `EDGE_CONTROL_DOMAIN` and `CONTROL_PUBLIC_BASE` is set (the design's test 10 says it "fails or the callback fails closed"; only the second half is possible). What this task provides: the portal-side checks above, and the cross-plane evidence that a callback URL on the wrong host fails closed (the edge returns 404 for it, covered by CT-5 test 10). The operator runbook check is that the `callbackUrl` in `GET /api/v1/providers` equals `https://auth.<EDGE_CONTROL_DOMAIN>/connections/callback`; CT-10 writes it.
- [ ] Depends on: `02_ct5_edge_control_and_apps_domain_split.md` (the edge must classify `auth.<controlDomain>` as the auth host for the new callback URL to be served). This task changes only portal code and portal tests.

## Implementation

Line numbers are at commit 792557a of `projects/helix`.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-6-portal-control-origin`.

2. Read first: `apps/portal/src/deployment.ts` (all 135 lines; note `resolveAppPublicBase` at `:28-45`, `connectionsCallbackUrl` at `:72-75`, `resolveDevApiBase` at `:85-93` as the optional-URL pattern, `assertDeploymentConfig` at `:131-135`); `apps/portal/src/deployment.test.ts` (`:18-97`, `:164-184`); `apps/portal/src/app.ts:74-76` (where `assertDeploymentConfig()` runs); `apps/portal/src/routes/config.ts` and `config.test.ts:20-33`; `routes/providers.test.ts:286-312`; `routes/apps.test.ts:423-435`.

3. `deployment.ts`. Add the resolver next to `resolveAppPublicBase`. Follow `resolveDevApiBase` for the optional shape and `resolveAppPublicBase` for the error wording.

   ```ts
   /**
    * Scheme + host + port of the control domain (`CONTROL_PUBLIC_BASE`): where the
    * auth host (`auth.`) lives. Optional — unset or blank means the control hosts
    * share the apps domain, which is the single-domain layout. When set it must
    * agree with the edge's EDGE_CONTROL_DOMAIN; the two come from one Bicep
    * parameter, and a mismatch fails at the vendor's redirect-URI check.
    */
   export function resolveControlPublicBase(env: NodeJS.ProcessEnv = process.env): URL {
     const apps = resolveAppPublicBase(env);
     const raw = env.CONTROL_PUBLIC_BASE?.trim();
     if (!raw) return apps;
     let control: URL;
     try {
       control = new URL(raw);
     } catch {
       throw new Error(`CONTROL_PUBLIC_BASE is not a valid absolute URL: ${raw}`);
     }
     if (control.protocol !== apps.protocol || control.port !== apps.port) {
       throw new Error(
         `CONTROL_PUBLIC_BASE (${control.origin}) must use the same scheme and port as ` +
           `APP_PUBLIC_BASE (${apps.origin}): the edge serves both on one listener.`,
       );
     }
     if (control.hostname.endsWith(`.${apps.hostname}`)) {
       throw new Error(
         `CONTROL_PUBLIC_BASE (${control.hostname}) must not be a subdomain of the apps host ` +
           `(${apps.hostname}): an app could set cookies that reach the control hosts.`,
       );
     }
     return control;
   }
   ```

   Check that a literal port equal to the scheme default compares correctly: `new URL("https://a.test:443").port` is `""`, the same as no port, so `port` comparison is safe.

   Change `connectionsCallbackUrl` to use it, and replace its doc comment (`:58-71`) so it says: the callback is `auth.<control host>` plus `CONNECTIONS_CALLBACK_PATH`; the control base defaults to the apps base; the edge's `/connections/*` proxy forwards that prefix to this portal; the shared constant is the single source both planes read. Replace the "Derived, never configured" paragraph with the new rule from Requirements.

   ```ts
   export function connectionsCallbackUrl(env: NodeJS.ProcessEnv = process.env): string {
     const base = resolveControlPublicBase(env);
     return `${base.protocol}//auth.${base.host}${CONNECTIONS_CALLBACK_PATH}`;
   }
   ```

   Add `resolveControlPublicBase(env);` to `assertDeploymentConfig` (`:131-135`) after `resolveAppPublicBase(env)`. Update the file-header comment if it lists the env variables it reads.

4. No change to `routes/config.ts`, `routes/catalogue.ts`, `routes/dashboard.ts`, the SPA, or `packages/shared/src/deployment.ts`. Confirm with `grep -rn "resolveAppPublicBase\|connectionsCallbackUrl" apps/portal/src --include='*.ts' | grep -v test` that every `connectionsCallbackUrl` caller is one of the three named above and every `resolveAppPublicBase` caller is about app URLs.

5. Tests (portal unit tests; the DB-backed ones need the dev container).
   - `deployment.test.ts`: a new `describe("resolveControlPublicBase")` after the `connectionsCallbackUrl` block (`:77-97`):
     - unset and blank both return the apps base (`resolveControlPublicBase({ APP_PUBLIC_BASE: "https://azx.helix.azxlabs.io" }).origin`);
     - a set value is returned, for example `{ APP_PUBLIC_BASE: "https://apps.example.test", CONTROL_PUBLIC_BASE: "https://control.example.test" }`;
     - a non-URL value throws /not a valid absolute URL/;
     - a different port or scheme throws /same scheme and port/;
     - a control host that is a subdomain of the apps host throws /subdomain/; the reverse (apps host a subdomain of the control host, the delegated-subdomain case) is allowed.
     Extend `describe("connectionsCallbackUrl")` with the split case: with the pair above, the callback is `https://auth.control.example.test/connections/callback`, and `appPublicUrl("demo", env)` is `https://demo.apps.example.test`; assert the two hosts have different registrable domains by construction (they share no suffix). The two existing cases (`:83-96`) stay as they are and prove the default.
     Extend `describe("assertDeploymentConfig")` (`:164`): a malformed `CONTROL_PUBLIC_BASE` throws /CONTROL_PUBLIC_BASE/; the well-formed split pair does not throw.
   - `routes/config.test.ts` (after `:31`): with `APP_PUBLIC_BASE=https://apps.example.com` and `CONTROL_PUBLIC_BASE=https://control.example.com` (use the file's `withEnv`), `GET /api/v1/config` returns `appPublicBase` equal to the apps origin, and `JSON.stringify(res.json())` contains no `control.example.com`.
   - `routes/apps.test.ts` (after `:423-435`): same two variables; a created app's `url` is on the apps host (`https://<slug>.apps.example.com`) and the control host appears nowhere in it.
   - `routes/providers.test.ts` (after `:294-307`): with the same split env stubbed through `vi.stubEnv`, `GET /api/v1/providers` returns `callbackUrl` `https://auth.control.example.com/connections/callback`; keep the `try/finally` + `vi.unstubAllEnvs()` pattern.
   - Mismatch evidence for the record: the portal cannot be tested against the edge here. In `results/` quote CT-5's test 10 (the edge answers 404 for `auth.<apps>/connections/callback`) as the other half.

6. Docs: code comments only here. The documentation of the new variable (`apps/docs/src/deploy/configuration.md:190`, `infra/azure/README.md:433`, `docs/features/portal-web.md:257`) is CT-10.

7. Run from the dev container: `./check-and-lint.sh` (the portal route tests need Postgres), then `just dev smoke` (portal changed). Single-domain smoke must pass unchanged; split-mode smoke is CT-7.

## Done When

- [ ] All requirements met.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just dev smoke` passes (single-domain mode, unchanged).
- [ ] With `CONTROL_PUBLIC_BASE` unset every existing portal test passes unmodified.
- [ ] With it set, the callback URL is on the control host and app URLs are on the apps host, in the unit tests and in the `GET /api/v1/providers` and `GET /api/v1/config` route tests. An invalid value, a scheme or port mismatch and a control host under the apps host each throw at boot.
- [ ] `results/` records the portal half of design test 10 as "boot check on the portal's own pair of values; cross-plane mismatch fails closed at the vendor and at the edge (CT-5 test 10)", and states that the portal cannot detect a one-sided setting.
- [ ] Not verified here: that an operator who sets only one of the two variables sees the vendor reject the redirect (needs a real vendor and real domains); anything about Azure. Both go in the operator rollout notes (CT-10).
- [ ] Committed with `fest commit -m "CT-6: portal CONTROL_PUBLIC_BASE for the vendor callback URL"`.
