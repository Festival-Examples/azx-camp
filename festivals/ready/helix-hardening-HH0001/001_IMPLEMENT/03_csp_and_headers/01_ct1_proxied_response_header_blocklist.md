---
fest_type: task
fest_id: 01_ct1_proxied_response_header_blocklist.md
fest_name: ct1 proxied response header blocklist
fest_parent: 03_csp_and_headers
fest_order: 1
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:54:29.41863-06:00
fest_tracking: true
---

# Task: ct1 proxied response header blocklist

## Objective

Stop a proxied upstream from setting `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints` or `nel` on the app-origin response, by adding those seven names to the one shared blocklist that egress and the edge gateway both read. Implements CT-1 from 02-app-containment.md ("Part 3", finding SEC-13).

## Requirements

- [ ] No prerequisite task. `02_ct2_report_only_csp_and_report_counter.md` follows this one in order only; there is no code dependency.
- [ ] `RESPONSE_HEADER_BLOCKLIST` in `packages/shared/src/fetch.ts` contains the seven new names, all lowercase, appended after the eleven that are there now (`set-cookie`, `set-cookie2`, `authorization`, `location`, `transfer-encoding`, `connection`, `keep-alive`, `proxy-authenticate`, `proxy-authorization`, `trailer`, `upgrade`). Nothing is removed or reordered.
- [ ] Egress (`apps/egress/src/proxy.ts`) does not copy any of the seven onto its response to the edge, for a keyless call and for a connection-backed call.
- [ ] The edge gateway (`apps/edge/src/gateway/fetch.ts`) does not copy any of the seven onto the response it sends to the app, even when its egress provider returns them. The edge enforces this itself because the two hops do not trust each other. The dev-gateway reuses the same handler, so it is covered by the same test.
- [ ] Headers the app relies on still pass on both hops: `etag`, `content-type`, `retry-after`, a `x-ratelimit-*` header, `cache-control`, and `link`. `www-authenticate` also still passes (the docblock at `packages/shared/src/fetch.ts:104` keeps it on purpose).
- [ ] Failure path: an upstream that sends all seven at once, plus `link` and a benign header, produces a response with none of the seven and with `link` and the benign header intact. Header-name case does not matter (Node lowercases on the way in; the shared test asserts the list itself is lowercase so the `Set` lookups in both consumers keep matching).
- [ ] `link` is deliberately not stripped: browsers do not act on a `Link` header in a `fetch()` response, so stripping it gives no protection, and it would break `rel="next"` pagination that apps use against vendors such as the GitHub API. It must keep passing through on all three layers (assertions in steps 4, 5 and 6). The design listed it; it was dropped at task-writing time for this reason.
- [ ] No new span, metric or attribute on either hop. `apps/egress/src/spanAttributes.test.ts` and `apps/edge/src/spanRedaction.test.ts` are not touched.
- [ ] Nothing in this change is Azure-specific.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b ct-1-proxied-response-header-blocklist`.

2. Read the three places that use the list before editing:
   - `packages/shared/src/fetch.ts:100-122`: the docblock and `RESPONSE_HEADER_BLOCKLIST` (11 names today).
   - `apps/egress/src/proxy.ts:79` builds `RESPONSE_BLOCKED = new Set(RESPONSE_HEADER_BLOCKLIST)`. The copy loop is at `proxy.ts:666-675`; it adds the per-recipe header names to the set and skips every name in it.
   - `apps/edge/src/gateway/fetch.ts:73` builds its own set from the same list plus `OUTCOME_HEADER` and `content-length`. The copy loop is at `gateway/fetch.ts:406-408`.

   Both consumers build their set from the shared array at module load, so the one edit in step 3 reaches both. No change to `proxy.ts` or `gateway/fetch.ts` is needed.

3. Edit `packages/shared/src/fetch.ts`. Append to the array at line 110, and extend the docblock above it (lines 100-109) with a short paragraph. Keep the comment to the constraint:

```ts
  "upgrade",
  // Response-side policy headers. They are inert on a fetch() response, but the
  // proxy copies headers verbatim onto the app origin, so an approved upstream
  // could otherwise set them there: clear-site-data runs against the app's own
  // origin (cookies, storage), and the CSP and reporting headers are the
  // app origin's to set, not a vendor's. Keep this a denylist; an allowlist
  // would drop headers apps rely on (etag, retry-after, rate-limit headers).
  "clear-site-data",
  "content-security-policy",
  "content-security-policy-report-only",
  "refresh",
  "report-to",
  "reporting-endpoints",
  "nel",
];
```

   Do not cite this plan's change IDs or any `workflow/` path in comments. ADR numbers and file names are fine.

4. Shared test, `packages/shared/src/fetch.test.ts`. The file has no blocklist test today. Import `RESPONSE_HEADER_BLOCKLIST` from `./fetch.js` (line 2 imports from there already) and add a `describe("RESPONSE_HEADER_BLOCKLIST", ...)` in the style of the `FETCH_ERROR_CODES` block at lines 21-24:
   - `pins the full list, in order`: `expect(RESPONSE_HEADER_BLOCKLIST).toEqual([...the 11 existing, ...the 7 new])`. Write both groups out as literals so a removal or a typo fails.
   - `is entirely lowercase and has no duplicates`: both consumers look names up in a `Set` of lowercase keys.
   - `it.each` over the seven new names: `is in the list`.
   - `leaves the headers apps rely on alone`: `etag`, `content-type`, `cache-control`, `retry-after`, `link`, `www-authenticate`, `x-ratelimit-remaining`, `x-ratelimit-reset` are not in the list.

5. Egress test, `apps/egress/src/proxy.test.ts`. The fake upstream is created in the `beforeAll` at line 31, with a `/throttle` route at line 36 that sets `retry-after`. Add a second route beside it that sets all seven names, `link` and the benign ones:

```ts
    if (req.url === "/leaky-headers") {
      res.writeHead(200, {
        "content-type": "application/json",
        etag: '"v1"',
        "retry-after": "30",
        "x-ratelimit-remaining": "41",
        "clear-site-data": '"cookies", "storage"',
        "content-security-policy": "default-src 'none'",
        "content-security-policy-report-only": "default-src 'none'",
        refresh: "0; url=https://evil.example/",
        "report-to": '{"group":"x","max_age":1,"endpoints":[{"url":"https://evil.example/r"}]}',
        "reporting-endpoints": 'x="https://evil.example/r"',
        nel: '{"report_to":"x","max_age":1}',
        link: '<https://evil.example/p2>; rel="next"',
      });
      res.end("{}");
      return;
    }
```

   Add the tests inside `describe("egress /proxy", ...)` (starts at line 136), next to the 429 test at line 158. Reuse `makeApp(true)`, `mint({ origin })` and the headers shape that test uses (`INSTRUCTION_HEADER`, `TARGET_HEADER` = `${origin}/leaky-headers`, `METHOD_HEADER`):
   - `it.each(NEW_HEADERS)("strips %s from the upstream response", ...)`: one proxied GET, `expect(res.headers[name]).toBeUndefined()`. Define `NEW_HEADERS` as a local literal of the seven names, not imported from the shared list, so the test fails if the shared list loses one.
   - `it("still forwards link, etag, retry-after and rate-limit headers from the same response", ...)`: `res.headers["link"]` is the upstream value, `res.headers["etag"]` is `"v1"` (with quotes), `retry-after` is `30`, `x-ratelimit-remaining` is `41`.
   - `it("strips them on a connection-backed call too", ...)`: same route with `mint({ origin, connection: "gh" })`, which takes the branch at `proxy.ts:666-675` where the per-recipe names are merged into the set. The seven must still be absent and `link` still present.

6. Edge gateway test, `apps/edge/src/gateway/fetch.test.ts`. `FakeEgress.proxy()` returns a fixed `headers: { "content-type": "application/json" }` at line 90. Add a field beside `responseBody` (line 52) and spread it into the returned headers:

```ts
  /** Extra headers the fake upstream response carries (merged over the default). */
  responseHeaders: Record<string, string> = {};
  // ...in proxy():
      headers: { "content-type": "application/json", ...this.responseHeaders },
```

   In `describe("/_api/fetch", ...)` (line 180), after the 429 test at line 632, add:
   - `it.each(NEW_HEADERS)("does not copy %s from egress's response onto the app's", ...)`: `buildFetchEdge()`, set `egress.responseHeaders` to all seven plus `link`, `etag`, `retry-after` and `x-ratelimit-remaining`, `app.inject` a `GET /_api/fetch/https://api.github.com/x` with `{ ...HOST, origin: ORIGIN }` (as the 429 test does), assert `res.headers[name]` is undefined. Then assert `link`, `etag`, `retry-after` and `x-ratelimit-remaining` arrive unchanged. This proves the edge strips on its own even though a real egress would already have stripped them.
   - Run it once against the dev-gateway's reuse of the handler only if a dev-gateway fetch test already exists in `apps/edge/src/devGateway/devGateway.test.ts`; do not add a new dev-gateway suite for this.

7. Docs.
   - `docs/features/fetch-proxy.md:72-78` (item 4, "Header controls") says the response blocklist strips "`set-cookie` and friends" and lists "tracked gaps" including "it omits `authorization`/`www-authenticate` (#7)". The code at `packages/shared/src/fetch.ts:113` already blocks `authorization`, and `www-authenticate` is kept on purpose (`fetch.ts:104`). Rewrite only the clause about the response blocklist so it names what is stripped (credential and transport headers, `location`, and now the policy and reporting headers: `clear-site-data`, `content-security-policy`, `content-security-policy-report-only`, `refresh`, `report-to`, `reporting-endpoints`, `nel`) and what is kept (`link`, `www-authenticate`, `content-location` with an injected query redacted). Leave the `#8` and `#11` clauses alone unless you verify them while you are there; if either also looks stale, say so in `results/` rather than fixing it here.
   - `packages/deploy-skill/SKILL.md:409-423` (section 3.3, "Outbound HTTP") describes what the proxy passes through. Add one sentence: the proxy strips response headers that would change the app's own origin (`Content-Security-Policy`, `Clear-Site-Data`, `Refresh`, the reporting headers). The `Link` header still passes through, so pagination by `rel="next"` keeps working. Edit `SKILL.md` only. `apps/docs/src/apps/quickstart.md` is generated from it by `apps/docs/scripts/render-skill.ts` and is gitignored (`.gitignore:55`); the docs step of `./check-and-lint.sh` regenerates it, so do not hand-edit it.
   - `docs/adr/0005-ssrf-egress-controls.md:28` says the blocklist "backstops `authorization`". Do not edit the ADR here; this task adds no decision. Note in `results/` that the ADR sentence is still true.

8. Run the focused tests, then the gate:
   - `pnpm vitest run packages/shared/src/fetch.test.ts apps/egress/src/proxy.test.ts apps/edge/src/gateway/fetch.test.ts`
   - Delete `"nel"` from the array locally and confirm the shared, egress and edge tests each fail, then restore it. Do this once, so you know each of the three layers would catch a regression on its own.
   - `./check-and-lint.sh` in the dev container, then `just dev smoke`. Save the output under the sequence's `results/` directory.

9. Write any stale-doc findings from step 7 to `results/ct1-notes.md`, and note that `link` was left out of the list on purpose.

## Done When

- [ ] All requirements met.
- [ ] The shared blocklist test, the new egress `proxy.test.ts` cases (keyless and connection-backed) and the new edge `gateway/fetch.test.ts` cases pass. The existing cases in all three files pass unchanged, including the 429 / `retry-after` test at `apps/egress/src/proxy.test.ts:158` and the echo-back suite at `apps/egress/src/adversarial.test.ts:278`.
- [ ] Removing `"nel"` from the array makes the shared, egress and edge tests fail (checked once, then restored).
- [ ] `docs/features/fetch-proxy.md` and `packages/deploy-skill/SKILL.md` describe the new strip and say `Link` still passes. `apps/docs/src/apps/quickstart.md` was regenerated by the docs step, not edited by hand.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (edge and egress still boot and answer their checks). Output saved under `results/`. The smoke runner has no proxied-fetch check, so the vitest suites are the proof of the strip.
- [ ] Committed with `fest commit -m "CT-1: strip policy and reporting headers from proxied responses"`.
- [ ] Nothing here is Azure-specific, so nothing is left unverified in Azure.
