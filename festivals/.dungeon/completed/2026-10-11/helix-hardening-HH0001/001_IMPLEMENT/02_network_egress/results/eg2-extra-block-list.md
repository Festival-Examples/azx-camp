# EG-2 result: deployment-supplied extra block list

**Result: done.** `EGRESS_EXTRA_BLOCKED_CIDRS` (comma-separated IPv4 and IPv6 CIDRs) adds install-specific ranges, such as a VNet prefix outside RFC 1918, to the SSRF block list. Parsed once at boot in `apps/egress/src/config.ts`; any bad element (no prefix, bad length, zone id, `/0`, not an address) stops egress from starting with a message naming the variable. `apps/egress/src/ssrf.ts` checks the extra ranges for plain addresses and for every embedded IPv4 form, threaded through `resolveAndValidate`, the validating connector, and the pinned dispatcher. Boot logs the count and warns if `EGRESS_ALLOW_PRIVATE` (dev only, refused in production) is also set. Docs and `.env.example` updated; the Bicep wiring is EG-5's.

## Review checks

- Matching masks both the candidate and the configured base, so a range written with host bits (`10.250.1.7/16`) still matches its whole network. Checked directly in the container: `10.250.9.9` blocked, `11.0.0.1` allowed; `203.0.114.77/24` blocks `203.0.114.1`, not `203.0.115.1`; `2600:1::5/32` blocks `2600:1:ffff::1`.
- The exchange and provider clients use the proxy's shared dispatcher, built with the configured connector, so they get the extra list without changes (the task expected edits there).

## Evidence

- `config.test.ts` (unset, valid, each malformed form, production with and without the dev flag), `ssrf.test.ts` (range edges, embedded forms, empty-list regression, DNS rebind), `adversarial.test.ts` (end-to-end 403 for an extra range).
- Gate: all test files passed (`eg2-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped. Browser lane: 10 passed.

## Executor

cursor-agent, `composer-2.5`, 128 tool calls.
