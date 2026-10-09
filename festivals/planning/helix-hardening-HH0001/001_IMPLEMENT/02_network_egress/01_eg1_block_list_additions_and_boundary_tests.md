---
fest_type: task
fest_id: 01_eg1_block_list_additions_and_boundary_tests.md
fest_name: eg1 block list additions and boundary tests
fest_parent: 02_network_egress
fest_order: 1
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.023011-06:00
fest_tracking: true
---

# Task: eg1 block list additions and boundary tests

## Objective

Close the gaps in the egress SSRF block list (Azure's wire-server address, the IPv4 documentation and 6to4-relay ranges, two IPv6 ranges, and the IPv4-translated IPv6 form) and prove every new range with boundary tests. Implements EG-1 from 03-egress-network-control.md.

## Requirements

- [ ] No prerequisite task. `02_eg2_deployment_supplied_extra_block_list.md` and `03_eg3_special_purpose_registry_completeness_test.md` build on this one, and `08_eg8_probe_entry_point.md` lists it as a dependency.
- [ ] `isBlockedAddress` returns `true` for every address in these new IPv4 ranges: `168.63.129.16/32`, `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `192.88.99.0/24`.
- [ ] `isBlockedAddress` returns `true` for every address in `3fff::/20` and `5f00::/16`.
- [ ] The IPv4-translated form `::ffff:0:0:0/96` (for example `::ffff:0:7f00:1`) is handled like the mapped, NAT64 and compatible forms: the embedded IPv4 is extracted and re-checked. `::ffff:0:7f00:1` is blocked, `::ffff:0:808:808` (8.8.8.8) is allowed.
- [ ] All four embedded spellings of `168.63.129.16` are blocked: `::ffff:a83f:8110` (mapped), `64:ff9b::a83f:8110` (NAT64), `::a83f:8110` (compatible), `::ffff:0:a83f:8110` (translated). The same four forms are tested for every new IPv4 range.
- [ ] Boundary behavior, not just membership: for each new range the first address and the last address are blocked, and the address just below the first and just above the last are allowed. For `168.63.129.16/32` those outside neighbors are `168.63.129.15` and `168.63.129.17`.
- [ ] Failure path. A hostname that resolves to `168.63.129.16`, alone or in a dual-record set with a public address, is refused as a whole host with `SsrfBlockedError` (the existing rule that one blocked address refuses the host).
- [ ] Failure path. An end-to-end `POST /proxy` whose target is `168.63.129.16` (and its hex-mapped form) returns 403 with `code: "blocked"`, and egress never dials: the response arrives well inside the configured upstream timeout instead of timing out into a 502.
- [ ] No behavior change for public addresses already allowed: the existing `ssrf.test.ts` tables still pass untouched.
- [ ] No new span, metric or attribute. The blocked outcome is already a 403 `blocked` (`apps/egress/src/proxy.ts:699-701`), and the optional `ssrf.reason` attribute is deferred by `plan.md`; do not add it.
- [ ] Whether `168.63.129.16` is reachable from a Container Apps replica stays **unverified in Azure**. The block is safe either way.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-1-block-list-additions`.

2. Read `apps/egress/src/ssrf.ts` end to end first. The pieces you change:
   - `V4_BLOCKED` is at lines 41-53, one `[base, bits]` tuple per range with a trailing comment. `isBlockedV4Int` (lines 56-58) walks it with `inV4Cidr` (lines 34-38), which already handles `bits = 32`.
   - `V6_BLOCKED` is at lines 115-127, parsed once into `V6_BLOCKED_NUM` (lines 130-133). `V6_MAPPED` and `V6_NAT64` are at lines 135-136.
   - `isBlockedAddress` is at lines 139-153. The embedded-IPv4 extraction is lines 146-148.

3. Add the five IPv4 ranges to `V4_BLOCKED`, keeping the list sorted by base address and the one-line comment style:

```ts
  ["168.63.129.16", 32], // Azure virtual public IP: wire server, platform DNS, health probes
  ["192.0.2.0", 24], // TEST-NET-1 (documentation)
  ["192.88.99.0", 24], // deprecated 6to4 relay anycast (v6 2002::/16 is already blocked)
  ["198.51.100.0", 24], // TEST-NET-2 (documentation)
  ["203.0.113.0", 24], // TEST-NET-3 (documentation)
```

   Insert each at its sorted position (`168.63.129.16` after `127.0.0.0`/before `169.254.0.0`; `192.0.2.0` after `192.0.0.0`; `192.88.99.0` before `192.168.0.0`; `198.51.100.0` after `198.18.0.0`; `203.0.113.0` before `224.0.0.0`).

4. Add the two IPv6 ranges to `V6_BLOCKED` the same way:

```ts
  ["3fff::", 20], // documentation (RFC 9637)
  ["5f00::", 16], // segment-routing SIDs (RFC 9602)
```

5. Add the IPv4-translated form. Next to `V6_NAT64` (line 136) add the constant, and add one branch to `isBlockedAddress` beside the other three extractions (line 148 is the compatible-form branch; add the new line above it so the `val >> 32n === 0n` branch stays last):

```ts
const V6_TRANSLATED = ipv6ToBigInt("::ffff:0:0:0"); // ::ffff:0:0:0/96 IPv4-translated (SIIT)

    if (inV6Cidr(val, V6_TRANSLATED, 96)) return isBlockedV4Int(Number(val & 0xffffffffn)); // ::ffff:0:a.b.c.d
```

   The mapped form has `ffff` in the sixth group and the translated form in the fifth, so the two prefixes do not overlap and branch order between them does not matter. Add a sentence to the `V6_BLOCKED` docblock (lines 109-114) saying the translated form is handled by extraction too.

6. Update the module docblock only if it names a specific list of ranges (it does not today: lines 5-16); leave it. Do not touch `resolveAndValidate`, the connector or `makePinnedDispatcher`: the new ranges flow through `isBlockedAddress`. `02_eg2_deployment_supplied_extra_block_list.md` changes those signatures later.

7. Tests in `apps/egress/src/ssrf.test.ts`. Follow the existing `it.each` style (see lines 25-52 and 72-88). Add a small helper near the top of the file that builds an embedded form from a dotted quad, so every range is tested through every spelling without hand-converting hex:

```ts
function embed(form: "mapped" | "nat64" | "compat" | "translated", v4: string): string {
  const [a, b, c, d] = v4.split(".").map(Number) as [number, number, number, number];
  const hi = ((a << 8) | b).toString(16);
  const lo = ((c << 8) | d).toString(16);
  const prefix = { mapped: "::ffff:", nat64: "64:ff9b::", compat: "::", translated: "::ffff:0:" }[form];
  return `${prefix}${hi}:${lo}`;
}
```

   Add these tests:
   - `describe("isBlockedAddress — new IPv4 ranges (boundaries)")` with one `it.each` table of `[range, first, last, below, above]` rows. `blocks first and last` asserts `true` for `first` and `last`; `allows the neighbors` asserts `false` for `below` and `above`. Rows:
     - `168.63.129.16/32`: first and last both `168.63.129.16`, below `168.63.129.15`, above `168.63.129.17`
     - `192.0.2.0/24`: `192.0.2.0`, `192.0.2.255`, `192.0.1.255`, `192.0.3.0`
     - `198.51.100.0/24`: `198.51.100.0`, `198.51.100.255`, `198.51.99.255`, `198.51.101.0`
     - `203.0.113.0/24`: `203.0.113.0`, `203.0.113.255`, `203.0.112.255`, `203.0.114.0`
     - `192.88.99.0/24`: `192.88.99.0`, `192.88.99.255`, `192.88.98.255`, `192.88.100.0`
   - `describe("isBlockedAddress — new ranges through every embedded form")`: for each of the five ranges, take the first and last address, run `embed` for all four forms, assert `true`. Add the literal four spellings of `168.63.129.16` listed in Requirements so a bug in `embed` cannot hide a miss. Add the negative: `embed("mapped", "168.63.129.17")` and `embed("translated", "8.8.8.8")` are allowed.
   - `describe("isBlockedAddress — new IPv6 ranges")` with first, last, below, above for `3fff::/20` (`3fff::`, `3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff`, `3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff`, `3fff:1000::`) and `5f00::/16` (`5f00::`, `5f00:ffff:ffff:ffff:ffff:ffff:ffff:ffff`, `5eff:ffff:ffff:ffff:ffff:ffff:ffff:ffff`, `5f01::`). Blocked for first and last, allowed for the other two.
   - Extend `describe("resolveAndValidate — DNS AAAA rebind (mocked lookup)")` (line 112): a name resolving to `168.63.129.16` (`resolveTo([{ address: "168.63.129.16", family: 4 }])`) rejects with `SsrfBlockedError`; a dual-record name `[ { address: "8.8.8.8", family: 4 }, { address: "168.63.129.16", family: 4 } ]` rejects the whole host (same shape as the dual-record test at lines 147-155); a name resolving to `::ffff:0:a83f:8110` rejects.

   Keep the mocked-`lookup` setup exactly as the existing blocks do (`beforeEach(() => mockLookup.mockReset())`, `resolveTo`).

8. Adversarial test in `apps/egress/src/adversarial.test.ts`. The "egress SSRF hardening" suite is at line 139 and loops over four literal targets (169.254.169.254, 127.0.0.1, 10.0.0.5, `[::1]`) with `makeApp(false)` (defined at line 99) and `mint` (line 114). Add `http://168.63.129.16/` and `http://[::ffff:a83f:8110]/` to that list. Both go through the IP-literal branch of `resolveAndValidate`, which throws before any socket opens, so the case also proves "never dials": the suite's `makeApp` sets `timeoutMs: 5000`, and a dial to a dropped address would take about that long and answer 502, not 403. After the loop's existing assertions add one more explicit case that asserts the response body message matches `/blocked address/` (the `SsrfBlockedError` text) so a transport error cannot pass for a refusal.

9. Docs. `docs/features/fetch-proxy.md` item 3 (line 65, "SSRF controls") lists what is refused. Add the platform address and the documentation ranges to that sentence. Do not edit ADR-0005 here; `11_eg11_docs_and_adr_amendments.md` writes its amendment.

10. Run the focused tests first: `pnpm vitest run apps/egress/src/ssrf.test.ts apps/egress/src/adversarial.test.ts`. Then the gate and the smoke runner (see Done When). Save output under the sequence's `results/` directory.

11. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The new `ssrf.test.ts` tables and the `adversarial.test.ts` additions pass, and the existing cases in both files pass unchanged.
- [ ] Deleting `["168.63.129.16", 32]` from `V4_BLOCKED` locally makes the new tests fail (check once, then restore it).
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (egress still boots and answers its three smoke checks). Output saved under `results/`. Note: the smoke runner has no proxied-fetch or LLM check for egress (`.claude/skills/run-helix/smoke.mjs:479-507` covers health, a missing-header 400 and a forged-instruction 401), and the dev stack runs with `EGRESS_ALLOW_PRIVATE=true`, so the blocking proof is the vitest suites, not smoke.
- [ ] Committed with `fest commit -m "EG-1: block the Azure platform address, documentation ranges and 6to4 relay in egress SSRF filter"`.
- [ ] Unverified in Azure: whether `168.63.129.16` answers from a Container Apps replica, and which ports. Nothing here depends on the answer.
