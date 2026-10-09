---
fest_type: task
fest_id: 06_ct9_bicep_dns_and_certbot_for_apps_domain.md
fest_name: ct9 bicep dns and certbot for apps domain
fest_parent: 04_domain_split
fest_order: 6
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-09T12:11:05.359987-06:00
fest_tracking: true
---

# Task: ct9 bicep dns and certbot for apps domain

## Objective

Add the Bicep that lets an install serve hosted apps from a second domain (`hostedAppsDomain`): the edge, portal and dev-gateway get the two domains, the edge declares a second wildcard binding, the apps zone holds only `*` and `asuid`, and the certbot job is instantiated a second time for the apps domain, all compile-checked only and labeled unverified in Azure. Implements CT-9 from 02-app-containment.md.

## Requirements

Nothing here is deployed or applied. Bicep is compile-checked with `just infra build` only (decision V4). Anything that needs Azure is labeled **unverified in Azure** in the parameter descriptions, in `results/`, and in Done When.

- [ ] **New parameters, all default-off, so every existing `.bicepparam` stays valid.**
  - `hostedAppsDomain string = ''` (empty means "same as `appsDomain`", the single-domain layout). `appsDomain` keeps its meaning and becomes the **control** domain when `hostedAppsDomain` is set. The name reads backwards for a new install; the description says so and CT-10 explains it in the docs.
  - `hostedAppsTlsBound bool = false`: the second gate, for the same reason ADR-0044 introduced `wildcardTlsBound` (a declarative binding to a certificate that does not exist fails the app PUT). Flip it after the second certbot run.
  - `legacyAppRedirect bool = false`: sets `EDGE_LEGACY_APP_REDIRECT` for CT-8, and keeps the control zone's `*` record while the redirect is on. The design's file list omits this parameter, but its rollout notes tell the operator to set the edge variable through Bicep, so there has to be one (the CSP sequence made the same kind of addition for `imgSrcExtra` and `imgSrcAllowAll`). Record it as a design gap in `results/`.
- [ ] **Unset means unchanged.** With the three parameters unset, every value the template produced before is produced again (`EDGE_BASE_DOMAIN`, `APP_PUBLIC_BASE`, the edge `customDomains`, the DNS records, the certbot module). A byte-identical compiled template is not reachable: new parameters, new variables, and `condition`s on resources that used to be unconditional all appear in the JSON. The real criterion: compile on `main` and on the branch, diff the two JSON documents, and every hunk must be one of (a) a new parameter with its default, (b) a new variable, (c) a `condition` that evaluates true when the new parameters are unset, (d) a new resource or module gated false when they are unset, or (e) an expression whose unset branch yields the old value. No existing value changes. Save the diff in `results/` and annotate each hunk.
- [ ] **With the parameters set** (read from the compiled expressions; evaluation under set parameters is unverified in Azure):
  - the edge gets `EDGE_BASE_DOMAIN = hostedAppsDomain` and `EDGE_CONTROL_DOMAIN = appsDomain`; the dev-gateway gets the same two values (its popup URL uses the auth host);
  - the portal gets `APP_PUBLIC_BASE = https://<hostedAppsDomain>` and `CONTROL_PUBLIC_BASE = https://<appsDomain>`; `DEV_API_PUBLIC_BASE` is unchanged (`dev-api.<appsDomain>`);
  - the edge gets two `customDomains`: `*.<appsDomain>` with the control certificate and `*.<hostedAppsDomain>` with the apps certificate, each gated by its own flag;
  - `dns.bicep` is instantiated twice: the control zone keeps `auth`, `portal`, `dev-api` (when deployed) and `asuid`, plus `*` only while `legacyAppRedirect` is on or no split is configured; the apps zone gets only `*` and `asuid`;
  - the certbot module is instantiated twice with distinct names and the apps instance passes empty `portalAppName` and `devGatewayAppName`, so it issues `*.<hostedAppsDomain>` and binds it on the edge only;
  - `EDGE_CONTROL_DOMAIN`, `CONTROL_PUBLIC_BASE`, `EDGE_LEGACY_APP_REDIRECT` and the second `customDomains` entry are emitted **only** when the split is configured, so a single-domain install sees no environment or revision churn.
- [ ] **Unchanged on purpose.** The availability probe stays `https://auth.${appsDomain}/health` (`main.bicep:895`): it is keyed to the control domain, which still hosts `auth.`, and the edge answers platform `/health` only on non-app hosts. `apps/certbot/issue-and-bind.sh` is not edited (it is already parameterised by `APPS_DOMAIN`, `CERT_NAME`, `EDGE_APP`, `PORTAL_APP` and `DEV_GATEWAY_APP`). `infra/entra` is not touched (the auth host does not move, so redirect URIs do not change).
- [ ] **ADR-0044 invariant per certificate.** Each certificate name is computed once in `main.bicep` and passed both to its certbot instance (`CERT_NAME`) and to its declarative binding (`certificateId`). The control name stays `wildcard-<appsDomain with dashes>` (`main.bicep:1120`), so a live install's existing name does not change.
- [ ] **Certbot double instantiation: settled by reading the module.** `certbot.bicep` names the identity `${namePrefix}-certbot-id` (`:80`) and the job `${namePrefix}-certbot` (`:148`), so a second instance with the same `namePrefix` would collide on both and silently overwrite the first job. Role assignment names are `guid(...)` of the identity id (`:101`, `:110`, `:119`), so they are distinct once the identities are. The collision is therefore avoided with no change to the module by passing a different `namePrefix` to the second instance (below). The module is not edited.
- [ ] **Firewall installs.** The apps-domain certbot job runs in the apps environment. On an install that runs the Azure Firewall it needs the ACME, Azure Resource Manager and Entra hosts on the apps subnet's list, which `02_network_egress/06_eg6_firewall_platform_lists_and_threat_intel.md` (EG-6) adds. EG-6 must land first on such installs. Both instances use the one `acmeServer` parameter, so the single `acmeServerHost` EG-6 derives still covers both; if a task ever gives each domain its own ACME server, that variable has to become a list.
- [ ] **Failure paths from the design.**
  - Second certificate missing or bound to the wrong name: with `hostedAppsTlsBound=false` the template declares no binding for the apps domain and the certbot job binds at runtime (the ADR-0044 bootstrap path); with the flag on and no certificate, the edge app PUT fails loudly at deploy, not silently at runtime.
  - Apps moved before DNS or the certificate exist: TLS fails in the browser. The old URLs keep working because the control wildcard stays bound. The operator order that avoids this (DNS and certificates first, the portal `APP_PUBLIC_BASE` flip last) goes in the rollout notes (CT-10).
  - A bad pair of domains (the control domain under the apps domain) is refused by the edge at boot (CT-5), not by Bicep, which cannot check it at compile time; the parameter description says so. The delegated-subdomain pair (apps domain under the control domain) is allowed and only separates the sites if the zone is on the Public Suffix List.
- [ ] Depends on: `02_ct5_edge_control_and_apps_domain_split.md` and `03_ct6_portal_control_origin.md` (the settings this template sets), `02_network_egress/06_eg6_firewall_platform_lists_and_threat_intel.md` on firewall installs, and `05_ct8_legacy_app_host_redirect.md` for the variable `legacyAppRedirect` sets.

## Implementation

Line numbers are at commit 792557a of `projects/helix`. The CSP sequence (CT-2, CT-3) and EG-4 to EG-7 add parameters and resources to `main.bicep` and shift every line below; search for the named symbol and read the surrounding block first.

1. Create the branch: `cd projects/helix && git checkout main && git checkout -b ct-9-bicep-dns-certbot-apps-domain`.

2. Read first: `infra/azure/main.bicep` at `:55` (`appsDomain`), `:378-390` (`deployCertbot`, `wildcardTlsBound` and its long description, the model for yours), `:403` (`domainVerificationId`), `:880-910` (availability targets), `:1115-1150` (certificate name, `declarativeTls`, the edge `customDomains`), `:1177-1248` (edge `envVars`, `EDGE_BASE_DOMAIN` at `:1197`), `:1262-1280` (portal `customDomains`), `:1298-1356` (portal `envVars`, `APP_PUBLIC_BASE` and `DEV_API_PUBLIC_BASE` at `:1334-1340`), `:1388-1402` (dev-gateway `customDomains`), `:1419-1453` (dev-gateway `envVars`, `EDGE_BASE_DOMAIN` at `:1433`), `:1465-1505` (the `dns` and `certbot` modules); `infra/azure/modules/dns.bicep` (all 96 lines); `modules/certbot.bicep` (all 202 lines); `modules/containerapp.bicep:82-111` (an empty `customDomains` omits the property); `apps/certbot/issue-and-bind.sh:105-180` (what it issues and binds); `infra/azure/README.md:298-372` (Wildcard TLS, including the what-if canary) and `ADR-0044` (`docs/adr/0044-declarative-wildcard-tls-bindings.md`).

3. Baseline compile for the diff, before any edit: from the dev container, `az bicep build --file infra/azure/main.bicep --stdout > "$RESULTS/main.before.json"` (and the same for `modules/dns.bicep`, `modules/certbot.bicep`).

4. `main.bicep` parameters. Add them next to the TLS parameters (after `wildcardTlsBound`, `:388`). Descriptions follow the house style: what it does, the default, who should set it, and the unverified label.
   ```bicep
   @description('Serve hosted apps on a separate domain from the control hosts (auth., portal., dev-api.). Empty (default) = apps stay on appsDomain, the single-domain layout. When set, appsDomain becomes the CONTROL domain (auth/portal/dev-api, Entra and vendor callback URLs do not move) and apps live at <slug>.<hostedAppsDomain>. Delegate the zone, list it on the Public Suffix List if it is a subdomain of a domain you own (without that the two are the same site and the cookie protection is lost), and set hostedAppsTlsBound after the second certbot run. The edge refuses to start if appsDomain (the control domain) is a subdomain of hostedAppsDomain, because an app could then set cookies that reach the control hosts; the reverse, hostedAppsDomain under appsDomain, boots and needs the Public Suffix List entry. Two wildcard certificates on one Container App are UNVERIFIED IN AZURE.')
   param hostedAppsDomain string = ''

   @description('Declare the hosted-apps wildcard binding in-template, the second gate beside wildcardTlsBound (ADR-0044). TRUE only after the second certbot job has run: a declarative binding to a certificate that does not exist fails the edge app PUT loudly. Set it literally in the params file, never from an env var. Only meaningful with hostedAppsDomain. UNVERIFIED IN AZURE.')
   param hostedAppsTlsBound bool = false

   @description('Redirect old <slug>.<appsDomain> app URLs to the new apps domain with a 307 (EDGE_LEGACY_APP_REDIRECT), and keep the control zone wildcard DNS record while it is on. Only meaningful with hostedAppsDomain. Turn it off when the helix.edge.legacy_app_redirects counter has been zero for a period you choose. Default false.')
   param legacyAppRedirect bool = false
   ```
   Derived variables, next to `wildcardCertName` (`:1120`):
   ```bicep
   var hostedSplit = !empty(hostedAppsDomain) && hostedAppsDomain != appsDomain
   var appHostsDomain = hostedSplit ? hostedAppsDomain : appsDomain
   var hostedCertName = 'wildcard-${replace(hostedAppsDomain, '.', '-')}'
   var hostedCertId = '${appsEnv.outputs.environmentId}/certificates/${hostedCertName}'
   var certbotEnabled = deployApps && deployCertbot && !empty(acmeEmail)
   var declarativeHostedTls = hostedSplit && certbotEnabled && hostedAppsTlsBound
   ```
   `declarativeTls` (`:1126`) stays as it is; it gates the control binding.

5. Edge. `EDGE_BASE_DOMAIN` (`:1197`): `value: appHostsDomain`. `customDomains` (`:1141-1150`) becomes a concatenation, so the unset case is still `[]` and the property is still omitted (`containerapp.bicep:111`):
   ```bicep
   customDomains: concat(
     declarativeTls ? [ { name: '*.${appsDomain}', bindingType: 'SniEnabled', certificateId: wildcardCertId } ] : [],
     declarativeHostedTls ? [ { name: '*.${hostedAppsDomain}', bindingType: 'SniEnabled', certificateId: hostedCertId } ] : []
   )
   ```
   Keep the existing comment on the first entry and add one on the second. The extra environment entries are added without touching the long literal list: change only the `envVars: [` line (`:1177`) to `envVars: concat([` and the closing `]` (`:1248`) to `], splitEdgeEnv)`, and define above the module:
   ```bicep
   var splitEdgeEnv = concat(
     hostedSplit ? [ { name: 'EDGE_CONTROL_DOMAIN', value: appsDomain } ] : [],
     hostedSplit && legacyAppRedirect ? [ { name: 'EDGE_LEGACY_APP_REDIRECT', value: 'true' } ] : []
   )
   ```
   The lowercase literal `'true'` matters: the edge parses `=== "true"`, and ARM's `string(bool)` yields `True` (see the comment at `:1216-1221` for `EDGE_ALLOW_PUBLIC_APPS`). Add a comment saying the control domain is omitted, not blank, when unset so a single-domain install sees no new environment variable.

6. Portal. `APP_PUBLIC_BASE` (`:1334`): `'https://${appHostsDomain}'`. The same concat trick on its `envVars` (`:1298`, closing `]` at `:1356`) with `splitPortalEnv = hostedSplit ? [ { name: 'CONTROL_PUBLIC_BASE', value: 'https://${appsDomain}' } ] : []`. `DEV_API_PUBLIC_BASE` (`:1337-1340`) is unchanged. The portal's own binding `portal.${appsDomain}` (`:1269-1276`) is unchanged.

7. Dev-gateway. `EDGE_BASE_DOMAIN` (`:1433`): `appHostsDomain`; `envVars` (`:1419`, closing `]` at `:1453`) gains `EDGE_CONTROL_DOMAIN` through the same `splitEdgeEnv`-style variable (only the control domain, not the redirect flag: the dev-gateway serves no apps). Its binding `dev-api.${appsDomain}` (`:1393-1400`) is unchanged.

8. `modules/dns.bicep`. Add two parameters and gate the records; the file header comment gets two sentences on the two-zone layout.
   ```bicep
   @description('Add the control-plane records (auth, portal, dev-api). False for a hosted-apps zone, which holds only the wildcard and the verification record.')
   param hostsControlPlane bool = true

   @description('Add the wildcard record. False for a control zone once the legacy app redirect is off: auth, portal and dev-api have their own records.')
   param hostsWildcard bool = true
   ```
   `wildcardRecord` (`:36`) gets `= if (hostsWildcard)`; `authRecord` (`:47`) and `portalRecord` (`:58`) get `= if (hostsControlPlane)`; `devApiRecord` (`:73`) becomes `= if (deployDevGateway && hostsControlPlane)`; the `asuid` record is unchanged. Then in `main.bicep`:
   ```bicep
   module dns 'modules/dns.bicep' = {
     name: 'dns'
     params: {
       appsDomain: appsDomain
       edgeStaticIp: appsEnv.outputs.staticIp
       domainVerificationId: domainVerificationId
       deployDevGateway: deployDevGateway
       hostsWildcard: !hostedSplit || legacyAppRedirect
     }
   }
   module dnsHosted 'modules/dns.bicep' = if (hostedSplit) {
     name: 'dns-hosted'
     params: {
       appsDomain: hostedAppsDomain
       edgeStaticIp: appsEnv.outputs.staticIp
       domainVerificationId: domainVerificationId
       hostsControlPlane: false
     }
   }
   ```
   The same environment `domainVerificationId` goes into both zones' `asuid` record (the verification id belongs to the Container Apps environment).

9. Certbot, second instance. The existing `module certbot` (`:1485`) is unchanged except that it can use `certbotEnabled` in its condition if you want one name for it (optional; do not change its parameters). Add:
   ```bicep
   module certbotHosted 'modules/certbot.bicep' = if (hostedSplit && certbotEnabled) {
     name: 'certbot-hosted'
     params: {
       location: location
       // Distinct identity and job names (certbot.bicep:80, :148). Short on purpose: an ACA job name is
       // limited to 32 characters, and <namePrefix>-ap-certbot must fit.
       namePrefix: '${namePrefix}-ap'
       appsDomain: hostedAppsDomain
       wildcardCertName: hostedCertName
       acaEnvName: '${namePrefix}-apps-env'
       acaEnvId: appsEnv.outputs.environmentId
       edgeAppName: '${namePrefix}-edge'
       portalAppName: ''
       devGatewayAppName: ''
       image: '${imageRegistry}/helix-certbot:${imageTag}'
       acmeEmail: acmeEmail
       acmeServer: acmeServer
       // The control instance runs at 03:00 UTC. Both jobs add and bind hostnames on the same edge app, so
       // offset the second by half an hour rather than racing two writes to one Container App.
       cronExpression: '30 3 * * *'
     }
     dependsOn: [ edgeApp, dnsHosted ]
   }
   ```
   Copy `acaEnvName`, `edgeAppName` and `image` from the existing instance exactly; if the existing block differs from this sketch, the existing block wins. Rename the file-header sentence in the module comment only if it says "one cert" in a way that is now wrong; otherwise leave the module alone.

10. Parameter files. In `main.bicepparam` and `main.bootstrap.bicepparam`, add a commented example next to `wildcardTlsBound` (`main.bicepparam:64`, `main.bootstrap.bicepparam:78`), in the style of the existing commented examples:
    ```
    // Hosted apps on a separate domain (see the hostedAppsDomain description in main.bicep).
    // param hostedAppsDomain = 'apps.example.test'
    // param hostedAppsTlsBound = false
    // param legacyAppRedirect = false
    ```
    Do not add an active line; the live installs' parameter files are not touched (scope limit), and these two are templates in this repository.

11. Compile checks, from the dev container, saving every output in `results/`:
    - `just infra build` (it also builds both parameter files and `infra/entra`). Must pass with the parameters unset.
    - `az bicep build --file infra/azure/main.bicep --stdout > "$RESULTS/main.after.json"`, then diff against the baseline normalizing the generator hashes: `diff <(jq -S . before.json | grep -v templateHash) <(jq -S . after.json | grep -v templateHash)`. Annotate each hunk against criteria (a) to (e) in Requirements and put the annotated diff in `results/ct9-compile-diff.md`.
    - A "set" compile: copy `main.bicepparam` to a scratch file in `results/` with the three parameters set (`hostedAppsDomain = 'apps.example.test'`, `hostedAppsTlsBound = true`, `legacyAppRedirect = true`) and run `az bicep build-params --file <scratch> --stdout`. This proves the parameters parse and the template accepts them; it does not evaluate the expressions. Then read the compiled `variables`, the edge `customDomains` and `envVars` expressions and the two `dns` and two `certbot` module entries in the JSON and write one line each in `results/` saying what they evaluate to for the set parameters (the reading is the evidence, and it is not an Azure what-if).
    - Compile `modules/dns.bicep` and `modules/certbot.bicep` alone as a sanity check.

12. Documentation of the new parameters is CT-10 (`infra/azure/README.md`, `apps/docs/src/deploy/configuration.md`, ADR-0044 amendment). In this task the parameter descriptions and code comments carry the constraints only; no change IDs and no `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `./check-and-lint.sh` passes in the dev container.
- [ ] `just infra build` passes, with the three parameters unset.
- [ ] The compiled-template diff against `main` is in `results/ct9-compile-diff.md`, every hunk annotated, and none changes an existing value; the "set" parameter file compiles; the compiled expressions for the set case are read and summarized.
- [ ] `hostedAppsDomain` (default `''`), `hostedAppsTlsBound` and `legacyAppRedirect` exist with descriptions that carry the unverified label; with the split configured the edge has both `EDGE_BASE_DOMAIN` and `EDGE_CONTROL_DOMAIN`, the portal both `APP_PUBLIC_BASE` and `CONTROL_PUBLIC_BASE`, the edge two `customDomains`, the apps zone only `*` and `asuid`, and the two certbot instances have distinct identity and job names; `issue-and-bind.sh` and `certbot.bicep` have no diff.
- [ ] `just dev smoke` is not required (no edge, portal or egress code changed); say so in `results/`.
- [ ] **Unverified in Azure**, stated in the parameter descriptions and in `results/`, and carried into the operator rollout notes (CT-10): whether one Container App accepts two wildcard custom domains on different certificates; certificate issuance and binding for the second domain; whether two certbot jobs adding and binding hostnames on one edge app collide at runtime (the half-hour offset is a precaution, not a proof); the ADR-0044 what-if canary with two bindings (a what-if on a gated install must never show `Delete properties.configuration.ingress.customDomains`); DNS delegation of both zones and the Public Suffix List entry; whether an empty or omitted environment entry is accepted exactly as assumed; the 32-character job-name limit for long `namePrefix` values; and certbot's ACME, Resource Manager and Entra reachability behind the firewall tier, which also depends on EG-6 having landed.
- [ ] Committed with `fest commit -m "CT-9: Bicep, DNS and certbot instances for the apps domain"`.
