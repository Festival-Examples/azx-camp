---
fest_type: task
fest_id: 09_sp9_platform_daily_ceiling.md
fest_name: sp9 platform daily ceiling
fest_parent: 01_spend_controls
fest_order: 9
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.336314-06:00
fest_tracking: true
---

# Task: sp9 platform daily ceiling

## Objective

Refuse new LLM calls platform-wide once the platform's LLM spend for the day reaches a configured ceiling, with the ceiling on by default in deployed installs, a boot self-test that catches a misconfigured owner policy, and an alert on the refusal. Implements SP-9 from 01-spend-controls.md.

## Requirements

- [ ] Depends on `07_sp7_admission_denial_throttle.md` (the throttled denial path, `meterAdmissionDenied`, `ADMISSION_DENIAL_REASONS`) and `08_sp8_platform_spend_definer_function.md` (the `platform_llm_spend_micro_usd` function and its grants).
- [ ] New setting `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY`. A positive number enables the ceiling. `0` or unset disables it (local development unaffected; a one-organization install under ADR-0028 can switch it off explicitly). A negative, non-numeric, `NaN` or `Infinity` value fails at boot with the variable named.
- [ ] With the ceiling set, an app under its own budget is refused with `503 capability_unavailable` ("platform LLM budget exhausted for today") and a `retry-after` equal to the seconds until the next local midnight, once the platform's `today` sum reaches the ceiling. The day boundary is the one the per-app check uses (`date_trunc('day', now())`). No new shared error code (`API_ERROR_CODES` in `packages/shared/src/api.ts` is a client contract).
- [ ] The ceiling check runs after the per-app check: an app over its own budget still gets `429`, not `503`.
- [ ] The denial is recorded as a `quota_blocked` row with `errorDetail = "platform_ceiling"`, through the same denial throttle as the per-app denial (a ceiling trip is when every app floods at once), and counts `helix.gateway.admission_denied` with reason `platform_ceiling`.
- [ ] Failure path. The ceiling read throws (database down, `EXECUTE` missing): fail closed. The call is refused with `503 capability_unavailable` and `retry-after: 5`; a warn log with the fixed event `gateway.platform_spend_unavailable` is written. A stale cache entry is used only inside its TTL; after that a failed read refuses the call.
- [ ] Failure path. A migration whose owner policy is missing returns zeros and would silently disable the ceiling. The edge runs a self-test at boot when the ceiling is enabled: it checks the function exists, is `SECURITY DEFINER`, and that the `gateway_calls_owner_read` policy admits the function's owner. A misconfiguration fails the boot loudly; an unreachable database only warns (the registry already tolerates a down database at boot, and ceiling reads fail closed per call).
- [ ] The platform read is cached per edge replica for a short TTL (5 s) with one read in flight per env, so the database sees a handful of queries a minute. The overshoot bound is stated in the code and docs: at most the ceiling plus the calls admitted before the cache caught up.
- [ ] The dev gateway never enforces the ceiling (`helix_dev` has no `EXECUTE` grant on the function).
- [ ] Bicep supplies a value to a deployed edge by default: one tenth of `platformMonthlyUsdCap`, `0` to switch off. An alert rule fires on `helix.gateway.admission_denied` with `reason = platform_ceiling`.
- [ ] Telemetry ships with it: `platform_ceiling` joins `ADMISSION_DENIAL_REASONS`; an observable gauge `helix.gateway.platform_spend_ratio` (dimension `helix.env`) reports cached spend over the ceiling so an alert can fire at 80% before the block. The cache is wired, so the gauge is included.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-9-platform-daily-ceiling`.

2. Shared names, `packages/shared/src/telemetry.ts`. Add `INSTR_GATEWAY_PLATFORM_SPEND_RATIO = "helix.gateway.platform_spend_ratio"` to the instrument block, and extend the array the SP-7 task created: `ADMISSION_DENIAL_REASONS = ["app_budget_day", "app_budget_burst", "platform_ceiling"] as const`. Update the pin in `packages/shared/src/telemetry.test.ts`. `ATTR_ENV` (`helix.env`) already exists. Check the new instrument name is free: `grep -rn "platform_spend_ratio" packages apps docs`.

3. Config, `apps/edge/src/config.ts`. Add `platformDollarsPerDay: number;` to the `llm` block (docblock: `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY`; `0`/unset disables; the edge only; the dev gateway ignores it) and parse it in `loadGatewayConfig` (lines 754-764) with the `requireNonNegativeNumber` helper the SP-6 task added:

```ts
      platformDollarsPerDay: requireNonNegativeNumber(
        env.EDGE_LLM_PLATFORM_DOLLARS_PER_DAY,
        0,
        "EDGE_LLM_PLATFORM_DOLLARS_PER_DAY",
      ),
```

   Add `platformDollarsPerDay: 0` to both fixtures in `apps/edge/src/test/config.ts`. Config tests in `apps/edge/src/config.test.ts` (style of the reconcile-interval case, line 102): unset and blank give 0; `"100"` is honored; `"0"` is accepted; `"-1"`, `"abc"`, `"NaN"`, `"Infinity"` throw naming the variable.

4. The usage store, `apps/edge/src/gateway/usage.ts`.
   - Interface `UsageStore` (line 235): add `platformLlmSpendMicroUsd(env: Env): Promise<LlmSpend>` with a docblock: the platform-wide LLM spend across all apps for one env, from the definer function; cached per instance; throws when the read fails. Reuse the existing `LlmSpend` type (line 228).
   - `PgUsageStore` (line 282): add a constructor option `platformCacheMs?: number` (default `PLATFORM_SPEND_CACHE_MS = 5_000`, `0` disables caching, for tests), a `Map<Env, { at: number; value: LlmSpend }>` cache and a `Map<Env, Promise<LlmSpend>>` of in-flight reads (single flight: concurrent callers share one query):

```ts
  async platformLlmSpendMicroUsd(env: Env): Promise<LlmSpend> {
    const hit = this.#platformCache.get(env);
    if (hit && Date.now() - hit.at < this.#platformCacheMs) return hit.value;
    let read = this.#platformInflight.get(env);
    if (!read) {
      read = this.#readPlatform(env)
        .then((value) => {
          this.#platformCache.set(env, { at: Date.now(), value });
          return value;
        })
        .finally(() => this.#platformInflight.delete(env));
      this.#platformInflight.set(env, read);
    }
    return read;
  }

  async #readPlatform(env: Env): Promise<LlmSpend> {
    // Straight on the pool, not withPartition: the function takes the env itself, and a
    // partition would set an app GUC that means nothing here.
    const result = await this.#pool.query(
      "SELECT today, hour FROM platform_llm_spend_micro_usd($1)",
      [env],
    );
    const row = result.rows[0] as { today: string | number; hour: string | number } | undefined;
    return { todayMicro: row ? Number(row.today) : 0, hourMicro: row ? Number(row.hour) : 0 };
  }
```

     A failed read is not cached and not retried inside the TTL window of a good value; a rejected `read` is removed by `.finally`. Add `peekPlatformSpend(env): LlmSpend | null` returning the last cached value with no I/O (for the gauge).
   - The boot self-test. Add an exported SQL string and a pure classifier so the logic is testable without breaking the shared database:

```ts
export const PLATFORM_SPEND_CHECK_SQL = `
  SELECT p.prosecdef AS definer,
         EXISTS (SELECT 1 FROM pg_policies pol
                 WHERE pol.schemaname = 'public' AND pol.tablename = 'gateway_calls'
                   AND pol.policyname = 'gateway_calls_owner_read'
                   AND pg_get_userbyid(p.proowner) = ANY (pol.roles)) AS owner_policy
  FROM pg_proc p
  WHERE p.proname = 'platform_llm_spend_micro_usd' AND p.pronamespace = 'public'::regnamespace`;

export type PlatformSpendCheck =
  | { status: "ok" }
  | { status: "misconfigured"; problem: string }
  | { status: "unreachable"; error: unknown };
```

     `classifyPlatformSpendCheck(rows)` returns `misconfigured` with a plain-text `problem` for no row (function missing), `definer = false`, or `owner_policy = false`. `PgUsageStore.checkPlatformSpendFunction()` runs the SQL, classifies, then calls `SELECT * FROM platform_llm_spend_micro_usd('prod')` once; a Postgres error code `42501` (insufficient privilege) or `42883` (undefined function) is `misconfigured`, any other error is `unreachable`. The catalog query reads only public catalogs, so a failure there is `unreachable`.
   - `apps/edge/src/test/fakes.ts`, `FakeUsageStore` (line 202): add `platformSpendTodayMicro?: number`, `platformSpendHourMicro?: number` (overrides; default is the sum of every `llm` record in `records`, the way `llmSpendMicroUsd` sums) and `platformReadError?: Error` (when set, `platformLlmSpendMicroUsd` rejects). No other class implements `UsageStore`: `apps/connections-lane/src/world.ts:584` only constructs a `PgUsageStore`. Run `grep -rn "implements UsageStore\|UsageStore = {" apps packages` to be sure.

5. The handler, `apps/edge/src/gateway/llm.ts`.
   - Add `platformCeilingDollars: number;` to `LlmGatewayRuntime` (0 = off). `apps/edge/src/app.ts` passes `config.llm.platformDollarsPerDay` in `llmRuntime` (line 259); `apps/edge/src/devGateway/app.ts` passes `0` in its `llmRuntime` (line 134) with the comment that `helix_dev` has no `EXECUTE` on the function and the dev tier has no ceiling.
   - Refactor the SP-7 denial block into one local helper used by both checks, so the metric, span attribute, throttle, log and row stay identical:

```ts
    const recordDenial = async (reason: AdmissionDenialReason, errorDetail?: string) => {
      meterGatewayCall({ appId: entry.appId, capability: "llm", outcome: "quota_blocked" });
      meterAdmissionDenied({ appId: entry.appId, capability: "llm", reason });
      trace.getActiveSpan()?.setAttribute(ATTR_REASON, reason);
      const decision = rt.denialThrottle
        ? await rt.denialThrottle.admit(entry.appId, caller.env, "llm")
        : { meter: true as const, suppressedAt: undefined };
      if (decision.suppressedAt !== undefined) {
        req.log.warn(
          { appId: entry.appId, env: caller.env, reason, attempts: decision.suppressedAt },
          "quota-denial metering suppressed: this app is over its denial budget for the window",
        );
      }
      if (decision.meter) {
        await usage
          .record({
            appId: entry.appId, env: caller.env, ...identity, capability: "llm", model: chat.model,
            inputTokens: 0, outputTokens: 0, costMicroUsd: 0, outcome: "quota_blocked",
            ...(errorDetail ? { errorDetail } : {}),
          })
          .catch(() => {});
      }
    };
```

   - After the per-app block (it ends at the closing brace of `if (cap > 0) { ... }`), add the ceiling check:

```ts
    if (rt.platformCeilingDollars > 0) {
      let platform: LlmSpend;
      try {
        platform = await usage.platformLlmSpendMicroUsd(caller.env);
      } catch (err) {
        // Fail closed: an unreadable ceiling is not an absent ceiling.
        req.log.warn({ err, event: "gateway.platform_spend_unavailable" }, "platform spend read failed");
        reply.header("retry-after", "5");
        codec.error(reply, 503, "capability_unavailable", "platform budget check unavailable");
        return;
      }
      if (platform.todayMicro >= rt.platformCeilingDollars * 1_000_000) {
        await recordDenial("platform_ceiling", "platform_ceiling");
        reply.header("retry-after", String(secondsUntilNextLocalMidnight()));
        codec.error(reply, 503, "capability_unavailable", "platform LLM budget exhausted for today");
        return;
      }
    }
```

     Import `type LlmSpend` from `./usage.js` and `AdmissionDenialReason`. Add and export `secondsUntilNextLocalMidnight(now = new Date()): number` (`const next = new Date(now); next.setHours(24, 0, 0, 0); return Math.max(1, Math.ceil((next.getTime() - now.getTime()) / 1000));`). It assumes the edge process and the database session share a time zone (both UTC on Container Apps and the dev container); say so in its comment, because `date_trunc('day', now())` runs in the database session's time zone. The `retry-after` value is advisory.

     Keep the order: replica/lease checks added later come after both budget checks.

   - Document the overshoot bound in the comment above the check.

6. Boot wiring, `apps/edge/src/server.ts`. Before `await app.listen(...)` (inside the existing `try`, which logs and exits on a throw), when `config.llm.platformDollarsPerDay > 0` and `usage instanceof PgUsageStore`:

```ts
  const check = await usage.checkPlatformSpendFunction();
  if (check.status === "misconfigured") {
    throw new Error(`platform LLM ceiling is enabled but the database is misconfigured: ${check.problem}`);
  }
  if (check.status === "unreachable") {
    app.log.warn({ err: check.error, event: "platform_ceiling.selftest_unreachable" }, "platform ceiling self-test could not reach the database; per-call reads fail closed");
  }
```

     Add `llmPlatformDollarsPerDay: config.llm.platformDollarsPerDay` to the `boot.serving` log object (line 311). Attach the gauge near the other gauge wiring (see `apps/edge/src/routing/trustProxyHealth.ts:176-187` for the callback and `onClose` removal pattern): add `platformSpendRatio: ObservableGauge` to `EdgeInstruments` and `instruments()` in `apps/edge/src/telemetry.ts`, then in `server.ts` when the ceiling is on:

```ts
const ratioGauge = instruments().platformSpendRatio;
const observeRatio = (result: ObservableResult): void => {
  const spend = usage.peekPlatformSpend("prod");
  if (spend) result.observe(spend.todayMicro / (config.llm.platformDollarsPerDay * 1_000_000), { [ATTR_ENV]: "prod" });
};
ratioGauge.addCallback(observeRatio);
// and in the existing onClose hook: ratioGauge.removeCallback(observeRatio)
```

     The gauge is absent until the first read, which is the honest state. (`usage` is typed `UsageStore | null` in `server.ts`; narrow with `instanceof PgUsageStore` once and reuse the narrowed binding.)

7. Bicep.
   - `infra/azure/main.bicep`: add next to the SP-6 parameter (`llmDefaultDollarsPerDay`):

```bicep
@description('Platform-wide daily LLM spend ceiling in USD, enforced by the edge (EDGE_LLM_PLATFORM_DOLLARS_PER_DAY): once the day\'s spend across all apps reaches it, new LLM calls are refused with 503 until local midnight. -1 (default) derives one tenth of platformMonthlyUsdCap (100 when platformMonthlyUsdCap is 0, so hiding the portal watch line does not switch enforcement off). 0 switches the ceiling off, for a one-organization install (ADR-0028). Needs the platform_llm_spend_micro_usd migration applied before the edge image.')
@minValue(-1)
param llmPlatformDollarsPerDay int = -1
```

     and a `var` beside `fetchMaxBodyBytes` (line 737): `var effectiveLlmPlatformDollarsPerDay = llmPlatformDollarsPerDay >= 0 ? llmPlatformDollarsPerDay : (platformMonthlyUsdCap > 0 ? max(1, platformMonthlyUsdCap / 10) : 100)`. Pass `{ name: 'EDGE_LLM_PLATFORM_DOLLARS_PER_DAY', value: string(effectiveLlmPlatformDollarsPerDay) }` on `edgeApp` only (next to `EDGE_LLM_OPENAI_CONNECTION`, line 1230); do **not** add it to `devGatewayApp`. Update the `platformMonthlyUsdCap` description (line 57): it is still the portal's display line, and the daily ceiling default now derives from it. Let `just infra build` settle any Bicep syntax question (`max()` and the conditional). Commented example lines go in `main.bicepparam` and `main.bootstrap.bicepparam` in the style of the existing `llmMonthlyBudgetUsd` line (`main.bicepparam:106`).
   - `infra/azure/modules/alerts.bicep`: add a rule after the trust-proxy rule (`resource trustProxyRule`, before the `notifies` output), modeled on rules 1 and 3 (`includeMetricRule` gate, `severity`, `autoMitigate: true`, KQL on one line):

```bicep
var platformCeilingQuery = 'AppMetrics | where Name == "helix.gateway.admission_denied" | where tostring(Properties["helix.reason"]) == "platform_ceiling" | summarize Denied = sum(Sum) by AppRoleName | where Denied > 0'
```

     Name it `${namePrefix}-alert-llm-platform-ceiling`, display name "LLM platform ceiling reached", description saying all LLM calls are being refused until local midnight. Update the module's header comment (the opening comment block, which lists the rules) to list the new rule. The `Properties` column name and the way the counter's `Sum` aggregates are **unverified in Azure**.

8. Tests.
   - `apps/edge/src/gateway/llm.test.ts`, new `describe("platform ceiling")`: (a) ceiling set (build the edge with `platformCeilingDollars`; extend `buildLlmEdge`), `platformSpendTodayMicro` at the ceiling, app well under its own budget: `503`, `capability_unavailable`, a numeric `retry-after` between 1 and 86400, provider never called, a `quota_blocked` row with `errorDetail: "platform_ceiling"`; (b) below the ceiling: served; (c) ceiling 0: served at any platform spend; (d) an app over its own budget with the platform also over: `429 quota_exceeded`, not `503`; (e) the denial rows stop at the throttle maximum (25 refusals, 20 rows) while `helix.gateway.admission_denied{reason=platform_ceiling}` counts 25; (f) `platformReadError` set: `503` with `retry-after: 5`, provider never called, the warn event logged, no ledger row; (g) a charged cut call (SP-5) counts toward the platform sum: hang up one call, then the fake's default platform sum includes it.
   - `secondsUntilNextLocalMidnight`: unit test with fixed dates, including a date at 23:59:59.5 (result 1) and a DST-change day if the container's zone has one (otherwise skip that case and say so).
   - `apps/edge/src/gateway/usage.rls.integration.test.ts` (runs as `helix_edge`): `PgUsageStore.platformLlmSpendMicroUsd` returns the cross-app sum (assert on a before/after difference, with `platformCacheMs: 0`); a row charged by a cut call (`outcome: "error"`, `costMicroUsd > 0`) is reflected; within the TTL a second read returns the cached value after a new row is inserted, and with `platformCacheMs: 0` it returns the new one; concurrent reads share one flight (assert both resolve to the same object).
   - `classifyPlatformSpendCheck` unit tests: no row, `definer = false`, `owner_policy = false`, all good. And an integration test that `checkPlatformSpendFunction()` returns `ok` against the migrated test database.
   - Telemetry: `gateway/telemetry.test.ts` for the new reason value and the gauge (`startRecordingTelemetry`, attribute keys exactly `helix.env`); `spanRedaction.test.ts` global scan covers a ceiling refusal (no prompt fragment, oid, URL or scope string in any attribute). Run the telemetry tests again with `OTEL_SDK_DISABLED=1`.

9. Docs: `docs/features/llm-gateway.md` "Quota" (lines 33-46): add the platform ceiling (what it counts, the 503 and `retry-after`, the 5-second cache and the overshoot bound, fail-closed reads, `0` to disable). `docs/features/observability.md`: add `platform_ceiling` to the `helix.gateway.admission_denied` row, a row for `helix.gateway.platform_spend_ratio` (observable gauge, `env`), and mention the alert. `infra/azure/README.md` (the Cost section at line 1033): the enforced daily ceiling, how its default derives, how to switch it off, and the migrate-before-edge ordering. `apps/docs/src/deploy/configuration.md`: a `llmPlatformDollarsPerDay` parameter row (the parameters table; the `platformMonthlyUsdCap` row is line 121), an `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY` variable row (the environment-variable tables; the first row of the `App(s)` table is line 199), and correct the `platformMonthlyUsdCap` row (it says nothing enforces it). `.env.example`: the variable, commented, default off locally.

10. Smoke with the ceiling on: the runner passes the shell environment to the services (`SVC_ENV = { ...process.env, ...STACK.env }` in `.claude/skills/run-helix/smoke.mjs`), so run `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100 just dev smoke`. The runner does not call the LLM, so this proves the edge boots with the ceiling enabled and the boot self-test passes against a freshly migrated database; the refusal itself is proven by the tests above. Say that in `results/`.

11. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (SP-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] The `llm.test.ts` ceiling cases and the integration tests pass; the probe-owner test from the SP-8 task still passes.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes, and `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=100 just dev smoke` passes (boot self-test). Output saved under `results/`.
- [ ] `just infra build` passes for the parameter, the derived variable, the env entry and the alert rule.
- [ ] Committed with `fest commit -m "SP-9: enforce the platform daily LLM ceiling"`.
- [ ] Unverified in Azure: the Bicep parameter and the edge environment wiring (compile-checked only); the alert rule's KQL (`Properties["helix.reason"]`, `sum(Sum)` on a counter in `AppMetrics`) and that it fires; that the production owner role admits the function under `FORCE` RLS (carried from the owner-policy task); that Azure Postgres local midnight matches the edge's, which the `retry-after` assumes.
