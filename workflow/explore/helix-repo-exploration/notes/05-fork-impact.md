# Fork impact

_Scope:_ What in `projects/helix` at `792557a` is tied to the original owner (AZX PBC, the GitHub organization `AZX-PBC-OSS`, the `azxlabs.io` domain, the `@azx-pbc` npm scope, and the `ghcr.io/azx-pbc-oss` image namespace), and what that means now that `origin` is the private `lancekrogers/helix`.

_Method:_ `git remote -v`, `git ls-files` piped to `grep -o` and `grep -l` for counts, and `grep -n` for locations. `cat -n` or `sed -n` on the infra parameter files, both workflows, `docs.yml`, the docs site config, `packages/cli/package.json`, `LICENSE`, `SECURITY.md`, and the Shell component. `gh issue list -R AZX-PBC-OSS/helix --state open` (read-only). Counts cover tracked files only. Nothing in the repository was changed.

## Summary

The fork carries the original owner's identity in five places: the `@azx-pbc` npm scope (26 package names), the `azxlabs.io` domain (352 occurrences, including the production apps domain and the dev hostnames), the `AZX-PBC-OSS` GitHub organization (GitHub Pages, links, and the one published package), the `ghcr.io/azx-pbc-oss` image namespace (the default for the Azure deploy), and the Azure and Entra names in the parameter files. Local development and the CI build and test path do not depend on these, so the fork can still be built and checked. Publishing the CLI, deploying to Azure at the configured domain, and pulling images with the default settings all depend on the owner's identity. Three things need a decision before the team owns this: where the domain and Azure target live, whether the CLI keeps publishing under `@azx-pbc`, and whether the fork keeps a fetch-only `upstream` remote to receive the four open upstream issues.

## What already meets the bar

- **No real tenant, subscription, or client identifiers are committed.** Subscription and tenant come from the deployment context: `infra/azure/main.bicep:154` (`tenant().tenantId`), `infra/azure/modules/certbot.bicep:183` (`subscription().subscriptionId`), and `infra/azure/modules/keyvault.bicep:47`. The example Key Vault references use all-zero placeholders (`infra/azure/main.bicepparam:146-161`).
- **No private keys are tracked.** A grep for `BEGIN PRIVATE KEY` and `BEGIN RSA` across tracked non-test files returned nothing. The only tracked env file is `.env.example`, and `.gitignore:27-29` ignores the rest.
- **The CLI publishes without a long-lived npm token.** `.github/workflows/release-cli.yml:3-6` says there is no `NPM_TOKEN` and that the trust relationship is registered against the workflow file. The workflow also checks that the tag matches the package version (`release-cli.yml:71-82`) and that the tarball contains no workspace-only specifiers (`:107-117`).
- **Production secrets stay in Key Vault, and the migration job holds no credential.** `infra/azure/README.md:745-751` says the migration job reads `postgres-admin-password` from Key Vault with a managed identity that has only `Key Vault Secrets User`.
- **Only one git remote is configured.** `git remote -v` shows `origin` pointing at `git@github.com:lancekrogers/helix.git` and nothing else. Nothing can push to the upstream by accident.

## Findings

### FORK-1 The `@azx-pbc` npm scope and the public CLI publish path

- **Severity:** High. **Status:** Confirmed for the names and the configuration. Hypothesis for the publish failure.
- **Area:** Packaging and distribution.
- **What:** Every package name uses the `@azx-pbc/` scope. The one publishable package is `@azx-pbc/helix-cli`, version `0.4.0`, published to public npm. Its `repository.url` points at `AZX-PBC-OSS/helix`. The npm trusted publisher is documented as registered to `AZX-PBC-OSS/helix`.
- **Evidence:**
  - `grep -n '"name": "@azx-pbc' <each package.json>` lists 26 package names: `apps/*` (8), `examples/*` (12), and `packages/*` (6). Counting `"@azx-pbc/"` occurrences in the `package.json` files gives 67 (`grep -rn "@azx-pbc/" --include=package.json --exclude-dir=node_modules . | wc -l`). Across all tracked files the string appears 850 times in 410 files.
  - `packages/cli/package.json:2-3` (name and version), `:5` (`"license": "MIT"`), `:8` (repository URL `git+https://github.com/AZX-PBC-OSS/helix.git`), `:19-21` (`publishConfig.access: public`).
  - `packages/cli/README.md:216` says the trust relationship is with `AZX-PBC-OSS/helix`.
  - `docs/adr/0032-cli-naming-and-distribution.md:24` gives the reason for public npm over GitHub Packages (the package scope must match the owning organization). `:44-48` describes the trusted-publisher registration and the placeholder version published by hand.
- **Why it matters:** A `cli-v*` tag pushed to the fork would run `release-cli.yml`. If the npm trusted publisher is bound to `AZX-PBC-OSS/helix`, npm will reject the OIDC token and the publish fails (Hypothesis, not tested). Separately, publishing to the `@azx-pbc` scope requires membership in that npm organization (Hypothesis, npm ownership not checked). Either way, the fork cannot publish the CLI under its current name without the original owner's cooperation. A fork that deletes the publish step loses nothing else; a fork that renames the scope touches about 67 `package.json` references, the lockfile, the docs, and the ADR.
- **Recommendation:** The owner chooses one of three paths. (a) Keep publishing upstream only, and disable or guard `release-cli.yml` in the fork. (b) Rename the scope to one the owner controls, update the 26 `package.json` names and every import, re-register the trusted publisher against `lancekrogers/helix` with the same workflow filename, and then publish. (c) Stop publishing from the fork until the scope question is settled. Do not rename the scope silently: ADR-0032 treats it as a deliberate choice.

### FORK-2 The `azxlabs.io` domain: production apps domain and dev hostnames

- **Severity:** High. **Status:** Confirmed.
- **Area:** DNS, TLS, and identity redirects.
- **What:** `azxlabs.io` appears 352 times in 96 tracked files. The production apps domain is `azx.helix.azxlabs.io`. The dev stack uses `*.local.helix.azxlabs.io`, and the compose comment says that name is "a platform-owned wildcard that resolves to 127.0.0.1" (replacing `localtest.me`). The Entra redirect URIs and the certificate job both depend on the same zone.
- **Evidence:**
  - Counts by area: `apps/` 217 (34 files in `apps/edge`), `docs/` 55, `infra/` 23, `examples/` 14, `.devcontainer/` 8, `scripts/` 4, `.claude/` 4, `packages/` 3, `.github/` 1.
  - Production: `infra/azure/main.bicepparam:18` and `main.bootstrap.bicepparam:32` set `appsDomain = 'azx.helix.azxlabs.io'`. `infra/entra/main.bicepparam:12-13` sets the edge and portal redirect URIs to `auth.azx.helix.azxlabs.io` and `portal.azx.helix.azxlabs.io`.
  - Delegation: `infra/azure/README.md:847-849` says to add NS records for `azx.helix` in the parent `azxlabs.io` Cloudflare zone. The Let's Encrypt DNS-01 challenge needs that zone (`infra/azure/README.md:857-859`).
  - Dev: `.devcontainer/docker-compose.yml:87-98`, `scripts/stack-env.mjs:27`, `scripts/dev-vendor-tls.mjs:31`.
  - `azx-labs.com`: zero occurrences in tracked files. It appears only in the title of upstream issue #16, "Untrusted apps share the registrable domain (azx-labs.com) with portal/auth — use a separate eTLD+1" (`gh issue list`, output below). That suggests a second AZX domain existed or was planned. Hypothesis, not checked.
- **Why it matters:** A fork cannot deploy to the configured production domain without control of `azxlabs.io` DNS. Local dev also resolves a name that the fork owner does not control, so a DNS change upstream would break every developer's dev stack. The production domain is also baked into the Entra redirect URIs and the wildcard certificate name, so a domain change touches identity configuration, not only DNS.
- **Recommendation:** The owner decides whether the fork keeps `azxlabs.io`. If yes, confirm who controls the zone and that the owner can add the NS delegation. If no, pick a domain the owner controls and move it in one change: the about 350 references, the Entra redirect URIs, the Cloudflare delegation, and the wildcard certificate name. For dev, move the hostnames to a name the owner controls, or to a host-only setup that does not need public DNS. Keep the dev change separate from the production change.

### FORK-3 Azure and Entra names and parameter files

- **Severity:** High. **Status:** Confirmed for the values. Hypothesis for name collisions.
- **Area:** Infrastructure as code.
- **What:** The committed parameter files set one deployment's names. The resource group, Key Vaults, storage account, PostgreSQL server, and Entra application names all use the `helix-prod` prefix. These are names, not secrets, but they identify the original owner's deployment shape. A fork that deploys into its own subscription must edit every literal.
- **Evidence:**
  - `infra/azure/main.bicepparam:5-11`: `namePrefix = 'helix-prod'`, `location = 'eastus2'`, `storageAccountName = 'helixprodbundles'`, `platformVaultName = 'helix-prod-kvp'`, `connectionsVaultName = 'helix-prod-kvc'`, `delegatedVaultName = 'helix-prod-kvd'`, `postgresServerName = 'helix-prod-pg'`. The same values appear in `main.bootstrap.bicepparam:19-25`.
  - `infra/azure/main.bicepparam:144-145` says: "Replace the subscription id / RG / vault name literals with your install's." The next lines hard-code `'00000000-0000-0000-0000-000000000000'` and `'rg-helix-prod'` in each `az.getSecret` call (`:146-161`).
  - `infra/entra/main.bicepparam:6` sets `namePrefix = 'helix-prod'`. `infra/entra/main.bicep:83-84`, `163-164`, and `272-273` create the applications `helix-prod-edge`, `helix-prod-portal`, and `helix-prod-cli`.
  - The GUIDs in the modules (for example `infra/azure/modules/rbac.bicep:56-59`, `certbot.bicep:76-77`, `foundry.bicep:62-63`) are not subscription or tenant identifiers. Several look like Azure built-in role IDs. Hypothesis, not checked against Microsoft's list.
- **Why it matters:** Storage account and Key Vault names are globally unique. If the owner's subscription already uses `helixprodbundles` or `helix-prod-kvp`, the deploy fails. A team inheriting the fork has to find every literal, which is easy to miss, and the parameter file comment makes that a manual step.
- **Recommendation:** Keep the names in one place. Either move them into a non-committed environment file, or derive them from `namePrefix` the way the rest of the template already does. Confirm the subscription, the region, and the prefix before the first apply. Keep the zero-GUID placeholders in the committed file.

### FORK-4 GHCR image namespace and package visibility

- **Severity:** High. **Status:** Confirmed for the mismatch. Hypothesis for the visibility default.
- **Area:** Container images and the deploy path.
- **What:** CI publishes to the namespace of the repository owner. For this fork that is `ghcr.io/lancekrogers/helix-<app>`. The Azure templates and the docs default to `ghcr.io/azx-pbc-oss`. The template pulls anonymously, which needs public packages.
- **Evidence:**
  - `.github/workflows/ci.yml:497` builds the image name from `${{ github.repository_owner }}`. `ci.yml:525` pushes on every run that is not a pull request, so a manual dispatch from the fork pushes to `ghcr.io/lancekrogers/...`.
  - Defaults that point to `ghcr.io/azx-pbc-oss`: `infra/azure/main.bicep:285`, `main.bicepparam:33`, `main.bootstrap.bicepparam:47`, `infra/azure/modules/certbot.bicep:61`, `containerapp.bicep:38`, `migrate-job.bicep:48` (comment examples).
  - Docs: `apps/docs/src/deploy/configuration.md:125`, `getting-started.md:273` and `:307`, `database.md:73`. `infra/azure/README.md:661-663` and `:683`.
  - `infra/azure/README.md:672-677`: "The bicep does an anonymous pull by default... which requires the three packages to be **public**."
  - `HELIX_IMAGE_REGISTRY` overrides the default (`main.bicepparam:33`), so the fix is configuration, not code. Hypothesis: packages in a private repository default to private, which would break the anonymous pull.
- **Why it matters:** A deploy that follows the docs pulls from the upstream namespace, not from the images the fork built. A deploy that follows the fork's CI needs the override and public packages. Either way, the team has to know which image is running. Making the packages public also publishes the platform code's built images, which the upstream already does.
- **Recommendation:** Decide the image source before the first deploy. Option 1: keep pulling upstream images by tag or digest and build nothing for production. Option 2: publish from the fork, set `HELIX_IMAGE_REGISTRY` in the deployment environment, and set package visibility deliberately. Record the chosen digest in the deploy record.

### FORK-5 GitHub Pages and the docs site

- **Severity:** Medium. **Status:** Confirmed for the configuration. Hypothesis for the plan requirement.
- **Area:** Documentation publishing.
- **What:** The docs workflow deploys to GitHub Pages on manual dispatch. The site's base path and sitemap hostname point at the upstream organization.
- **Evidence:**
  - `.github/workflows/docs.yml:3-4` says the site is at `https://azx-pbc-oss.github.io/helix/`. `docs.yml:9-10` gives the one-time setup as `gh api repos/AZX-PBC-OSS/helix/pages`.
  - `apps/docs/.vitepress/config.ts:5` (comment), `:19` (`base: "/helix/"`), `:23` (sitemap hostname `https://azx-pbc-oss.github.io/helix/`), `:71` (GitHub social link to `AZX-PBC-OSS/helix`).
  - `apps/docs/README.md:3` and `:42` reason about the upstream origin and robots files.
  - Hypothesis: GitHub Pages for a private repository requires a paid plan. Not checked.
- **Why it matters:** If Pages is enabled on the fork, the site would build at `lancekrogers.github.io/helix/` while the sitemap and the social link still point at the upstream host. Search engines would index the wrong host. If Pages is not available, the job fails on deploy.
- **Recommendation:** Either disable `docs.yml` in the fork, or set the base path, the sitemap hostname, and the social link from one variable. Confirm the plan before enabling Pages.

### FORK-6 Hard-coded upstream links in product code, the security contact, and the docs

- **Severity:** Medium. **Status:** Confirmed.
- **Area:** User-facing links and vulnerability reporting.
- **What:** The portal UI links to the upstream repository. The security policy sends vulnerability reports to the upstream advisory form. The docs and the CLI README link to upstream throughout.
- **Evidence:**
  - `apps/portal-web/src/components/Shell.tsx:62` sets `REPO_URL = "https://github.com/AZX-PBC-OSS/helix"`. `apps/portal-web/src/test/help-modal.test.tsx:144` and `:149` assert the upstream URL and the upstream issues URL, so changing the link requires changing the test.
  - `SECURITY.md:20` links to `https://github.com/AZX-PBC-OSS/helix/security/advisories/new`. `SECURITY.md:26` and `:41` name the npm package `@azx-pbc/helix-cli`.
  - Upstream links in docs: 31 occurrences of `github.com/AZX-PBC-OSS` across 18 tracked files (`apps/docs/src/contributing.md` (6), `apps/docs/src/deploy/configuration.md` (4), `apps/docs/src/index.md` (3), `apps/docs/src/deploy/entra-setup.md` (2), `apps/docs/src/deploy/getting-started.md` (2), and others).
  - `examples/helix-help/dist/assets/index-8ZothUb9.js` is a tracked build artifact that contains `azx-pbc-oss`.
- **Why it matters:** A security report sent through `SECURITY.md` goes to the upstream owner's advisory queue, which the fork owner may not watch. Contributor links in the docs send people to the upstream repository for issues and pull requests. A tracked build artifact with the old name is a hygiene issue, and it will change again on the next build.
- **Recommendation:** Change `SECURITY.md` to a channel the fork owner watches, or state that reports go upstream and name who triages them. Make `REPO_URL` a single constant and update the test in the same change. Replace the doc links once the repository location is final. Rebuild the helix-help example and stop tracking the `dist` directory, or document why it is tracked.

### FORK-7 No upstream remote and four open upstream issues

- **Severity:** High. **Status:** Confirmed.
- **Area:** Upstream relationship and security backlog.
- **What:** The fork has one remote, `origin`. There is no `upstream`, so there is no way to fetch fixes from `AZX-PBC-OSS/helix`. Four issues are open upstream: three are labeled `security` and `important`.
- **Evidence:**
  - `git remote -v` lists only `origin`.
  - `gh issue list -R AZX-PBC-OSS/helix --state open --limit 100` returned:
    - `#43` (open, last listed 2026-10-06): "Feature request: Make it stupidly easy to deploy from claude/codex". No labels.
    - `#16` (open, 2026-09-22): "Untrusted apps share the registrable domain (azx-labs.com) with portal/auth — use a separate eTLD+1". Labels: `security`, `important`.
    - `#6` (open, 2026-06-26): "Attested instruction binds only the origin (method/path/query/body unsigned); no aud or key rotation". Labels: `security`, `important`.
    - `#5` (open, 2026-06-25): "Edge↔egress hop is plain HTTP (no TLS in the seam)". Labels: `security`, `important`.
  - `gh issue list -R lancekrogers/helix --state open` returned no open issues.
- **Why it matters:** The fork inherits three open security issues with no route to fix them from upstream. Two of them (#5, #6) concern the edge-to-egress trust path, which the repository describes as the mechanism plane. Issue #16 concerns the app-isolation domain. Whether these apply to the fork's deployment depends on the domain decision in FORK-2 and the deploy in FORK-3. Hypothesis: the fork's code is identical to upstream at `24e4b32` (per the brief), so the issues apply to the fork as written.
- **Recommendation:** Add a fetch-only `upstream` remote, and disable its push URL so nothing can be pushed there by accident. Track the three security issues in the fork's backlog, with an owner for each. Decide whether to fix them in the fork, or to wait for upstream.

- **Coordinator note:** the security review corrects the status of these issues. #5 (plain-HTTP hop) does not describe the deployed state: every internal base URL in the Bicep is `https://` (SEC-11). #6 is partly stale: `aud` and a single-use `jti` burn are implemented, while the query and body are still unsigned and the claims are optional (SEC-5). #16 (shared registrable domain) stands (SEC-1).

### FORK-8 License and copyright holder

- **Severity:** Low. **Status:** Confirmed for the license text. The ownership question is open and needs legal review.
- **Area:** Licensing and attribution.
- **What:** The repository is MIT-licensed, with the copyright holder named as AZX, PBC. The CLI package also declares MIT.
- **Evidence:**
  - `LICENSE:1` ("MIT License") and `LICENSE:3` ("Copyright (c) 2026 AZX, PBC").
  - `packages/cli/package.json:5` (`"license": "MIT"`).
  - Context from the brief: 556 of 564 commits are by one author since 2026-06-11. Not re-verified here.
- **Why it matters:** MIT permits a private fork and modification, provided the copyright notice and the permission notice stay in copies or substantial portions. It does not grant rights to the AZX name or marks. It does not say who owns code that the fork's author wrote, and it does not settle whether AZX, PBC or the author holds the copyright in new commits. Those are questions for the owner's counsel, not a finding from reading the repository.
- **Recommendation:** Keep the `LICENSE` file and the notice unchanged in any copy. Before the team owns the fork, decide and record who holds the copyright in new code, and whether the fork's README says it is a fork of AZX-PBC-OSS/helix.

### FORK-9 CI cost and triggers now bill the owner's account

- **Severity:** Medium. **Status:** Confirmed.
- **Area:** CI/CD cost and process.
- **What:** Automatic triggers are off in all three workflows. The CI workflow still has a comment that justifies its layout by free runners on a public repository. When one dispatch runs, it starts 11 jobs, which bill to the owner's account.
- **Evidence:**
  - `.github/workflows/ci.yml:60-65` (triggers commented out), `docs.yml:15-18`, `release-cli.yml:28-31`.
  - `ci.yml:30-34`: sharding and the early browser lane are justified because "standard GitHub-hosted runners are free and unbilled for public repos," with "Revisit this if the repo goes private." `ci.yml:57-59` says the repo is private and runs bill minutes.
  - One dispatch of `ci.yml` starts `static` (1 job), `test` (3 shards), `browser-lane` (1), `bicep` (1), `package` (1), and `images` (4 matrix jobs): 11 jobs.
- **Why it matters:** The cost model in the comments is the reverse of the current one. The sharding that saves wall-clock time now multiplies billed minutes, and nothing else in the repository reminds the team to check the bill. The triggers being off also means nothing is checked on a pull request.
- **Recommendation:** Decide on the trigger policy and the shard count for a private repository. Update the `ci.yml` comment so it does not describe a public-repository trade-off. Set an Actions spending limit on the account, if the owner wants one.

### FORK-10 Test fixture identities under the old domains

- **Severity:** Low. **Status:** Confirmed. The domain ownership is not checked.
- **Area:** Test and dev fixtures.
- **What:** Dev-IdP fixture users use the email domains `azx.dev` (137 occurrences) and `azx.io` (61 occurrences).
- **Evidence:**
  - `README.md:91-93` lists `alice@azx.dev`, `bob@azx.dev`, and `mallory@azx.dev`. `apps/dev-idp/README.md:26-27` repeats them. `apps/connections-lane/src/world.ts:77` uses `alice@azx.dev`.
  - `apps/portal-web/src/test/approvals-page.test.tsx:21` uses `owner@azx.io`.
- **Why it matters:** The fixtures are only used in dev and tests. The risk is that someone uses a fixture address for a real account, or that the owner later stops holding those domains and the fixtures become claimable. Neither is a current exposure.
- **Recommendation:** Confirm whether the owner holds `azx.dev` and `azx.io`. Either way, use the reserved example domains (`example.com` or `example.test`) in new fixtures.

## Missing for production and staff-level quality

- **A documented upstream sync process.** There is no remote, no sync note, and no record of which upstream commit the fork started from beyond the seed notes. A team that inherits the fork needs one page that says what to pull, how often, and who decides.
- **Configuration that is not tied to the owner.** The domain, the scope, the image namespace, and the Azure names are literals spread across the repository (the domain alone appears in 96 tracked files). Each one needs an owner decision (section below) before a team can run the fork as its own.
- **A security contact the fork owner watches.** `SECURITY.md` routes to upstream (FORK-6).
- **An owner for the Azure subscription, the Entra tenant, and the DNS zone**, recorded in one place. Today those are implied by the parameter files and by the runbooks.

## Open questions

- Who controls the `azxlabs.io` zone, and can the owner add the NS delegation that the production deploy needs (FORK-2)?
- Is `azx-labs.com` an AZX domain the owner still holds? Issue #16 names it, and the repository does not use it (FORK-2).
- Does the npm `@azx-pbc` organization include the owner's account, and is the trusted publisher on npm bound to `AZX-PBC-OSS/helix` (FORK-1)? Hypothesis until checked on npm.
- Is GitHub Pages available on the owner's plan for a private repository (FORK-5)?
- Who holds the copyright in code committed to the fork since 2026-06-11 (FORK-8)? This needs counsel.
- Are the Azure names `helix-prod`, `helixprodbundles`, and the Key Vault names free in the target subscription (FORK-3)?

## Decisions the owner must make

1. **Upstream relationship.** Add a fetch-only `upstream` remote with push disabled, and track issues #5, #6, and #16 in the fork. Recommendation: yes.
2. **npm scope and CLI publishing.** Keep `@azx-pbc` and publish only upstream, rename the scope and re-register the trusted publisher, or stop publishing from the fork (FORK-1).
3. **Domain.** Keep `azxlabs.io` with confirmed DNS control, or move production and dev hostnames to a domain the owner controls (FORK-2).
4. **Azure target.** Which subscription, tenant, region, and name prefix the fork deploys to (FORK-3).
5. **Image source.** Pull upstream images by digest, or publish from the fork and set `HELIX_IMAGE_REGISTRY` with a visibility decision (FORK-4).
6. **Documentation publishing.** Retire `docs.yml` in the fork, or host Pages under the fork with the base path and sitemap host changed (FORK-5).
7. **Vulnerability reporting.** Change `SECURITY.md` to a channel the owner watches, or keep upstream as the channel with a named triage owner (FORK-6).
8. **CI policy.** Keep the triggers off, or set them for pull requests. Decide the shard count and any spending limit (FORK-9).
9. **Licensing and attribution.** Confirm the copyright holder for new code and how the fork describes its origin (FORK-8).
