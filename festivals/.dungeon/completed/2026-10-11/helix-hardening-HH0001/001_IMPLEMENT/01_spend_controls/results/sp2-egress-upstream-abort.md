# SP-2 result: abort the egress upstream call when the edge hangs up

**Result: done.** Egress now passes an abort signal to the upstream `request()`, fed by `reply.raw` `close`, so a hang-up before the upstream headers arrive stops the vendor call. The hang-up path no longer logs a warning or writes a 502 to a dead socket, and it increments `helix.egress.upstream_aborts` (dimension `helix.capability` only).

## Evidence

- **Red on main, green after:** with `main`'s `apps/egress/src/proxy.ts` and the new tests, 5 of 6 tests in "hang-up before the headers (upstream abort)" fail (`closes the upstream connection well before the header delay elapses`, `logs no upstream request failed warning`, both `upstream_aborts` tests, `still pools sockets after an abandoned call`). All pass with the change.
- **Egress suites:** all 72 tests in `proxy.test.ts`, `adversarial.test.ts`, and `spanAttributes.test.ts` pass, also with `OTEL_SDK_DISABLED=1` on `proxy.test.ts`.
- **Smoke:** `just dev smoke` 31 passed, 0 failed, 1 skipped (the real-browser SPA render: no Chromium path for the smoke runner). Output in `sp2-smoke.txt`.
- **Gate:** see `sp2-gate.txt` and the note below.

## Gate note

The full gate ran while the host's load average was 60 to 80. Four test files outside egress failed: `apps/edge/src/auth/password-login.test.ts` (throttle), `apps/edge/src/auth/password.test.ts` (concurrency), `apps/portal/src/routes/data.test.ts` (export cap), and the known flaky `apps/edge/src/routing/connectionsJourney.integration.test.ts`. Rerun alone, the first three passed. `connectionsJourney` passed 2 of 3 runs on this branch, the same rate as on `main` (2 of 4). None of the four touches code this change edits. They are recorded as load flakes; the sequence's testing gate reruns the full suite.

## Review notes for the sequence review

- `never dials the vendor when the client aborts during secret resolution` also passes on `main`, so it does not demonstrate the fix. Strengthen or drop it.
- On the hang-up path the span records `helix.upstream.status = 200` although no upstream response arrived (no outcome header is written, so the reply's default status is read). The design accepted this; `helix.client_disconnected` distinguishes the path. Consider not setting the status attribute when the client is gone.
- The agent left a 15 MB Prisma engine crash dump at `apps/portal/core` during its gate runs; it was deleted before commit. `core` files are not in `.gitignore`.

## Unverified

Whether the Container Apps ingress forwards a client reset from edge to egress promptly (unverified in Azure). Locally edge and egress talk over loopback.

## Executor

cursor-agent, `composer-2.5`, 93 tool calls, about 21 minutes.
