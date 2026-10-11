# EG-3 result: special-purpose registry completeness test

**Result: done.** `apps/egress/src/ssrfRegistry.test.ts` embeds a snapshot of the IANA IPv4 and IPv6 Special-Purpose Address Registries (retrieved 2026-10-10 from `iana-ipv4-special-registry-1.csv` and `iana-ipv6-special-registry-1.csv`; the task's URLs without `-1` return 404) and asserts that every row marked not forwardable or not globally reachable is blocked by `isBlockedAddress` at its first, middle, and last address. Globally reachable service ranges (anycast, AMT, AS112, Teredo, 6to4 and its deprecated relay) are listed explicitly in `GLOBAL_SERVICES`, and two documented exceptions stay allowed because the filter extracts their embedded IPv4 instead of blocking them wholesale (`64:ff9b::/96`, `::ffff:0:0/96`); a stale exception fails the test. A layout guard fails loudly if the CSV format changes.

The test found one gap, now fixed in `apps/egress/src/ssrf.ts`: `100:0:0:1::/64` (IANA Dummy IPv6 Prefix, RFC 9780).

## Evidence

- Spot check of the embedded snapshot: `192.0.0.0/24`, `198.18.0.0/15`, `2001:db8::/32`, `100:0:0:1::/64`, `64:ff9b:1::/48` present.
- The agent removed `198.18.0.0/15` locally and the Benchmarking row failed, then restored it.
- Gate: 238 of 238 test files (`eg3-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`eg3-smoke.txt`).

## Maintenance

The snapshot is a point-in-time copy. When IANA adds a row, refresh the snapshot in the test; the layout guard and the per-row checks then show whether the filter needs the new range.

## Executor

cursor-agent, `composer-2.5`, 69 tool calls.
