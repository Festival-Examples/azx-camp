# EG-1 result: SSRF block-list additions and boundary tests

**Result: done.** `apps/egress/src/ssrf.ts` now also blocks `168.63.129.16/32` (Azure's virtual public IP: wire server, platform DNS, health probes), the IPv4 documentation ranges `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, the deprecated 6to4 relay `192.88.99.0/24`, IPv6 documentation `3fff::/20`, and segment-routing SIDs `5f00::/16`, and extracts the embedded IPv4 from the IPv4-translated form `::ffff:0:0:0/96` alongside the existing mapped, NAT64, and compat forms. `docs/features/fetch-proxy.md` updated.

## Evidence

- `ssrf.test.ts`: first and last blocked address and the neighbors just outside each new IPv4 and IPv6 range; every new range through the mapped, NAT64, compat, and translated spellings; DNS rebind cases for `168.63.129.16` alone and mixed with a public record. The agent confirmed that removing `168.63.129.16` from the list fails the boundary test.
- `adversarial.test.ts`: `http://168.63.129.16/` and `http://[::ffff:a83f:8110]/` return 403 `blocked`.
- Gate: all test files passed (`eg1-gate.txt`). Smoke: see `eg1-smoke.txt`.

## Unverified in Azure

Whether `168.63.129.16` is reachable from a Container Apps replica and on which ports. The block is intended either way.

## Executor

cursor-agent, `composer-2.5`, 32 tool calls.
