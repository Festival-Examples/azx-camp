---
fest_type: task
fest_id: 11_sp11_llm_concurrency_caps_and_deadline.md
fest_name: sp11 llm concurrency caps and deadline
fest_parent: 01_spend_controls
fest_order: 11
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.336951-06:00
fest_updated: 2026-10-09T17:39:40.568516-06:00
fest_tracking: true
---



# Task: sp11 llm concurrency caps and deadline

## Objective

Cap the number of in-flight LLM calls per app and per user across all edge replicas, add a per-replica limit and a wall-clock call deadline, and release every slot only after the call's ledger row is written. Implements SP-11 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `05_sp5_charge_cut_and_failed_calls.md` (a deadline abort is charged by the same rule as a hang-up, through `recordOnce`'s `cut` option), `07_sp7_admission_denial_throttle.md` (`meterAdmissionDenied`, `ADMISSION_DENIAL_REASONS`) and `10_sp10_inflight_lease_store.md` (`LeaseStore`, `PgLeaseStore`, `InMemoryLeaseStore`, the table and grants).
- [ ] Per-app cap `EDGE_LLM_MAX_APP_IN_FLIGHT` (starting value 10) on scope `llm:app:<appId>`, and per-user cap `EDGE_LLM_MAX_USER_IN_FLIGHT` (starting value 3) on scope `llm:user:<appId>:<userOid>`. An over-cap call is refused with `503 capability_unavailable` and reason `concurrency_app` or `concurrency_user`.
- [ ] An anonymous caller gets the app scope only. Anonymous callers share one identity (`ANON_USER_OID`, `apps/edge/src/auth/gate.ts:105-114`), so a per-user scope would be one bucket for the whole public audience; the per-IP limiter still covers them.
- [ ] A per-replica limit `EDGE_LLM_MAX_IN_FLIGHT` refuses with reason `concurrency_replica`, checked before the database round trip. It is per replica by design and its docblock says so, as `DenialThrottle`'s does. The design gives no starting value; use 200 and record it in `results/` as a choice the owner has not confirmed.
- [ ] `0` disables each cap or limit. A negative, fractional, non-numeric, `NaN` or `Infinity` value fails at boot naming the variable.
- [ ] `EDGE_LLM_MAX_CALL_MS` (default 600000, ten minutes) is a wall-clock deadline: the upstream signal is `AbortSignal.any([clientAbort, AbortSignal.timeout(maxCallMs)])`. It must be positive; it has no off value because the lease TTL is derived from it (record this as a deviation from the design's blanket "every control has an off value").
- [ ] A deadline abort is an upstream-style error, not a hang-up: the row is `outcome: "error"`, `errorDetail` starting `deadline_exceeded` and ending `;usage=...`, charged by the cut rule even if no event had arrived, and the client gets a normal error (an in-band error frame if the head is out). A client hang-up is still distinguished by `clientGone`.
- [ ] The lease TTL is `maxCallMs` plus a grace period (60 s), so a live call never loses its slot.
- [ ] The lease is released after `recordOnce` has written the ledger row, on every exit path (success, upstream error, hang-up, deadline, exception), so a freed slot never admits a call that cannot yet see the previous call's spend. The replica gate is released on the same paths.
- [ ] Failure path. A lease acquire that throws (database down, lock wait past the statement timeout, pool timeout) fails closed: `503 capability_unavailable`, a warn log with the fixed event `gateway.lease_unavailable`, and the replica gate is given back.
- [ ] Failure path. A release that fails is logged and swallowed; the row expires at `expiresAt`.
- [ ] Denials write a metric and a span attribute, no ledger row (the design asks for none for concurrency refusals); `ADMISSION_DENIAL_REASONS` gains `concurrency_app`, `concurrency_user`, `concurrency_replica`. No scope string, `userOid`, URL or prompt text appears in any attribute.
- [ ] The dev gateway honors the caps in memory (`InMemoryLeaseStore`) and the deadline; it gets no database grant (`helix_dev` has none on `inflight_leases`).
- [ ] Bicep passes the four settings to the edge and the dev gateway.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-11-llm-concurrency-caps`.

   The `llm.ts` line numbers below are those at `main` (792557a). The earlier tasks in this sequence moved them, so find each spot by the landmark text quoted with it.

2. Shared names: extend `ADMISSION_DENIAL_REASONS` in `packages/shared/src/telemetry.ts` with `"concurrency_app"`, `"concurrency_user"`, `"concurrency_replica"` and update the pin in `packages/shared/src/telemetry.test.ts`.

3. Config, `apps/edge/src/config.ts`. Add to the `llm` block of `GatewayConfig` (docblocks as in the SP-6 task) and parse in `loadGatewayConfig`:
   - `maxAppInFlight: number` from `EDGE_LLM_MAX_APP_IN_FLIGHT` (default 10), `maxUserInFlight` from `EDGE_LLM_MAX_USER_IN_FLIGHT` (default 3), `maxInFlight` from `EDGE_LLM_MAX_IN_FLIGHT` (default 200). Use `requireNonNegativeNumber` (added by the SP-6 task) and wrap it in a small `requireNonNegativeInt` that also throws on a fractional value, with the variable named in the message.
   - `maxCallMs: number` from `EDGE_LLM_MAX_CALL_MS` through the existing `requirePositiveMs` (`apps/edge/src/config.ts:684`), default 600_000.
   - Add the four fields to both fixtures in `apps/edge/src/test/config.ts` with the caps at `0` (off) and `maxCallMs: 600_000`, so existing suites are unaffected. New tests override them.
   - `apps/edge/src/config.test.ts`: defaults, honored values, `0` accepted for the three caps, rejections (`"-1"`, `"2.5"`, `"abc"`, `"NaN"`, `"Infinity"`) naming the variable, `EDGE_LLM_MAX_CALL_MS` rejects `"0"` and negative values, the dev-gateway loader applies the same validation.

4. The replica gate. Create `apps/edge/src/gateway/replicaGate.ts`:

```ts
/**
 * Caps total in-flight LLM calls on this replica. It protects this process's sockets and
 * event loop without a database lock on every call. Per replica by design, like
 * DenialThrottle: the cross-replica limits are the Postgres leases, and the effective total
 * here is max x replicas (up to three).
 */
export class ReplicaGate {
  readonly #max: number;
  #inFlight = 0;
  constructor(max: number) { this.#max = max; }
  /** False when the replica is at its limit. 0 disables the limit. */
  tryEnter(): boolean {
    if (this.#max > 0 && this.#inFlight >= this.#max) return false;
    this.#inFlight += 1;
    return true;
  }
  leave(): void {
    if (this.#inFlight > 0) this.#inFlight -= 1;
  }
}
```

   with `replicaGate.test.ts`: admits up to the limit, refuses the next, `leave` frees a slot, `leave` never goes negative, `0` never refuses.

   Add a test helper to `InMemoryLeaseStore` (`leaseStore.ts`): `held(scope: string): number` returning unexpired leases on a scope, documented as for tests.

5. Wire the runtime. In `apps/edge/src/gateway/llm.ts` add to `LlmGatewayRuntime` (the interface at lines 65-77):

```ts
  /** Concurrency control; null disables every cap (tests that do not exercise it). */
  concurrency: {
    leases: LeaseStore;
    gate: ReplicaGate | null;
    maxAppInFlight: number;
    maxUserInFlight: number;
  } | null;
  /** Wall-clock deadline for one upstream call, ms. Also bounds the lease TTL. */
  maxCallMs: number;
```

   - `apps/edge/src/app.ts`: add `leases?: LeaseStore | null` to `EdgeDeps` (`EdgeDeps`, lines 75-110, beside `anonRateLimiter` at line 106). In `llmRuntime` (line 259) set `concurrency` from `config.llm.*`: `leases: deps.leases ?? fallbackLeases` where `fallbackLeases = new InMemoryLeaseStore()` is created next to `fallbackCounters` (line 213, same "keeps single-process dev and tests working" reasoning), `gate: new ReplicaGate(config.llm.maxInFlight)`, and `maxCallMs: config.llm.maxCallMs`.
   - `apps/edge/src/devGateway/app.ts`: `llmRuntime` (line 134) gets `concurrency` with a fresh `InMemoryLeaseStore()`, a `ReplicaGate`, the config caps, and `maxCallMs`. Comment: single process, so memory is correct, and `helix_dev` has no grant on `inflight_leases`.
   - `apps/edge/src/server.ts`: build `const leases = new PgLeaseStore(config.databaseUrl, { statementTimeoutMs: config.statementTimeoutMs, onClientError });` beside `counterStore` (line 175) and pass `leases` to `buildApp`. Schedule its sweep next to the `counterSweep` interval (lines 268-274) with the same shape (60 s, `unref`, warn on failure with a fixed message), clear it and `await leases.close()` in the `onClose` hook (line 275). Add the four values to the `boot.serving` log object (line 311).

6. The handler. All of this goes after the per-app and platform budget checks, before the "Admitted" abort controller block (landmark: the comment `// Admitted. Abort the upstream if the client goes away.`, line 218 at `main`).

   a. Admission, with one helper for the three refusals (metric plus span attribute, no row):

```ts
    const conc = rt.concurrency;
    let release: (() => Promise<void>) | null = null;
    if (conc) {
      const refuse = (reason: AdmissionDenialReason, message: string): void => {
        meterAdmissionDenied({ appId: entry.appId, capability: "llm", reason });
        trace.getActiveSpan()?.setAttribute(ATTR_REASON, reason);
        reply.header("retry-after", "1");
        codec.error(reply, 503, "capability_unavailable", message);
      };
      if (conc.gate && !conc.gate.tryEnter()) {
        refuse("concurrency_replica", "this replica is at its in-flight LLM limit");
        return;
      }
      const requests: LeaseRequest[] = [
        { scope: `llm:app:${entry.appId}`, cap: conc.maxAppInFlight },
        // An anonymous caller shares one identity; the per-IP limiter covers them.
        ...(caller.authenticated
          ? [{ scope: `llm:user:${entry.appId}:${userOid}`, cap: conc.maxUserInFlight }]
          : []),
      ];
      let acquired: AcquireResult;
      try {
        acquired = await conc.leases.acquire(requests, rt.maxCallMs + LEASE_GRACE_MS);
      } catch (err) {
        conc.gate?.leave();
        req.log.warn({ err, event: "gateway.lease_unavailable" }, "lease acquire failed");
        reply.header("retry-after", "5");
        codec.error(reply, 503, "capability_unavailable", "concurrency check unavailable");
        return;
      }
      if (!acquired.ok) {
        conc.gate?.leave();
        const app = acquired.scope.startsWith("llm:app:");
        refuse(
          app ? "concurrency_app" : "concurrency_user",
          app ? "too many concurrent LLM calls for this app" : "too many concurrent LLM calls for this user",
        );
        return;
      }
      release = async () => {
        conc.gate?.leave();
        await conc.leases.release(acquired.leaseId).catch((err: unknown) =>
          req.log.warn({ err, event: "gateway.lease_release_failed" }, "lease release failed"),
        );
      };
    }
```

      Import `type LeaseRequest`, `type AcquireResult` and `type LeaseStore` from `./leaseStore.js`, `ReplicaGate` from `./replicaGate.js`, and `meterAdmissionDenied` from `./usage.js`. Define `const LEASE_GRACE_MS = 60_000;` at the top of the file with a comment (the TTL is the deadline plus this, so a live call never loses its slot). `userOid` is the destructured binding already in scope (`const { userOid } = identity;`).

   b. Wrap everything from the abort controller block down to the end of the handler in `try { ... } finally { await release?.(); }`. Both branches await `recordOnce` before every exit (streaming: before `return;`; non-streaming: `recordOnce` precedes `sendResponse`, and the catch records), so `finally` runs after the ledger write. Add a comment at the `finally` saying that ordering is the point. A mechanical re-indent of the block is expected; keep the diff otherwise minimal.

   c. The deadline. Replace `const abort = new AbortController();` use at the provider call:

```ts
    const deadline = AbortSignal.timeout(rt.maxCallMs);
    const callSignal = AbortSignal.any([abort.signal, deadline]);
    const events = rt.provider.stream(chat, { signal: callSignal, ... });
```

      (The `clientGone` listener still aborts `abort`, unchanged.) In both `catch` blocks, after the `clientGone` branch, treat the deadline as a charged error:

```ts
      const deadlineHit = deadline.aborted;
      await recordOnce("error", {
        errorDetail: deadlineHit ? "deadline_exceeded" : errorDetailOf(err),
        cut: deadlineHit || eventsSeen > 0,
      });
      const { status, code, message, param, retryAfter } = deadlineHit
        ? { status: 502, code: "internal" as const, message: "LLM call exceeded its time limit", param: undefined, retryAfter: undefined }
        : describeError(err, { structured });
```

      Add a sentence to the module docblock and to the block-new comment: an abort by the client or by the deadline is not a quota cut.

7. Tests, `apps/edge/src/gateway/llm.test.ts` (new `describe("concurrency caps and the call deadline")`). Extend `buildLlmEdge` to accept `llm` config overrides (the SP-6 task started this) and `seedSession` to accept an `oid` so two different users can be seeded. To hold a call open, use `provider.onDelta` awaiting a promise the test releases. To run two calls concurrently through `app.inject()`, start the first without awaiting, wait with `until` (`apps/edge/src/test/socket.ts`) for `edge.provider.calls.length === 1`, then send the second.
   - Per-app cap 1: a second concurrent call from a different user is `503 capability_unavailable`; provider called once; after the first finishes, a third call succeeds.
   - Per-user cap 1 with app cap 5: the same user's second concurrent call is refused; a different user's is admitted.
   - Anonymous: a public-app registry entry (see how the data tests seed an anonymous caller), user cap 1, app cap 5: two concurrent anonymous calls are both admitted.
   - Replica limit 1: the second concurrent call is refused with the replica reason, for a different app too.
   - Release order: wrap the `InMemoryLeaseStore` in a spy whose `release` records `edge.usage.records.length`; assert it is 1 at release time on the streaming, non-streaming, upstream-error and hang-up paths.
   - Release on every path: after each of those, `held("llm:app:<id>")` is 0 and the gate is free (a further call succeeds).
   - `0` disables each cap.
   - Acquire throws (a stub store): `503`, provider never called, the warn event logged, the gate given back (the next call works once the stub is fixed).
   - Deadline: `maxCallMs: 50` with a provider that pauses 30 ms per delta over many deltas: the row is `error` with `errorDetail` matching `/^deadline_exceeded;usage=/`, `costMicroUsd > 0`, `stopReason` null; the lease is released; the client got an in-band error frame (streaming). Use real timers.
   - TTL: a spy records the TTL passed to `acquire` equals `maxCallMs + 60_000`.
   - Telemetry (`startRecordingTelemetry`): each of the three reasons increments `helix.gateway.admission_denied` with exactly `helix.app_id`, `helix.capability`, `helix.reason`; and `apps/edge/src/spanRedaction.test.ts` gets a refused-by-cap call with a planted oid and prompt fragment; no attribute value contains the oid, a scope string (`llm:user:`), or the fragment. Re-run with `OTEL_SDK_DISABLED=1`.
   - **The KP-2 exploit, end to end, over real sockets** (`withServer` from `apps/edge/src/test/socket.ts`): one app, caps well above the number of streams, eight concurrent streaming calls that each hang up after the first delta, with a platform ceiling set just below what eight charged calls cost. Assert: the ledger has eight `error` rows with `;usage=` markers and `costMicroUsd > 0`; `held(...)` returns to 0; the fake's platform spend reflects the charges; the next call is refused `503` by the ceiling.
   - Config and `ReplicaGate` tests as in steps 3 and 4.

8. Bicep, `infra/azure/main.bicep`, following the `fetchMaxBodyMb` pattern: parameters `llmMaxAppInFlight` (10), `llmMaxUserInFlight` (3), `llmMaxInFlight` (200), all `@minValue(0)`, and `llmMaxCallMs` (600000, `@minValue(1000)`), each with a description that names the env var and what `0` does. Pass `EDGE_LLM_MAX_APP_IN_FLIGHT`, `EDGE_LLM_MAX_USER_IN_FLIGHT`, `EDGE_LLM_MAX_IN_FLIGHT`, `EDGE_LLM_MAX_CALL_MS` on `edgeApp` and `devGatewayApp` next to `EDGE_LLM_OPENAI_CONNECTION` (lines 1230 and 1440 at `main`). Run `just infra build`.

9. Docs. `docs/features/llm-gateway.md`: add a "Concurrency and the call deadline" subsection after "Quota" (what the scopes are, anonymous callers, the overshoot bound `appCap x worst-case call cost`, fail-closed acquire, `0` to disable, the deadline and its charge). `docs/features/observability.md`: the three new reasons in the `helix.gateway.admission_denied` row. `apps/docs/src/deploy/configuration.md`: four parameter rows (the parameters table; the `platformMonthlyUsdCap` row is line 121) and four variable rows (the environment-variable tables; the first row of the `App(s)` table is line 199). `.env.example`: the four variables, commented, with their defaults. Do not write the ADR here; `13_sp13_adr_and_docs.md` does.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The exploit test passes: eight hung-up streams are charged, the leases return to zero, and the ceiling then refuses the next call.
- [ ] The release-order assertion passes on all four exit paths.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (the edge and dev gateway boot with the real `PgLeaseStore` and the sweep scheduled). Output saved under `results/`.
- [ ] `just infra build` passes for the four parameters and env entries.
- [ ] Committed with `fest commit -m "SP-11: cap concurrent LLM calls and add a call deadline"`.
- [ ] Unverified in Azure: the Bicep parameters and the edge and dev-gateway environment wiring (compile-checked only); the lease behavior across real replicas on Container Apps (proven locally with two stores on separate pools); that a deployed edge's database role can run the advisory-lock transaction at the statement timeout the pool sets. The starting values (10, 3, 200, 10 minutes) are guesses until real traffic exists.