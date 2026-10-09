---
fest_type: task
fest_id: 12_sp12_fetch_lease_caps.md
fest_name: sp12 fetch lease caps
fest_parent: 01_spend_controls
fest_order: 12
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.337254-06:00
fest_tracking: true
---

# Task: sp12 fetch lease caps

## Objective

Optionally bound the number of concurrent fetch-proxy calls per app with the same lease store, behind its own setting that is off by default, so one app cannot hold unlimited egress sockets. Implements SP-12 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `10_sp10_inflight_lease_store.md` (the store and table) and `11_sp11_llm_concurrency_caps_and_deadline.md` (the `LeaseStore` wiring in `app.ts` and the dev gateway, `requireNonNegativeInt`, and the `concurrency_app` reason).
- [ ] New setting `EDGE_FETCH_MAX_APP_IN_FLIGHT`, default `0` (off). Off means behavior is exactly as today: no lease is taken, no database round trip is added. A negative, fractional, non-numeric, `NaN` or `Infinity` value fails at boot naming the variable.
- [ ] With the setting positive, calls hold a lease on scope `fetch:app:<appId>`. A call over the cap is refused with `429 rate_limited` ("too many concurrent requests for this app") before an instruction is minted or egress is dialed, and counts `helix.gateway.admission_denied` with `capability = fetch` and `reason = concurrency_app`. No ledger row.
- [ ] The lease is held for the whole response, including the streamed body, and released when the response closes: normal completion, a client hang-up, an error, or a refusal. The design says "released in `finally`"; that does not work in this handler (see the first note under Implementation), so the release hangs off the response's `close` event.
- [ ] Release is idempotent and survives a failed release (logged, swallowed; the row expires at its TTL).
- [ ] Failure path. A lease acquire that throws fails closed: `503 upstream_error` ("fetch concurrency check unavailable") and a warn log with the fixed event `gateway.lease_unavailable`.
- [ ] The lease TTL is a named constant, ten minutes. The fetch path has no wall-clock deadline (its timeouts are idle timeouts), so a single call that outlives the TTL stops counting against the cap; that residual is stated in the code comment and the docs. This is bounded to one slot per such call.
- [ ] Caps are per app only; there is no per-user fetch scope and no per-replica gate for fetch.
- [ ] The dev gateway honors the setting in memory.
- [ ] Bicep passes the setting to the edge and the dev gateway.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-12-fetch-lease-caps`.

   Why the release cannot be a `finally`: the success path ends with `return reply.send(capBody(res.body, ...))` (`apps/edge/src/gateway/fetch.ts:413`). The handler returns Fastify's thenable `Reply`, which resolves only after the response has finished, but a `finally` block in the same function runs when the `return` statement executes, before that thenable is awaited. A `finally` release would free the slot as soon as the headers go out and would not count a long streamed response at all. The `reply.raw` `close` event fires after both a normal finish and a hang-up, which is the point the slot should be freed. (The LLM handler drives its own `for await` loop to completion before returning, so a `finally` is right there and nowhere else.) Verify this in your own test, as step 6 describes.

2. Config, `apps/edge/src/config.ts`. Add `maxAppInFlight: number;` to the `fetch` block of `GatewayConfig` (lines 205-218; docblock: `EDGE_FETCH_MAX_APP_IN_FLIGHT`, `0` off, the lease TTL residual) and parse it in `loadGatewayConfig` beside `maxBodyBytes` (line 773) with `requireNonNegativeInt(env.EDGE_FETCH_MAX_APP_IN_FLIGHT, 0, "EDGE_FETCH_MAX_APP_IN_FLIGHT")`. Add `maxAppInFlight: 0` to the `fetch:` object in both fixtures in `apps/edge/src/test/config.ts` (lines 92 and 135). Config tests as in the SP-11 task: default 0, honored value, rejections naming the variable, the dev-gateway loader.

3. Runtime wiring.
   - `apps/edge/src/gateway/fetch.ts`: add to `FetchGatewayRuntime` (lines 56-70):

```ts
  /** Per-app in-flight cap via leases; null (or maxAppInFlight 0) disables it. */
  concurrency: { leases: LeaseStore; maxAppInFlight: number } | null;
```

   - `apps/edge/src/app.ts`: pass `concurrency: { leases: deps.leases ?? fallbackLeases, maxAppInFlight: config.fetch.maxAppInFlight }` in the `makeFetchHandler` call (the call with `denialThrottle`, starting at the `const handleFetch =` on line 293), reusing the `fallbackLeases` the SP-11 task created.
   - `apps/edge/src/devGateway/app.ts`: pass `concurrency` built on the same in-memory store as the LLM runtime, with `config.fetch.maxAppInFlight`.

4. The handler, `apps/edge/src/gateway/fetch.ts`. Landmarks are quoted because earlier tasks moved lines: the numbers are those at `main` (792557a).
   - Place the acquire after the daily request budget gate (`const budget = entry.fetch.requestsPerDay;`, line 259) and after the request-body content-length fast path (the `if (!BODYLESS.has(req.method))` block that answers 413, ending just before `// Mint the attested instruction and forward to egress.`, line 296), and before `mintInstruction` (line 297): a refused call then costs nothing downstream.
   - Define `const FETCH_LEASE_TTL_MS = 10 * 60_000;` near the top with the comment about the residual.

```ts
    const conc = rt.concurrency;
    if (conc && conc.maxAppInFlight > 0) {
      let acquired: AcquireResult;
      try {
        acquired = await conc.leases.acquire(
          [{ scope: `fetch:app:${entry.appId}`, cap: conc.maxAppInFlight }],
          FETCH_LEASE_TTL_MS,
        );
      } catch (err) {
        req.log.warn({ err, event: "gateway.lease_unavailable" }, "lease acquire failed");
        sendFetchError(reply, 503, "upstream_error", "fetch concurrency check unavailable");
        return;
      }
      if (!acquired.ok) {
        meterAdmissionDenied({ appId: entry.appId, capability: "fetch", reason: "concurrency_app" });
        trace.getActiveSpan()?.setAttribute(ATTR_REASON, "concurrency_app");
        sendFetchError(reply, 429, "rate_limited", "too many concurrent requests for this app");
        return;
      }
      let released = false;
      const releaseLease = (): void => {
        if (released) return;
        released = true;
        void conc.leases.release(acquired.leaseId).catch((err: unknown) =>
          req.log.warn({ err, event: "gateway.lease_release_failed" }, "lease release failed"),
        );
      };
      // 'close' fires after the response finishes and after a hang-up: the right moment
      // to free the slot. A finally block would free it at the headers, because the
      // streamed body outlives this function's return.
      reply.raw.once("close", releaseLease);
      // If the socket is already gone when this attaches, 'close' will not fire again and the
      // lease lives until its TTL; that TTL is the backstop.
    }
```

     Import `meterAdmissionDenied` from `./usage.js` (its existing import block ends at line 40), `ATTR_REASON` from `@azx-pbc/shared/telemetry` (the import block ends at line 32), `type AcquireResult` and `type LeaseStore` from `./leaseStore.js`, and `trace` is already imported (line 20). The metric is bounded: `capability` is `fetch`, `reason` is from `ADMISSION_DENIAL_REASONS`, `appId` is the tenant id; nothing else.

   - The existing `record(...)` calls are awaited before any response is written on every path, so the ledger row precedes the release. Do not move them.

5. Tests, `apps/edge/src/gateway/fetch.test.ts`. `FakeEgress` (line 40) already supports `delayMs` and `abortedDuringCall`, and `responseBody` for a controllable body. Extend `buildFetchEdge` (line 129) to accept `fetch` config overrides (`maxAppInFlight`) and to expose the `InMemoryLeaseStore` it injects.
   - Refusal at the cap: cap 1, `egress.delayMs = 300`; start one call without awaiting, wait with `until` for `egress.calls.length === 1`, then a second call is `429` with code `rate_limited`, egress was called once, no ledger row for the refusal. After the first finishes, a third call succeeds.
   - Held for the whole body: set `egress.responseBody` to a `Readable` that emits a chunk now and the next after 200 ms; with `held("fetch:app:<id>")` polled via `until`, assert it is 1 while the body is still streaming and 0 after it ends. This is the test that would fail with a `finally`.
   - Release on hang-up, over a real socket (`withServer`, following the test at line 850): hang up mid-upload and assert `held` returns to 0.
   - Release on error: `egress` throws (set `egress.delayMs` with an aborted signal, or make `proxy` reject); the 502 is returned and `held` returns to 0.
   - Release exactly once: wrap the store so `release` counts calls; one completed call produces one release.
   - Off: with `maxAppInFlight: 0` the store is never called (a stub whose `acquire` throws proves it) and behavior is unchanged; the whole existing suite passes untouched.
   - Acquire throws: `503 upstream_error`, egress never called, the warn event logged.
   - Other capability untouched: the LLM caps and this cap use different scopes; a held fetch lease does not count against `llm:app:<id>`.
   - Telemetry: with `startRecordingTelemetry`, a refusal increments `helix.gateway.admission_denied` with exactly `helix.app_id`, `helix.capability` (= `fetch`), `helix.reason` (= `concurrency_app`). Add the refused fetch call (planted oid in the session, planted path segment) to the `spanRedaction.test.ts` global attribute scan: no attribute holds the oid, a scope string, or the planted path content beyond what `spanUrlAttributes` already allows. Re-run with `OTEL_SDK_DISABLED=1`.

6. Bicep, `infra/azure/main.bicep`: parameter `fetchMaxAppInFlight` (`@minValue(0)`, default `0`, description naming the env var and the TTL residual); env entry `EDGE_FETCH_MAX_APP_IN_FLIGHT` on `edgeApp` and `devGatewayApp`, next to `EDGE_FETCH_MAX_BODY_BYTES` (lines 1237 and 1442 at `main`). Run `just infra build`.

7. Docs. `docs/features/` fetch-proxy page if one describes quotas (`grep -rn "requestsPerDay" docs/features`): add a short "Concurrency cap" note; `docs/features/observability.md`: the `helix.gateway.admission_denied` row now also carries `capability = fetch`; `apps/docs/src/deploy/configuration.md`: a parameter row and a variable row; `.env.example`: the variable, commented, default 0. The TTL residual is stated in each.

8. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The held-for-the-whole-body test passes (and demonstrably fails if the release is moved into a `finally`; note that check in `results/`).
- [ ] With the setting at its default of 0, the full existing fetch suite passes unchanged.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (the runner exercises the fetch path through the edge and egress). Output saved under `results/`.
- [ ] `just infra build` passes for the parameter and env entries.
- [ ] Committed with `fest commit -m "SP-12: optional per-app lease cap on the fetch path"`.
- [ ] Unverified in Azure: the Bicep parameter and env wiring (compile-checked only). The cap is a bound on egress sockets one app can hold, not vendor spend; a call that outlives the ten-minute TTL stops counting.
