# CT-3 result: enforce the tightened img-src and object-src

**Result: done, with a measurement mode added (coordinator decision, logged in `decisions.md`).** The edge now has three image-policy modes. `apps/edge/src/serving/csp.ts` uses one private builder, and `applyAppCsp` is the single call at every site.

| Mode | Enforced `Content-Security-Policy` | Report-Only |
| --- | --- | --- |
| Default | `img-src 'self' data: blob:` plus approved origins and `EDGE_IMG_SRC_EXTRA`, `object-src 'none'` | none |
| `EDGE_IMG_SRC_REPORT_ONLY=true` (`imgSrcReportOnly`) | the previous policy (`img-src https: data: blob:` plus approved origins, no `object-src`), byte-identical to CT-2's enforced header | CT-2's tight policy, byte-identical |
| `EDGE_IMG_SRC_ALLOW_ALL=true` (`imgSrcAllowAll`) | `img-src https: data: blob:` plus approved and extra origins, `object-src 'none'` | none |
| Both true | edge refuses to boot, naming both variables | — |

**Why the measurement mode.** The task removed the Report-Only path in every mode, assuming the CT-2 release would run alone for a measurement window first. This fork is delivered as one `main`: CI is off, images are built per commit by whoever deploys, and the domain split lands after this. An operator taking `main` would go straight to enforcement. Reusing `ALLOW_ALL` as the measurement mode would fill a permanently relaxed install's Violations screen with report rows. The design's Part 2 tests ("only the enforced header after CT-3") hold for the default and allow-all modes.

**Origin handling.** `originSources` now drops non-`https:` and wildcard-host origins, for `connect-src` as well as `img-src`. The manifest accepts any URL (`z.url()`). Dropping `http:` origins changes nothing that works, because browsers block mixed-content `fetch()` from an `https:` app page and upgrade mixed-content images. Dropping a wildcard host such as `https://*.a.example` closes a widening the old code allowed. The measurement mode is byte-identical to CT-2 for `https:` origins; it differs only on those dropped forms.

## Coordinator fixes

- **Plan change IDs in code and docs, 13 places.** The agent named the measurement builder `buildCt2EnforcedAppCsp` and the mode `"ct2-enforced"`, and wrote "CT-2 dual headers" in `config.ts`, `configuration.md`, the edge README, ADR-0009, `edge-serving.md`, the `main.bicep` description and a test name. These are renamed to `buildLegacyEnforcedAppCsp` and `"legacy"`, and the wording now describes the mode itself. `git grep -iE "ct2|ct-2|ct-3|ct3"` over the source trees finds nothing.
- **Formatting** after the renames (prettier).

## Evidence (coordinator)

- **Byte-identity:** CT-2's `csp.ts` from `836673e`, run against the new `buildLegacyEnforcedAppCsp` and `buildMeasurementReportOnlyCsp` for four origin and extra combinations. Both the enforced and the Report-Only strings are identical in all four.
- **Gate:** `./check-and-lint.sh`, 241 of 241 test files, 3551 tests. `just infra build` passes. In the built template, both booleans are `if(parameters(...), 'true', 'false')`, never `string(bool)`.
- **Real-browser smoke** (`HELIX_SMOKE_CHROME`, Chromium 1248, default mode), 37 passed, 0 failed, 0 skipped:
  - "enforced CSP blocks remote image and records violation for smoke-csp: 7 report(s); disposition="enforce"", with `#remote` complete and `naturalWidth` 0, and `#inline` loading;
  - "granted origin appears in smoke-csp CSP" (psql grant, header polled, grant removed).
  - This closes the `disposition` hypothesis for both values in Chromium: `report` in CT-2, `enforce` here.
- **Connections lane** (`just check lane`, real browser): 10 passed. The consent popup journeys work under the tight policy.
- **Agent's negative check:** forcing the default branch to the open `img-src` failed 12 tests in `csp.test.ts` and `app.test.ts`, then it was restored.
- **Tests:**
  - The mode matrix in `csp.test.ts`, `app.test.ts` and `serviceWorker.test.ts` (the report-only arm keeps CT-2's pinned strings).
  - The strict parsing and both-true refusal in `config.test.ts`.
  - The portal route test: `img-src` resolves once the origin is granted; `object-src` and `data` never do.
  - `approval.test.ts` unchanged.
- **Docs:**
  - `SECURITY.md`, the ADR-0009 amendment (the open question trimmed to SRI and per-app CDNs), `docs/platform-architecture.md` (§ img-src and the threat-model row), `edge-serving.md`, observability (`report` only in measurement mode), `configuration.md`, the edge README and `TODO.md` (the `object-src` clause removed).
  - `SKILL.md`: the CSP block, and agents told to inline or bundle images. `quickstart.md` was regenerated and shows the new block.
  - `updates.md` gains "Upgrading to the tightened image policy": set `imgSrcReportOnly` before rolling the edge on an existing install, read the Violations screen, pre-grant or use `EDGE_IMG_SRC_EXTRA` (never an image proxy), then remove it. One-org installs use `EDGE_IMG_SRC_ALLOW_ALL`. Both parameter files carry commented lines.
- **Anchor correction:** the design cited `SECURITY.md:56-57` for the open `img-src`. Those lines are reference-deployment hostnames; the relevant text is the "Relaxed CSP directives" bullet and architecture §10.
- **Design gap:** the design's file list omitted `main.bicep`. `imgSrcAllowAll` and `imgSrcReportOnly` sit beside CT-2's `imgSrcExtra`.

## Unverified

- **In Azure:** that Container Apps passes `EDGE_IMG_SRC_REPORT_ONLY`, `EDGE_IMG_SRC_ALLOW_ALL` and `EDGE_IMG_SRC_EXTRA` through as set, and the rollout on a live install.
- **Untested anywhere:** WebRTC ICE and DNS prefetch or preconnect under this policy (the docs say so), and image blocking in Firefox and Safari.

## Executor

cursor-agent, `composer-2.5`, 113 tool calls. Coordinator fixes as listed.
