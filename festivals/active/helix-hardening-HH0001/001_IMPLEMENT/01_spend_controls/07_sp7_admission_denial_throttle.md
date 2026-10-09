---
fest_type: task
fest_id: 07_sp7_admission_denial_throttle.md
fest_name: sp7 admission denial throttle
fest_parent: 01_spend_controls
fest_order: 7
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.335497-06:00
fest_updated: 2026-10-09T16:37:52.705277-06:00
fest_tracking: true
---



# Task: sp7 admission denial throttle

## Objective

Route the LLM gateway's existing per-app `quota_blocked` rows through the denial throttle and count every admission denial in a bounded counter, so a flood of refused calls cannot become a ledger write flood and an operator can see the refusals. Implements SP-7 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `06_sp6_default_llm_budget.md`: the default budget makes every unset app refusable, so the denial path matters for every app.
- [ ] Per-app `quota_blocked` rows (today unthrottled, `apps/edge/src/gateway/llm.ts:193-207`) go through `DenialThrottle`. After the window maximum (20 rows per app and env per 60 s, per replica) the refusal still returns its 429 but writes no row.
- [ ] LLM denials use their own throttle bucket. The throttle today keys on `denial:<env>:<appId>` (`apps/edge/src/gateway/denialThrottle.ts:54-55`) and is shared with the fetch allowlist denial; a burst of fetch denials must not suppress LLM audit rows or the reverse.
- [ ] Each refusal increments `helix.gateway.admission_denied` with exactly `helix.capability`, `helix.reason` and `helix.app_id`. The counter is NOT gated by the throttle: the row is dropped past the cap, the signal is not (the same deliberate divergence the fetch allowlist denial documents).
- [ ] `helix.reason` is a member of `ADMISSION_DENIAL_REASONS`. In this task the set is `app_budget_day` and `app_budget_burst` only. Later tasks add `platform_ceiling` and the three concurrency reasons when they first use them.
- [ ] The `helix.gateway.llm` span carries `helix.reason` (the existing `ATTR_REASON`) set to the denial reason on a refusal.
- [ ] `userOid` is never a dimension or an attribute. No prompt text, URL or identifier appears in any attribute.
- [ ] Failure path. A suppressed row logs once at the first suppressed attempt and then every thousandth (the throttle's existing `suppressedAt` behavior), not once per request.
- [ ] Failure path. With `denialThrottle` null (tests and any caller that does not supply one) every denial is metered, as for fetch.
- [ ] Behavior of the refusal responses is unchanged: `429 quota_exceeded` for the day cap, `429 rate_limited` for the burst cap.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-7-admission-denial-throttle`.

2. Shared names, `packages/shared/src/telemetry.ts`. Add to the instrument block (after line 40) and next to the other bounded vocabularies (the session one is at lines 216-221):

```ts
export const INSTR_GATEWAY_ADMISSION_DENIED = "helix.gateway.admission_denied";

/**
 * Why the LLM gateway refused a call before sending it upstream: the `helix.reason`
 * dimension of `helix.gateway.admission_denied`. Bounded by construction: these are the
 * refusal branches in `apps/edge/src/gateway/llm.ts`, and a test asserts the set.
 * `app_budget_day` and `app_budget_burst` are the per-app USD windows.
 */
export const ADMISSION_DENIAL_REASONS = ["app_budget_day", "app_budget_burst"] as const;
export type AdmissionDenialReason = (typeof ADMISSION_DENIAL_REASONS)[number];
```

   Check the names are unused: `grep -rn "admission_denied\|ADMISSION_DENIAL" packages apps docs`. Pin the array in `packages/shared/src/telemetry.test.ts` the way `SESSION_DENIAL_REASONS` is pinned.

3. Edge instrument, `apps/edge/src/telemetry.ts`: import `INSTR_GATEWAY_ADMISSION_DENIED`; add `gatewayAdmissionDenied: Counter;` to `EdgeInstruments` (interface at line 46, with a docblock giving the dimensions: `capability`, `reason` in `ADMISSION_DENIAL_REASONS`, `appId`; never `userOid`); create it in `instruments()` after `sessionGateDenied` (line 118) with a description such as "LLM gateway admission denials by capability and reason."

4. Metering helper, `apps/edge/src/gateway/usage.ts`, next to `meterGatewayCall` (line 418):

```ts
export function meterAdmissionDenied(call: {
  appId: string;
  capability: string;
  reason: AdmissionDenialReason;
}): void {
  instruments().gatewayAdmissionDenied.add(1, {
    [ATTR_APP_ID]: call.appId,
    [ATTR_CAPABILITY]: call.capability,
    [ATTR_REASON]: call.reason,
  });
}
```

   Import `ATTR_REASON` and `type AdmissionDenialReason` from `@azx-pbc/shared/telemetry` (the import block is at the top of `usage.ts`, lines 8-14). Note `ATTR_REASON` is `helix.reason`.

5. Give the throttle a scope. `apps/edge/src/gateway/denialThrottle.ts`: `admit(appId, env)` (line 54) builds the key (line 55) `denial:${env}:${appId}`. Add an optional third parameter `scope?: string`; the key becomes `denial:${scope}:${env}:${appId}` when a scope is given and stays exactly `denial:${env}:${appId}` when not, so the fetch caller is unchanged. Update the docblock to say the bucket is per capability scope. In `denialThrottle.test.ts` add: an LLM-scoped bucket and the unscoped (fetch) bucket are independent for the same app and env (exhaust one, the other still meters).

6. Wire the throttle into the LLM runtime.
   - `apps/edge/src/gateway/llm.ts`: add `denialThrottle: DenialThrottle | null;` to `LlmGatewayRuntime` (lines 65-77, with a one-line docblock "Caps metered quota denials per (app, env). null => uncapped (tests)") and `import type { DenialThrottle } from "./denialThrottle.js";`. The fetch runtime has the same field (`apps/edge/src/gateway/fetch.ts:64`).
   - `apps/edge/src/app.ts`: `llmRuntime` (line 259) does not carry it; add `denialThrottle,` using the existing instance created at line 219 (`const denialThrottle = new DenialThrottle(fallbackCounters)`; the fetch handler gets the same instance at line 301). Per-replica in-memory by design, as that class documents.
   - `apps/edge/src/devGateway/app.ts`: `llmRuntime` (line 134) needs `denialThrottle` too. Today the fetch handler builds its own inline at line 163 (`new DenialThrottle(new InMemoryCounterStore())`). Hoist one instance to a `const denialThrottle` above `llmRuntime`, use it in both, and keep the comment that the dev gateway is single-process.

7. The refusal path in `llm.ts`. Replace lines 193-215 with the throttled shape, copying the structure of the fetch denial (`apps/edge/src/gateway/fetch.ts:181-232`: ask the throttle, log the suppression summary, never gate the metric on the decision):

```ts
      if (overDay || overBurst) {
        const reason: AdmissionDenialReason = overDay ? "app_budget_day" : "app_budget_burst";
        // The signals are NOT gated on the throttle: the throttle protects an append-only
        // table with no DELETE grant, it does not hide the event. Past the cap the ledger is
        // blind to the flood by design; the counter and the span are not.
        meterGatewayCall({ appId: entry.appId, capability: "llm", outcome: "quota_blocked" });
        meterAdmissionDenied({ appId: entry.appId, capability: "llm", reason });
        trace.getActiveSpan()?.setAttribute(ATTR_REASON, reason);
        const decision = rt.denialThrottle
          ? await rt.denialThrottle.admit(entry.appId, caller.env, "llm")
          : { meter: true as const, suppressedAt: undefined };
        if (decision.suppressedAt !== undefined) {
          req.log.warn(
            { appId: entry.appId, env: caller.env, attempts: decision.suppressedAt },
            "quota-denial metering suppressed: this app is over its denial budget for the window",
          );
        }
        if (decision.meter) {
          await usage
            .record({
              appId: entry.appId,
              env: caller.env,
              ...identity,
              capability: "llm",
              model: chat.model,
              inputTokens: 0,
              outputTokens: 0,
              costMicroUsd: 0,
              outcome: "quota_blocked",
            })
            .catch(() => {});
        }
        // (unchanged) Day cap is the harder stop; prefer its message.
```

   Keep the two `codec.error` calls and the `return` exactly as they are. Add the `ATTR_REASON` and `AdmissionDenialReason` imports (the `@azx-pbc/shared/telemetry` import is at `llm.ts:20-26`) and `meterAdmissionDenied` (the `./usage.js` import, line 18). The first-N rows carry the audit signal; the rest are dropped with a magnitude summary.

8. Tests.
   - `apps/edge/src/gateway/llm.test.ts`, in `describe("quota: block-new, finish-in-flight (USD)")` (line 313): (a) after 25 refused requests for one app, `edge.usage.records` holds exactly 20 `quota_blocked` rows and every response was 429 (`buildApp` creates its throttle internally with the default maximum of 20 per 60 s window, so loop on one app inside a single test); (b) the existing two tests at lines 314-342 stay unchanged and green; (c) a refusal for app A does not consume app B's bucket if you can seed a second registry entry cheaply, otherwise cover this in `denialThrottle.test.ts`.
   - Telemetry with `startRecordingTelemetry`, in `apps/edge/src/gateway/telemetry.test.ts` (style of lines 28-36): `meterAdmissionDenied` produces a data point whose attribute keys are exactly `helix.app_id`, `helix.capability`, `helix.reason`; each `ADMISSION_DENIAL_REASONS` value is accepted and nothing else is a key; no user identifier on any point. In `llm.test.ts` (or `spanRedaction.test.ts`), after the 25-request flood, the counter total is 25 while the ledger rows are 20 (the metric is not gated), and the recorded `helix.gateway.llm` span for a refusal has `helix.reason` equal to `app_budget_day` or `app_budget_burst` as appropriate.
   - `apps/edge/src/spanRedaction.test.ts`: add a refused LLM call (planted prompt fragment in `messages[].content`, planted oid) to the global attribute scan, following the cases at line 147; assert no attribute value contains either plant, a URL, or the oid.
   - Re-run the new telemetry tests with `OTEL_SDK_DISABLED=1`.
   - Fetch behavior is unchanged: `fetch.test.ts` and `denialThrottle.test.ts` pass untouched apart from the new scope case.

9. Docs. `docs/features/observability.md`: add `helix.gateway.admission_denied | counter | capability, reason (app_budget_day / app_budget_burst; later gateway reasons are added with the change that introduces them), appId. Not gated by the denial throttle, so it counts refusals the ledger drops` to the instrument table (line 185). `docs/features/llm-gateway.md` "Quota" section (lines 33-46): the `quota_blocked` row is now throttled per app and env (20 per minute per replica) while the counter still counts every refusal.

10. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The flood test shows exactly 20 rows against 25 refusals and a counter of 25.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes. Output saved under `results/`.
- [ ] Committed with `fest commit -m "SP-7: throttle and count LLM admission denials"`.
- [ ] Nothing Azure-specific. The throttle stays per replica (up to three replicas, so the row cap is per replica); that is stated in the throttle's docblock and is acceptable because it damps write amplification rather than defending a limit.