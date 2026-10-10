---
fest_type: task
fest_id: 02_eg2_deployment_supplied_extra_block_list.md
fest_name: eg2 deployment supplied extra block list
fest_parent: 02_network_egress
fest_order: 2
fest_status: in_progress
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.023909-06:00
fest_updated: 2026-10-10T01:35:32.703228-06:00
fest_tracking: true
---


# Task: eg2 deployment supplied extra block list

## Objective

Let an install add its own blocked CIDR ranges to the egress SSRF filter through `EGRESS_EXTRA_BLOCKED_CIDRS`, parsed once at boot and passed as an explicit parameter to every function that decides whether an address is blocked. Implements EG-2 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `01_eg1_block_list_additions_and_boundary_tests.md` (same files, and the new embedded-form helper in `ssrf.test.ts`). `03_eg3_special_purpose_registry_completeness_test.md` and `05_eg5_nsg_module_and_subnet_attachment.md` depend on this task.
- [ ] `EGRESS_EXTRA_BLOCKED_CIDRS` is a comma-separated list of IPv4 and IPv6 CIDRs. Unset, empty, or only whitespace is valid and means no extra ranges (the relaxed per-install value; this is the default).
- [ ] The list is parsed once, in `loadConfig`, into the same numeric form the built-in lists use (a 32-bit integer for IPv4, a `bigint` for IPv6, plus the prefix length).
- [ ] An address inside an extra range is blocked; the address just outside it is allowed. An IPv6 extra range works. An extra IPv4 range also blocks the IPv4 address embedded in the mapped, NAT64, compatible and translated IPv6 forms, because those forms already re-check the extracted IPv4.
- [ ] Failure path. A malformed entry makes `loadConfig` throw, so egress refuses to boot: a missing `/`, a non-IP address, a prefix length that is not an integer or is out of range (over 32 for IPv4, over 128 for IPv6), a zone id (`%eth0`), an empty element inside a non-empty list (`a,,b`), and `/0` (it would block every address). The error names `EGRESS_EXTRA_BLOCKED_CIDRS` and the offending entry. Under `activeRevisionsMode: 'Single'` the old revision keeps serving and the new revision shows unhealthy.
- [ ] The list is an explicit, required parameter of `isBlockedAddress`, `resolveAndValidate`, `makeValidatingConnector` and `makePinnedDispatcher`. There is no module-level global and no default value, so a caller that forgets it fails typecheck.
- [ ] Every caller passes the same configured list. Production has exactly one construction site, `makeProxyHandler` (`apps/egress/src/proxy.ts:272`); the exchange transport and the provider client receive that dispatcher and do not build their own connector (see Design mismatch below).
- [ ] `allowPrivate` bypasses the extra list too, exactly as it bypasses the built-in list. `EGRESS_ALLOW_PRIVATE` in production still refuses to boot, and a non-empty extra list does not change that.
- [ ] The boot log (`boot.serving`) reports how many extra ranges are active (a count, not the values), and a boot `warn` is written when `allowPrivate` is on and the extra list is non-empty, because the dev seam makes the list inert.
- [ ] No new span, metric or attribute (the blocked outcome is the existing 403 `blocked`).
- [ ] Design mismatch to record in `results/`: the design says `exchangeTransport.ts` and `providerClient.ts` must each receive the list. In the code they take the proxy's dispatcher as an argument (`apps/egress/src/exchangeTransport.ts:21`, `apps/egress/src/providerClient.ts:18` and `:45`) and never build a connector, so they change nothing. The comment at `apps/egress/src/ssrf.ts:212-216` is accurate about the shared transport; the list reaches them through `proxy.dispatcher` (`apps/egress/src/app.ts:162` and `:180`).

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-2-extra-block-list` (after `eg-1-block-list-additions` is merged).

2. Parser and parameter, `apps/egress/src/ssrf.ts`. Export a parsed type and two functions. Put them after `inV6Cidr` (line 104-107), because they use `ipv4ToInt` and `ipv6ToBigInt`, which are private to this file:

```ts
/** A CIDR from `EGRESS_EXTRA_BLOCKED_CIDRS`, parsed once at boot. */
export type ParsedCidr =
  | { family: 4; base: number; bits: number }
  | { family: 6; base: bigint; bits: number };

export function parseCidr(text: string): ParsedCidr {
  const slash = text.indexOf("/");
  if (slash === -1) throw new Error(`"${text}" is not a CIDR (want address/prefix-length)`);
  const addr = text.slice(0, slash);
  const lenText = text.slice(slash + 1);
  if (!/^\d{1,3}$/.test(lenText)) throw new Error(`"${text}" has a bad prefix length`);
  const bits = Number(lenText);
  if (addr.includes("%")) throw new Error(`"${text}" must not carry a zone id`);
  const family = isIP(addr);
  if (family === 0) throw new Error(`"${text}" does not start with an IP address`);
  if (bits === 0) throw new Error(`"${text}" is a /0 and would block every address`);
  if (bits > (family === 4 ? 32 : 128)) throw new Error(`"${text}" has a prefix length out of range`);
  return family === 4
    ? { family: 4, base: ipv4ToInt(addr)!, bits }
    : { family: 6, base: ipv6ToBigInt(addr), bits };
}

/** Empty or whitespace-only means "none". Any bad element throws, naming `name`. */
export function parseCidrList(raw: string | undefined, name: string): ParsedCidr[] {
  if (raw === undefined || raw.trim() === "") return [];
  return raw.split(",").map((part) => {
    const entry = part.trim();
    if (entry === "") throw new Error(`${name} has an empty element (check for a stray comma)`);
    try {
      return parseCidr(entry);
    } catch (err) {
      throw new Error(`${name}: ${(err as Error).message}`);
    }
  });
}
```

   `ipv4ToInt` accepts only a strict dotted quad, so `isIP` must run first (it does above) and `ipv4ToInt(addr)!` is safe after `isIP(addr) === 4`.

3. Thread the parameter. Change the four signatures, appending `extraBlocked: readonly ParsedCidr[]` as the last parameter of each:
   - `isBlockedAddress(ip, extraBlocked)` (line 139). In the IPv4 branch return `isBlockedV4Int(v4, extraBlocked)`; change `isBlockedV4Int` (line 56) to take the list and also test `extraBlocked.some((c) => c.family === 4 && inV4Int(ipInt, c))`. For IPv6, check the extra IPv6 ranges against the full value first, then run the existing extraction branches, each of which calls `isBlockedV4Int(..., extraBlocked)` so an embedded IPv4 meets the extra IPv4 ranges. Add a small `inV4Int(ipInt, c)` helper that reuses the mask arithmetic in `inV4Cidr` (lines 34-38) instead of duplicating it.
   - `resolveAndValidate(hostname, allowPrivate, extraBlocked)` (line 168): pass the list to both `isBlockedAddress` calls (lines 177 and 187). The `!allowPrivate &&` guards stay, which is what makes the dev seam bypass the extra list.
   - `makeValidatingConnector(allowPrivate, timeoutMs, extraBlocked)` (line 218): pass it to `resolveAndValidate` (line 224).
   - `makePinnedDispatcher(allowPrivate, timeoutMs, extraBlocked)` (line 276): pass it to `makeValidatingConnector` (line 278).

4. Config, `apps/egress/src/config.ts`.
   - Add to `EgressConfig` (after `allowPrivate`, line 91) with a docblock: `extraBlockedCidrs: ParsedCidr[];` "Extra CIDR ranges the SSRF filter refuses, from `EGRESS_EXTRA_BLOCKED_CIDRS`. Empty means built-in ranges only. Bypassed by `allowPrivate` like the built-in list." Import `parseCidrList` and `type ParsedCidr` from `./ssrf.js`.
   - In `loadConfig`, after the production refusal loop (it sits at lines 208-216, built on `allowPrivate`), parse once: `const extraBlockedCidrs = parseCidrList(env.EGRESS_EXTRA_BLOCKED_CIDRS, "EGRESS_EXTRA_BLOCKED_CIDRS");`. A bad value throws here, before anything binds a port. Add `extraBlockedCidrs,` to the returned object next to `allowPrivate` (line 249).
   - Leave the `allowPrivate` production refusal exactly as it is.

5. Callers.
   - `apps/egress/src/proxy.ts`: add `extraBlockedCidrs: readonly ParsedCidr[];` to `ProxyDeps` (lines 58-79, next to `allowPrivate` on line 66) and pass it at line 272: `connect: makeValidatingConnector(deps.allowPrivate, deps.limits.timeoutMs, deps.extraBlockedCidrs)`. Import the type from `./ssrf.js` (line 48 already imports from it).
   - `apps/egress/src/app.ts`: pass `extraBlockedCidrs: deps.config.extraBlockedCidrs` in the `makeProxyHandler({...})` call (line 133-135 area, next to `allowPrivate: deps.config.allowPrivate` on line 135).
   - `apps/egress/src/server.ts`: add `extraBlockedCidrCount: config.extraBlockedCidrs.length` to the `boot.serving` log object (event at line 320; `allowPrivate` is on line 331). In the block that warns when `config.allowPrivate` is set (line 337), add a second `app.log.warn` when `config.extraBlockedCidrs.length > 0`: "EGRESS_EXTRA_BLOCKED_CIDRS is set but EGRESS_ALLOW_PRIVATE bypasses it".
   - `apps/egress/src/exchangeTransport.ts`, `providerClient.ts`, `exchange.ts`: no change (see the design mismatch above). `ExchangeDeps.allowPrivate` (`exchange.ts:88`) is not related to the connector.

6. Fix every existing test site that the signature change breaks, and every fixture that typecheck cannot see. This is the step that is easy to get wrong:
   - Direct callers (typecheck finds these): `apps/egress/src/ssrf.test.ts` calls `isBlockedAddress(ip)` at lines 50, 62, 68, 82, 86, 102 and 108, `resolveAndValidate(name, bool)` at lines 117, 124, 131, 141, 152, 159 and 169, and `makeValidatingConnector(true, 5_000)` at lines 194 and 234. Add a `const NO_EXTRA: readonly ParsedCidr[] = [];` at the top and pass it. `apps/egress/src/exchange.test.ts` calls `makePinnedDispatcher(false, 1_000)` at line 685 and `makePinnedDispatcher(true, 1_000)` at line 727; `apps/egress/src/retire.integration.test.ts:471` and `apps/egress/src/renewal.integration.test.ts:187` call `makePinnedDispatcher(true, ...)`. Pass `[]`.
   - Config fixtures (typecheck CANNOT find these): eight places build the config as an object literal cast with `as EgressConfig`, so a missing field compiles and then reaches `makeValidatingConnector` as `undefined` at runtime. Add `extraBlockedCidrs: []` to each: `adversarial.test.ts:110` and `:506`, `delegated.integration.test.ts:208`, `exchange.test.ts:148` and `:537`, `managedIdentity.test.ts:180`, `proxy.test.ts:105`, `requestId.test.ts:23`, `spanOutcome.test.ts:48`. After editing, run `grep -n "as EgressConfig" apps/egress/src/*.ts` and confirm each hit is followed by a literal that contains `extraBlockedCidrs`. The design's claim that a missing caller fails typecheck is true for the production code and false for these fixtures, which is why `makeProxyHandler` should not paper over it with `?? []`.

7. Tests.
   - `apps/egress/src/config.test.ts` (style of the `EGRESS_MANAGED_IDENTITY_CONNECTIONS` block, which uses `it.each` and `.toThrow(/NAME/)`): add `describe("EGRESS_EXTRA_BLOCKED_CIDRS")`. Cases: unset gives `[]`; `"  "` gives `[]`; `"203.0.113.0/24, 2001:db9::/32"` parses to two entries with the right family and prefix length; `it.each` of malformed values (`"10.0.0.0"`, `"10.0.0.0/33"`, `"2001:db9::/129"`, `"nope/8"`, `"10.0.0.0/x"`, `"10.0.0.0/0"`, `"10.0.0.0/8,,10.1.0.0/16"`, `"fe80::1%eth0/64"`) each throw `/EGRESS_EXTRA_BLOCKED_CIDRS/`. Add the production case: `loadConfig({ ...ENV, EGRESS_ALLOW_PRIVATE: "true", EGRESS_EXTRA_BLOCKED_CIDRS: "10.9.0.0/16", NODE_ENV: "production" })` still throws `/EGRESS_ALLOW_PRIVATE.*refused in production/`, and a production boot with a valid extra list and `allowPrivate` unset succeeds with the list parsed.
   - `apps/egress/src/ssrf.test.ts`: a describe for the extra list. Build the list with `parseCidrList("198.19.0.0/16,2001:db9::/32,203.0.114.0/25", "test")`. Assert: `isBlockedAddress("198.19.0.1", list)` and `("198.19.255.255", list)` are `true`; `("198.20.0.0", list)` is `false`; the v6 range blocks `2001:db9::1` and allows `2001:dba::1`; `("203.0.114.127", list)` blocks and `("203.0.114.128", list)` allows; the embedded forms of `198.19.0.1` (mapped, NAT64, compat, translated, using the `embed` helper from `01_eg1_...`) are blocked with the list and allowed without it (pass `[]`); an empty list changes nothing against the built-in tables. Add `resolveAndValidate` cases with the mocked `lookup`: a name resolving to an address in the extra range is refused; `allowPrivate = true` with the same list resolves it (the bypass); a dual-record name with one address in the extra range is refused as a whole.
   - `apps/egress/src/adversarial.test.ts`: in the "egress SSRF hardening" suite (line 139) add a case that builds the app with a non-empty `extraBlockedCidrs` (extend `makeApp` at line 99 with an optional parameter, default `[]`) and proxies to `http://198.19.0.1/`, expecting 403 `blocked`. The default-empty run of the existing four targets is the regression.

8. Docs. `docs/features/fetch-proxy.md` item 3 (line 65): add one sentence that an install can add ranges with `EGRESS_EXTRA_BLOCKED_CIDRS` and that the dev seam bypasses it. `apps/docs/src/deploy/configuration.md`: add an `EGRESS_EXTRA_BLOCKED_CIDRS` row to the environment-variable tables (the egress body-cap table at lines 206-209 is the closest model: Variable, App(s), Set from, If absent). "Set from" says the template sets it from the VNet prefix once `05_eg5_nsg_module_and_subnet_attachment.md` lands, so write "unset until the template wires it" for now and let that task finish the row; "If absent" says built-in ranges only. `.env.example`: add a commented `# EGRESS_EXTRA_BLOCKED_CIDRS=` line with a one-line description near the other egress settings (`PORTAL_EGRESS_URL` is at line 38).

9. Run: `pnpm vitest run apps/egress`, then the gate and smoke below. For smoke, run it twice from the dev container: once as is, once with `EGRESS_EXTRA_BLOCKED_CIDRS=10.99.0.0/16 just dev smoke` (the runner spreads `process.env` into the service environment, `smoke.mjs:58`). Also try `EGRESS_EXTRA_BLOCKED_CIDRS=garbage just dev smoke` once and confirm egress fails to boot and the runner reports it, then discard that run.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The new config, ssrf and adversarial cases pass. Every one of the eight cast fixtures and the five direct callers listed in step 6 is updated, and `pnpm -r typecheck` is clean.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes with the variable empty and with it set to a valid CIDR. Output saved under `results/`. Smoke proves egress boots and parses the value; it does not prove blocking, because the dev stack sets `EGRESS_ALLOW_PRIVATE=true` (`.devcontainer/docker-compose.yml:142`) and that setting bypasses the extra list by design. The blocking proof is `ssrf.test.ts` and `adversarial.test.ts`.
- [ ] The design mismatch about `exchangeTransport.ts` and `providerClient.ts` is written into `results/`.
- [ ] Committed with `fest commit -m "EG-2: add EGRESS_EXTRA_BLOCKED_CIDRS to the egress SSRF filter"`.
- [ ] Unverified in Azure: nothing in this task depends on Azure. The template side (`main.bicep` setting the variable) is `05_eg5_nsg_module_and_subnet_attachment.md`.