---
fest_type: task
fest_id: 02_sp2_egress_upstream_abort.md
fest_name: sp2 egress upstream abort
fest_parent: 01_spend_controls
fest_order: 2
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.333475-06:00
fest_updated: 2026-10-09T15:14:59.860256-06:00
fest_tracking: true
---



# Task: sp2 egress upstream abort

## Objective

Make egress `POST /proxy` stop the vendor call when the edge hangs up, including before the upstream headers arrive, for both `llm` and `fetch` instructions. Implements SP-2 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `01_sp1_hangup_characterization_test.md`: SP-1 must be merged with a passing result. Its `proxy.test.ts` harness (`slow` upstream, `callThroughSocket`) is reused here.
- [ ] A hang-up before the upstream headers arrive closes the upstream connection well before the upstream's own delay elapses.
- [ ] A hang-up while egress is still burning the jti or resolving the secret never dials the vendor.
- [ ] A hang-up that happened before the `close` listener was attached (the handler awaits `authenticate` first) is still detected and never dials the vendor.
- [ ] A hang-up writes no 502 and logs no `upstream request failed` warning. It increments `helix.egress.upstream_aborts` with only `helix.capability`.
- [ ] A request-body cap trip with the client still connected still answers 413. A streamed request-cap trip destroys `req.raw`, which can close the response socket; that must not be read as a client hang-up.
- [ ] Body caps, response header stripping, the 401 renew flag, and the shared dispatcher are unchanged. `dispatcher.close()` and `dispatcher.destroy()` are never called.
- [ ] After an abandoned call, a second call to the same origin succeeds, and N sequential completed calls still reuse sockets.
- [ ] The span still records `helix.client_disconnected = true`, and every span attribute stays on the `EGRESS_SPAN_ATTRS` allowlist, with no header name and no error text. The egress span records no exception.
- [ ] The recorded span outcome stays `ok` and `helix.upstream.status` reads 200 on this path, because no outcome header is set when the handler returns without writing. This is deliberate; `helix.client_disconnected` is what separates it. Say so in the code comment and in `docs/features/observability.md`.
- [ ] Both capabilities are covered by tests: one `llm` instruction and one `fetch` instruction.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-2-egress-upstream-abort`.

2. Add the instrument name. In `packages/shared/src/telemetry.ts`, add after line 39 (`INSTR_EGRESS_RETIREMENTS`):

```ts
export const INSTR_EGRESS_UPSTREAM_ABORTS = "helix.egress.upstream_aborts";
```

   `packages/shared/src/telemetry.test.ts` already pins the `helix.` prefix, the character set, and uniqueness. Run `grep -n "upstream_aborts" -r apps packages docs` first to confirm the name is free.

3. Add the counter to egress's instruments, `apps/egress/src/telemetry.ts`: import `INSTR_EGRESS_UPSTREAM_ABORTS` in the `@azx-pbc/shared/telemetry` import block (lines 10-17); add `upstreamAborts: Counter;` to `EgressInstruments` with a docblock ("`helix.capability` only. Never `appId`, see the allowlist note on `proxyDuration`."); and create it in `instruments()` after `retirements`:

```ts
    upstreamAborts: meter.createCounter(INSTR_EGRESS_UPSTREAM_ABORTS, {
      description: "Proxied calls abandoned by the edge before the response finished, by capability.",
    }),
```

4. Edit `apps/egress/src/proxy.ts`. Follow the pattern the edge already uses at `apps/edge/src/gateway/llm.ts:218-243` and `apps/edge/src/gateway/fetch.ts:338-341`: watch the response (`reply.raw`), not the request, and use `writableEnded`, not `writableFinished`. Read both comments before copying.

   a. Imports: nothing new. `request` is already imported from `undici` (line 10), `ATTR_CAPABILITY` is imported (line 33), and `instruments` is imported (line 46).

   b. At the very top of `runProxy` (line 320, directly after `const { instruction, targetRaw, method } = authenticated;` at line 325), before the jti burn, add the controller and the listener. Hoist `let requestCapTripped = false;` from line 595 up to here so the listener can read it:

```ts
    // The edge hangs up (its own client left, or it hit its deadline): stop waiting for
    // the vendor. Watch the response, not the request: req.raw 'close' fires once the
    // inbound body is drained. writableEnded, not writableFinished: light-my-request never
    // settles the latter.
    const abort = new AbortController();
    let clientGone = false;
    let requestCapTripped = false;
    const onClose = (): void => {
      // A request-cap trip destroys req.raw, which may close this socket too. That is our
      // own cut, not a hang-up, and the catch below must still answer 413.
      if (reply.raw.writableEnded || requestCapTripped) return;
      clientGone = true;
      abort.abort();
    };
    reply.raw.once("close", onClose);
    // proxyHandler awaits authenticate() before this function runs, so the socket can
    // already be gone and 'close' will never fire again. A destroyed response with no
    // end() is the same hang-up.
    if (reply.raw.destroyed && !reply.raw.writableEnded) onClose();
```

   Verify in the dev container that `reply.raw.destroyed` is true after a late hang-up (a scratch script with `http.createServer`, a raw `net` client that destroys its socket, and a 300 ms delay in the handler showed `destroyed: true, closed: true, writableEnded: false` on Node 24.12). Remove the old `let requestCapTripped = false;` at line 595 so there is one declaration.

   c. Pass the signal at the `request()` call (line 606):

```ts
      const upstream = await request(target.href, {
        method,
        headers,
        body: requestBody,
        dispatcher,
        signal: abort.signal,
      });
```

   An already-aborted signal makes `request()` reject without dialling, which is what covers a hang-up during the jti burn, secret resolution, or delegated resolution (none of those take a signal).

   d. In the `catch` (line 693) add the `clientGone` branch first. The order is `clientGone`, then `requestCapTripped`, then `SsrfBlockedError`, then the generic 502:

```ts
    } catch (err) {
      if (clientGone) {
        // Normal event, not a failure: nothing to write to a dead socket and nothing worth a warn.
        // The span's helix.client_disconnected (set in proxyHandler's finally) is the signal.
        instruments().upstreamAborts.add(1, { [ATTR_CAPABILITY]: instruction.capability });
        return;
      }
      if (requestCapTripped) {
```

   Returning without `reply.send` is safe: Fastify's `wrapThenable` skips `reply.send(undefined)` when `request.raw.aborted` or the socket is destroyed (`node_modules/.pnpm/fastify@5.12.5/node_modules/fastify/lib/wrap-thenable.js:30-36`). Confirm no `FST_ERR_PROMISE_NOT_FULFILLED` or "reply already sent" line is logged in the new tests.

   `ATTR_CAPABILITY` is already imported (line 35). `instruction.capability` is a signed claim with two values, `llm` or `fetch`, so the dimension is bounded.

   Listener hygiene: the controller is per request and the listener is registered with `once` on `reply.raw`, which is per request too. Do not register anything on the shared `dispatcher`.

   e. Do not touch lines 611-692 (header stripping, `capBody`, 401 flag). A hang-up after `await request()` resolves is already handled by the Fastify teardown that SP-1 characterized.

5. Tests. All real-socket, in `apps/egress/src/proxy.test.ts` in a new `describe("egress /proxy — hang-up before the headers (upstream abort)")`, reusing the SP-1 helpers. Extend `mint` in that file (line 112) with an optional `capability?: "fetch" | "llm"` (default `"fetch"`) so one test can send an `llm` instruction. Add a second upstream route that delays its headers: `/slow-headers` waits 3000 ms before `writeHead`, and records `upstreamSawClose` on `res.on("close")`/`req.on("close")` attached synchronously in the handler. Clear the 3000 ms timer in that `close` handler (as the SP-1 `slow` server does): after egress aborts, a later `writeHead` or `write` on the destroyed response emits `error` with no listener and kills the test process. Also attach `res.on("error", () => {})`.

   - **Pre-header abort (red before the fix, green after).** Call `/slow-headers` through a real socket with an `AbortController`; abort after 100 ms. Assert the upstream saw its connection close within about 1 s (well under the 3 s delay), using `vi.waitFor`. Assert the egress span recorded `helix.client_disconnected === true` (`recording.spans()`, find `helix.egress.proxy`).
   - **Abort during secret resolution.** Build the app with a resolver whose `resolve` awaits a promise the test controls (`makeApp(true, waitingResolver)`; `makeApp`'s second parameter is the resolver). Send a keyed instruction (`connection: "gh"`), abort the client while `resolve` is pending, then release the resolver. Assert the upstream saw **no connection** (`connections` counter stays 0).
   - **Late-attach window.** There is no deterministic way to make the client leave inside the gap between `authenticate()` returning and the listener being attached. Do not write a timing-dependent test for it. Verify the `reply.raw.destroyed` guard with the scratch script in step 4b, say in `results/` that the guard is verified that way and not by a test, and keep a short comment at the guard naming the reason.
   - **No 502, no warn.** `buildApp(deps, loggerOverride)` (`apps/egress/src/app.ts:71-76`) takes a pino option as its second argument. Pass `{ level: "warn", stream: capture }` where `capture` is a `Writable` that pushes each chunk into an array, the way `apps/egress/src/exchange.test.ts:572-577` does. After a pre-header hang-up, assert no captured line contains `upstream request failed`.
   - **Counter.** Using the pattern at `apps/egress/src/retire.integration.test.ts:314-321` (`metricTotal(name, match)` over `recording.metrics()`), assert `helix.egress.upstream_aborts` increases by exactly 1 with attribute keys equal to `["helix.capability"]`. Metrics are cumulative across tests (`recording.reset()` does not clear them), so assert on the before/after difference.
   - **Both capabilities.** Run the pre-header abort once with `capability: "llm"` and once with `"fetch"`; the counter increments carry `helix.capability` equal to `llm` and `fetch` respectively.
   - **Pooling survives.** After an abandoned call, make a normal call to the same origin; it returns 200. Then repeat the existing pooling scenario (6 sequential completed calls) after the abandoned one and assert `connections` stays below the request count. The existing test at `proxy.test.ts:427-453` stays unchanged and green; it covers completed calls only and is not evidence for the abandoned case.
   - **A request-cap trip is not a hang-up.** In `apps/egress/src/adversarial.test.ts`, inside the `egress body-size cap (issue #8)` block (starts at line 464; the chunked-request test is at line 552), add a test that streams a chunked request body over the cap with the client left connected, then asserts `helix.egress.upstream_aborts` did **not** increase and no `upstream request failed` line was logged. The client may see a 413 or a reset (Node destroys the socket of a half-read request, which is why the existing test accepts `threw || status === 413`); the assertion is on the counter, which goes red if the `requestCapTripped` guard in the listener is removed. Because this file has no `recording`, import `startRecordingTelemetry` and add the same `beforeAll`/`afterAll`/`afterEach` that `proxy.test.ts` has, scoped to this `describe`.
   - **Client gone mid-upload.** Same block: the client destroys its socket mid-upload (before the cap); assert `upstream_aborts` increased by 1 and no `upstream request failed` line was logged.
   - **Existing tests stay green and unchanged:** the request-cap and chunked-response truncation tests (`adversarial.test.ts:517-600`), and the header-stripping echo tests (`describe("egress secret echo-back (issue #7)")`, line 278).

6. Telemetry adversarial suite. In `apps/egress/src/spanAttributes.test.ts`, add a case to `describe("a recorded egress span")` (starts at line 130): drive a real hang-up through the proxy (reuse the proxy.test.ts harness or build a tiny one), then assert every key of the recorded `helix.egress.proxy` span is in `EGRESS_SPAN_ATTRS`, that `helix.client_disconnected` is `true`, that there is no `exception` event, and that the serialized attributes contain no header name and no error text.

7. Docs. In `docs/features/observability.md`: add a row to the instrument table (line 185) for `helix.egress.upstream_aborts | counter | capability (llm or fetch)`, and a bullet under the `helix.egress.proxy` span notes saying that a hang-up leaves `helix.outcome` at `ok` and `helix.upstream.status` at 200, and that `helix.client_disconnected` is the distinguishing attribute. Do not describe this as a bug.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or the `workflow/` paths: other readers cannot resolve them.

9. Verify behavior with telemetry off: run the new tests with `OTEL_SDK_DISABLED=1 pnpm vitest run apps/egress/src/proxy.test.ts` and confirm they still pass (the counter call is a no-op without a provider).

10. Run `just dev smoke` and confirm the egress group still proxies a call. Save the output under `results/`.

## Done When

- [ ] All requirements met.
- [ ] The pre-header test is red on `main` and green after the change (record the red run in `results/sp2-egress-upstream-abort.md`).
- [ ] The existing cap, header-stripping, and pooling tests pass unchanged.
- [ ] `helix.egress.upstream_aborts` increments with only `helix.capability`; the span allowlist test passes.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (egress still proxies a call). Output saved under `results/`.
- [ ] Committed with `fest commit -m "SP-2: abort the egress upstream call when the edge hangs up"`.
- [ ] Unverified in Azure: the abort propagation through the Container Apps ingress between edge and egress. Locally the edge and egress talk over loopback, so whether the ingress forwards a client reset promptly to egress is not proven. Name this in the PR text and in the operator rollout notes (SP-13).