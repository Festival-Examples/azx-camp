# SP-1 result: hang-up after the first byte

**Result: pass.** A client hang-up after the first response chunk already tears down the vendor connection on `main` (792557a). The fake vendor saw its response closed about 10 to 15 ms after the hang-up, and egress sent no second request.

## What ran

- Tests: `apps/egress/src/proxy.test.ts`, describe "egress /proxy — client hang-up after the first byte (characterization)":
  - `closes the vendor connection when the client hangs up after the first chunk`
  - `control: a client that stays connected sees the upstream finish normally`
- Command, in the dev container: `pnpm exec vitest run apps/egress/src/proxy.test.ts -t "hang-up|control"`
- Repeats: 10 runs with the final test code, 10 passes, no flake.
- Gate: `./check-and-lint.sh` passed (231 of 231 test files); summary in `sp1-gate.txt`.

## Changes made during review

The agent's version counted TCP connections to the fake vendor and stopped counting at the moment of the hang-up, because undici's pool opens an idle connection after an aborted stream. That made the "no retry" assertion unable to catch a retry, which would also arrive after the hang-up. Review changed the counter to HTTP requests, which an idle pooled connection never sends, and removed the switch. A leftover `console.info` was removed.

## What it means for SP-2

The design's correction holds: the open window is before the upstream headers arrive. SP-2 closes it by passing an abort signal to the upstream `request()`.

## Unverified

Loopback only, on Node 24 and undici 7.30. Not proven through the Container Apps ingress between edge and egress (unverified in Azure).

## Agent notes

- Executor: cursor-agent, `composer-2.5`, 248 tool calls. Audit trail kept in the orchestrator's scratchpad.
- The agent also saw `apps/portal/src/deploy/diagnose.test.ts` exceed a 3 s timing bound once during its own gate runs. A second flaky test to watch, alongside `connectionsJourney.integration.test.ts`.
