# Spend controls: stop abandoned streams, charge what was used, cap the platform

_Problem:_ Problem 1, "AI spend escapes the budget", in [00-frame.md](00-frame.md). _Findings:_ KP-2 (`notes/04-known-problems.md`), SEC-4 (`notes/07-security.md`), OPS-14 (`notes/08-operability.md`).

_Repository:_ `projects/helix` at `main` = `792557a`. Read-only design; nothing in the repository was changed. Anchors are lines I opened. Anything inferred and not checked is marked **Hypothesis**.

## Summary

Ship three parts in order, each as separate changes (see Work breakdown). The audience is treated as possibly hostile (D1), so the platform ceiling is required and on by default; each stricter control stays a per-install setting. **Part 1** passes the edge's hang-up from egress `POST /proxy` into the undici `request()` through an `AbortController` fed by `reply.raw` `close`, the pattern the edge already uses. It covers LLM and fetch calls with one change, and it does not touch the body caps, the shared dispatcher or the header stripping. Reading the code shows that a hang-up after the upstream headers arrive is probably already propagated today, so Part 1 closes the pre-header window and starts with a characterization test that shows whether a post-header hang-up already tears down the vendor call. **Part 2** makes a cut or failed stream charge something: the provider yields its token counts as soon as it has them, the handler tallies the bytes it relays, and the ledger row freezes `input = measured else estimated` and `output = max(measured, estimated)`, marked as estimated in `errorDetail` (D4). This keeps ADR-0021's append-only ledger and block-new rule; only the meaning of "frozen cost" widens. **Part 3** makes the budget real: an unset `dollarsPerDay` is enforced as an install default (the approval baseline, $50), a platform-wide daily ceiling is read through a `SECURITY DEFINER` aggregate function because RLS hides other apps' rows from the edge, and per-app and per-user concurrency caps are Postgres leases with a TTL so they hold across edge replicas. The weak point in Part 1 and Part 2 is that Part 2's estimate is a heuristic. Part 3 bounds the damage instead of making the gate exact: overshoot is at most `concurrency cap x worst-case call cost`, and the platform ceiling is the hard backstop.

## Current behavior

**Admission.** `handleLlmChat` checks the budget once, before the upstream call. `const cap = entry.llm.dollarsPerDay` (`apps/edge/src/gateway/llm.ts:187`) and the whole check sits inside `if (cap !== undefined)` (`llm.ts:188`). The day cap is `dollarsPerDay`; the burst cap is `dollarsPerDay / 6` over a rolling hour (`BURST_BUDGET_FRACTION`, `llm.ts:56`). A refusal writes a `quota_blocked` row per refused call with no throttle (`llm.ts:186-216`). The comment states the rule: an in-flight request is never cut.

**Where "unset" comes from.** `LlmCapabilitySchema.dollarsPerDay` is `.optional()` and documented "unset => unbounded" (`packages/shared/src/manifest.ts:29` and its comment). The classifier already treats unset as the most permissive value: `budgetPrivilege` returns `Infinity` for a grant with no number (`packages/shared/src/approval.ts:245-248`), and a change is elevated when it raises privilege above `BASELINE_DOLLARS_PER_DAY = 50` (`approval.ts:206, 325-334`). So a fresh grant with no number queues for human approval. The gap is the approved-unset state, which the edge enforces as unlimited. **Hypothesis:** an install holds such apps only if an admin approved an unset budget; I did not enumerate approval paths or the live installs' data.

**Quota read.** `PgUsageStore.llmSpendMicroUsd` sums `costMicroUsd` for one app inside `withPartition` (`apps/edge/src/gateway/usage.ts`, `llmSpendMicroUsd`). `gateway_calls` has `ENABLE` and `FORCE ROW LEVEL SECURITY`, and the edge policy is `USING ("appId" = current_setting('app.app_id', true)::uuid)` (`apps/portal/prisma/migrations/20260721033820_rls_gateway_calls_collection_items/migration.sql:36-47`). The edge role cannot sum across apps. `helix_edge` has `SELECT, INSERT` only on the table, so the ledger is append-only for it (`20260616000001_edge_role_grants/migration.sql:24`; ADR-0021).

**Hang-up, edge side.** The handler listens on `reply.raw` `close`, skips it when `writableEnded`, sets `clientGone`, aborts its `AbortController` and marks the span (`llm.ts:232-243`). The abort reaches the egress call through `HttpEgressProvider.proxy` as `signal: req.signal` (`apps/edge/src/gateway/egressProvider.ts:101`). The fetch handler uses the same pattern (`apps/edge/src/gateway/fetch.ts:338-341`).

**Hang-up, egress side.** `runProxy` calls `request(target.href, { method, headers, body: requestBody, dispatcher })` with no `signal` (`apps/egress/src/proxy.ts:606-611`). There is no listener for `close` anywhere in egress (grep of `proxy.ts` for `signal`, `AbortController` and `raw.on` returns only comments).

**What actually happens after a hang-up. Hypothesis, read from source and not executed.**

- *After the upstream headers arrive:* already propagated. `reply.send(cappedBody)` (`proxy.ts:692`) goes through Fastify's `sendStream`, whose `eos(res, ...)` calls `payload.destroy()` when the response closes while the source is open (`node_modules/.pnpm/fastify@5.12.5/.../lib/reply.js:861-877`). `payload` is the `capBody` transform, and `capBody` builds `pipeline(source, cap, ...)` so destroying `cap` destroys `source` (`packages/shared/src/bodyCap.ts:82-85`). `source` is undici's `upstream.body`, whose `_destroy` calls `kAbort` when the stream is destroyed before `end` (`undici@7.30.0/lib/api/readable.js:85-92`), which tears the socket down. A hang-up that arrives while the body streams therefore ends the vendor connection.
- *Before the upstream headers arrive:* not propagated. The handler is parked in `await request(...)` (`proxy.ts:606`), or earlier in the jti burn and secret resolution. It does not learn of the close until `request()` resolves. The vendor has by then read the whole prompt and is billing input tokens.
- *During an upload (fetch path):* already propagated for the same reason. A dead inbound socket errors `req.raw`, which errors the `capBody` request stream and fails the undici upload.

So the "open N streams, hang up, vendor runs to completion" description in KP-2 and `TODO.md:58` overstates the output side. The accurate leak is the **pre-header window**, and above all that **the ledger records $0** for what the vendor billed (input tokens, plus whatever output was generated). Part 1's first task is a test that settles this, before any code changes.

**Why the ledger records $0.** `finalUsage` is zero-initialised (`llm.ts:248`) and filled only from the provider's `done` event (`Object.assign(finalUsage, ev.usage)` at `llm.ts:342` and `llm.ts:383`). `mapAnthropicStream` reads `input_tokens` at `message_start` and `output_tokens` at `message_start` and `message_delta`, but yields them only inside `done` (`provider.ts:98-155`). `mapOpenAiStream` reads usage only from the final chunk and throws `openai stream ended without a usage block` if it never arrives (`provider.ts:235-277`). A hang-up throws first; `recordOnce("error", { errorDetail: CLIENT_DISCONNECTED })` runs with the zero `finalUsage` (`llm.ts:356-358`, non-stream `llm.ts:395`). The row also keeps the default `finalStopReason = "end_turn"`, which is false for a cut call.

**Counting cadence. Hypothesis, from the vendor wire format and not checked in this repo or a vendor doc.** Anthropic's `message_delta` carries cumulative `output_tokens` and normally arrives once near the end of the message, so mid-stream the edge has the input count (exact, from `message_start`) and about one output token. OpenAI reports nothing until its last chunk. The existing tests only show one `message_delta` per stream (`provider.test.ts:26, 196`; `egressLlmProvider.test.ts:31`). Part 2 is designed for this worst case.

**Concurrency and replicas.** The edge runs `minReplicas = 1`, `maxReplicas = 3` (`infra/azure/modules/containerapp.bicep:54-57`). There is no in-flight cap anywhere in the LLM or fetch handler (SEC-4; I found none in `llm.ts` or `fetch.ts`). The per-IP limiter covers anonymous callers only. ADR-0011 moved the shared limiters to Postgres (`PgCounterStore`, `counterStore.ts`) because per-process state multiplies the limit by the replica count. `DenialThrottle` is the one deliberately per-replica store, and its docblock says why that is acceptable (it damps write amplification and defends no limit).

**Anonymous callers share one identity.** `meterIdentity` maps every unauthenticated caller to a sentinel `ANON_USER_OID` (`apps/edge/src/auth/gate.ts:105-114`). A per-user cap keyed on `userOid` would be one bucket for all anonymous visitors on a public app.

**Platform ceiling.** `platformMonthlyUsdCap` is display-only (`packages/shared/src/deployment.ts:34-37`), defaults to 1000 in Bicep (`infra/azure/main.bicep:58`) and reaches the portal as `PLATFORM_MONTHLY_USD_CAP` (`main.bicep:1341`). Azure budgets notify and never enforce (OPS-14).

## Goals and non-goals

**Goals**

1. When the edge drops a call, egress stops waiting for, and stops draining, the upstream response, for LLM and fetch, without changing body caps, pooling or header stripping.
2. A cut or failed LLM call writes a ledger row that charges what the vendor most likely billed, marked as measured or estimated.
3. No admitted app runs without a daily spend limit, and no combination of apps can spend past a platform daily ceiling.
4. A bounded number of LLM calls per app and per user are in flight at once, across all edge replicas.
5. Each part ships and verifies independently; Part 1 does not depend on Part 2 or Part 3.

**Non-goals**

- Cutting an in-flight stream because the budget was crossed. ADR-0021 and `docs/features/llm-gateway.md:40-44` reject this and this design keeps that.
- Exact cost accounting for streams the vendor bills but the edge never sees (reasoning tokens that are not streamed, an edge process crash mid-stream). These stay as documented residuals.
- Defaults for `data.writesPerDay` and `fetch.requestsPerDay`, which have the same "unset means unlimited" shape. They bound platform load, not vendor dollars. Left unchanged (S4).
- Per-app storage and row quotas, and asset-serving limits (SEC-4 items that are not spend).
- Network-level controls and the CSP; those are Problems 2 and 3.


## Options

Each part has one chosen option. The others are under "Options not chosen".

### Part 1: propagating a hang-up to the upstream call

**Option 1A: `AbortController` fed by `reply.raw` `close`, passed as `signal` to `request()`.**
In `runProxy`, create the controller before the jti burn and secret resolution, listen once on `reply.raw`, abort only when `!reply.raw.writableEnded`, and pass `signal` to `request()`. An already-aborted signal makes `request()` reject without dialling, so a hang-up during resolution never dials the vendor. It is the same pattern as `llm.ts:232-243` and `fetch.ts:338-341`, including the two reasons recorded there: watch the response because `req.raw` `close` fires after the inbound body is drained, and use `writableEnded` not `writableFinished` because light-my-request never settles the latter. Covers LLM and fetch, because both are `POST /proxy`.
- *Shared dispatcher.* A signal abort of an in-flight HTTP/1.1 request destroys that one socket; a half-read connection cannot go back to the pool. Other pooled connections stay open, and no one calls `dispatcher.close()` or `destroy()`. Pooling is defeated only for the sockets of calls that were abandoned, which is the intended effect. The existing pooling test (`apps/egress/src/proxy.test.ts:427-453`) covers completed calls only, so it passes unchanged and is not evidence for this case; Part 1 adds a test (see Tests).
- *Body caps, header stripping, the 401 renew flag.* All of these run after `await request()` resolves (`proxy.ts:613-692`), so a signal that only affects the `request()` promise does not touch them. A hang-up after that point is already handled by the Fastify teardown described above.
- *Error handling.* An abort now lands in the existing `catch` (`proxy.ts:693`) as an abort error. Today that branch logs `upstream request failed` at `warn` and calls `fail(reply, 502, ...)` (`proxy.ts:707-716`), which would write to a dead socket and log noise for a normal event. Add a `clientGone` branch before the request-cap and SSRF branches that logs nothing at `warn` and returns without writing. The request-cap branch must still win when the cap tripped and the client is still connected, so the order is: `clientGone`, then `requestCapTripped`, then `SsrfBlockedError`, then the generic 502.
- *Telemetry.* The `finally` already marks `helix.client_disconnected` from `!reply.raw.writableEnded` (`proxy.ts:798`), and the attribute is already in `EGRESS_SPAN_ATTRS` (`apps/egress/src/spanAttributes.ts`). The recorded span outcome stays `ok` because no outcome header is set on this path; the attribute is what distinguishes it. No new egress attribute is needed.
- Risk: a spurious `close` aborts a good call. The `writableEnded` guard is the protection; the existing edge code has run in this form. A second risk is `AbortSignal` listener leaks; undici removes its listener when the request settles, and the controller is per request.

Part 1 starts with a characterization test (Tests, item 1) that records whether a hang-up after the upstream headers arrive already tears down the vendor call. Its result decides how the rest of Part 1 is described, not whether the pre-header fix is made.

### Part 2: charging cut and failed streams

All options keep the row append-only and leave the block-new rule alone; they differ in what number goes in `costMicroUsd`.

**Option 2B: counted tokens, with an estimate filling the gaps (decision D4).** A `usage` event delivers counts as soon as the provider has them. The handler keeps two byte tallies and applies a per-field rule when a call ends without `done`:
- `inputTokens` = the measured count if a usage event delivered one, else `ceil(requestBytes / BYTES_PER_TOKEN)`.
- `outputTokens` = `max(measured, ceil(relayedDeltaBytes / BYTES_PER_TOKEN))`. Max, not replace, because the vendor bills output generated up to the cancel, which is more than what streamed through, and a measured count can lag.
- `BYTES_PER_TOKEN` is a named constant in `packages/shared` (initial value 3, which over-counts typical English at about 4 and under-counts nothing the gate cares about; tunable). `requestBytes` is the UTF-8 length of `chat.system` plus every `chat.messages[].content`; `relayedDeltaBytes` is the sum of `Buffer.byteLength(ev.text)` the handler already iterates.
- Cost is then `costUsd({ model, ...usage })` as today, so the frozen figure uses the same rate table.
- The row is marked: `errorDetail` = `client_disconnected` (or the error text) followed by `;usage=measured|estimated|mixed`. `stopReason` is written as `null` for these rows, not the false default `end_turn`.
- When to estimate: on a client hang-up, or on an error after the upstream returned 200 and at least one event arrived. Not on an upstream 4xx or 5xx before the stream started (the vendor rejected the request and did not generate), and not when the abort happened before the call reached egress (a window of a few milliseconds around minting the instruction; the design accepts the small over-charge there rather than adding a "dispatched" signal).

The gate moves for the exploit, the number is bounded above by what the prompt and relayed text imply, and the row says it is an estimate. It is a heuristic and can be wrong by tens of percent in either direction (non-Latin text, code, reasoning models whose hidden tokens are billed but never streamed). Over-charging a hang-up only affects that app's own budget.

**How counts reach the handler.** Add `{ type: "usage"; usage: LlmUsage }` to `LlmStreamEvent` (`provider.ts`). `mapAnthropicStream` yields it at `message_start` and at `message_delta`, which is at most twice per call. `mapOpenAiStream` yields it when the final usage chunk is parsed, immediately before `done`. `RoutingLlmProvider` and `EgressLlmProvider` forward events with `yield*` and need no change. The handler's two loops (`llm.ts:342` stream, `llm.ts:383` non-stream) gain a branch that does `Object.assign(finalUsage, ev.usage)` and sets `receivedUsage`. Existing tests that compare whole event arrays (`provider.test.ts`, `openaiProvider.test.ts`, `egressLlmProvider.test.ts`) must be updated for the extra events. **Hypothesis:** I did not open how each of them asserts.

### Part 3: defaults, a platform ceiling, and concurrency caps

**3a. Unset `dollarsPerDay` means an install default (3a-1).** `effectiveCap = entry.llm.dollarsPerDay ?? defaultDollarsPerDay` in `llm.ts`, where `defaultDollarsPerDay` comes from a new `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`, defaulting to `BASELINE_DOLLARS_PER_DAY` (50) and never above it unless the operator sets it explicitly. To keep the classifier honest, `budgetPrivilege(true, undefined)` returns `BASELINE_DOLLARS_PER_DAY` for the LLM budget, so removing a cap is a reduction to the baseline and an unset grant is baseline, not elevated. Anyone who wants more than $50 gets a number and, above the baseline, an approval, exactly as for any other raise. This is a behavior change for already-approved unset apps (see Rollout). It closes OPS-14's "unlimited by default" with one comparison and needs no data migration. The classifier edit touches the shared package that the portal SPA also imports, so snapshot and catalogue tests move. The default is a per-install setting: an install on ADR-0028's one-organization model can raise it.

**3b. Platform-wide daily ceiling: `SECURITY DEFINER` aggregate function (3b-1), required and on by default (D1).** The edge reads spend through `withPartition`, and the RLS policy hides other apps' rows, so a cross-app sum needs a definer function. `platform_llm_spend_micro_usd(p_env text) RETURNS TABLE(today bigint, hour bigint)` sums `costMicroUsd` over `gateway_calls` for `capability = 'llm'` and returns two numbers, nothing per app. Precedent: `session_lookup` and `session_sweep` (`20260721035543_rls_sessions_definer_lookup/migration.sql`): `SECURITY DEFINER`, `SET search_path = pg_catalog, public`, schema-qualified table, `EXECUTE` revoked from `PUBLIC` and granted to `helix_edge` only. **A wrinkle that decides the migration:** that migration chose `ENABLE` over `FORCE` for `sessions` because under `FORCE` the owner is subject to RLS, and every policy there is role-scoped, so an owner-run definer function matches no policy and sees zero rows. `gateway_calls` is `FORCE`. The function therefore needs a policy that admits its owner: a `FOR SELECT TO <owner> USING (true)` policy on `gateway_calls`, with the role name bound at migration time (`format('%I', current_user)` inside the migration's `DO` block, so it is whatever role runs migrations). Decision S3 takes this route; before the migration lands, check the production owner name against `infra/azure/sql/01-roles.sql` (the dev bootstrap uses `helix`, `.devcontainer/db-init/01-roles.sql:4`; **Hypothesis:** I did not read the production file). A dedicated NOLOGIN role is the stricter alternative and needs `CREATEROLE`, which could not be confirmed for the Azure migration identity.

Why this does not weaken ADR-0002: its "Framing (2026-07-21)" paragraph says the GUC-keyed policy is a backstop against application bugs, and that an RCE can already `set_config('app.app_id', ...)` to read any app. The function returns an aggregate to a role that can already read every app one at a time, so it adds no reach; the real boundary, grant absence on secrets and the registry, is unchanged. The function and its owner policy get the same dedicated review the auth code gets. Cost: a platform-wide day scan per read. The table keeps `gateway_calls_createdAt_idx` (`20260615214956_gateway_calls_created_at_index`), which the dev-env migration did not drop (it dropped only the `appId` index, `20260722192440_dev_env_partition/migration.sql:35`), so the scan is index-assisted but still touches every capability's rows for the day. **Hypothesis:** that is fine at pilot volume; a partial index on `("createdAt") WHERE capability = 'llm'` is the fix if it is not. A per-replica cache of the two numbers (TTL a few seconds) keeps it to a handful of queries a minute.
- *Behavior at the ceiling:* refuse new LLM calls platform-wide with `503 capability_unavailable` ("platform LLM budget exhausted for today") and a `retry-after` to the next local midnight. No new shared error code: `API_ERROR_CODES` (`packages/shared/src/api.ts:134-173`) is a client contract, and `capability_unavailable` already means "the platform cannot do this now". The ceiling uses the same day boundary as the per-app check (`date_trunc('day', now())`, server-local midnight) so the two windows agree. A ceiling decision records a `quota_blocked` row with `errorDetail = platform_ceiling` through `DenialThrottle`, because a ceiling trip is exactly when every app floods at once, and unthrottled rows would turn the denial into a write flood. The existing per-app `quota_blocked` rows (`llm.ts:186-216`) are unthrottled; route them through the same throttle in the same change.
- *Knob:* `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY`. Bicep always supplies a value to a deployed edge, so the ceiling is on by default; the starting value is one tenth of `platformMonthlyUsdCap` (S2). `0` or unset disables it, which keeps local development unaffected and lets an install on ADR-0028's model switch it off explicitly. `platformMonthlyUsdCap` stays display-only, and the Bicep default for the enforced daily value is derived from it so the two cannot silently disagree.

**3c. Concurrency caps: Postgres leases with a TTL (3c-2) plus a per-replica semaphore.** New table `inflight_leases(id uuid, scope text, "expiresAt" timestamp, PRIMARY KEY (id, scope))` with an index on `(scope, "expiresAt")`; `helix_edge` gets `SELECT, INSERT, DELETE`, no RLS (the scope string embeds the app id, as `rate_counters` keys do), and the portal and egress roles are revoked, mirroring `20260721215912_shared_rate_counters_and_jti_burn`. Acquire is one short transaction: take `pg_advisory_xact_lock(hashtextextended(scope, 0))` for each scope in sorted order, count unexpired leases per scope, and insert one row per scope if every count is under its cap, otherwise insert nothing. The advisory lock makes check-then-insert atomic, which a plain `count(*)` then `INSERT` is not under READ COMMITTED. Release is a `DELETE` by lease id in the handler's `finally`, run **after** `recordOnce` has written the ledger row, so a freed slot never admits a call that cannot yet see the previous call's spend. A replica that crashes leaks its leases only until `expiresAt`. The TTL is the call deadline plus a grace period (see Failure paths), so it is tied to a number the edge enforces itself. This reuses what ADR-0011 chose (Postgres, no Redis) and costs two database round trips per LLM call, small next to a model call. Scopes: `llm:app:<appId>` always; `llm:user:<appId>:<userOid>` only for an authenticated caller. Anonymous callers share `ANON_USER_OID`, so a per-user scope would be one bucket for the whole public audience; they are covered by the app scope plus the existing per-IP limiter. Caps are per-install settings; `0` disables a cap.
- *Per-replica semaphore.* A semaphore for total in-flight LLM calls (`EDGE_LLM_MAX_IN_FLIGHT`) in front of the database acquire protects the replica's own sockets and event loop without a database lock on every call. That one is per-replica by design, so its docblock should say so, as `DenialThrottle`'s does.
- *Fetch path.* The lease store is generic. Wiring it into `fetch.ts` with its own scopes (`fetch:app:...`) and larger caps is the same code and bounds the egress sockets one app can hold, but fetch is not vendor spend. It ships behind its own config, after the LLM wiring.
- *Overshoot bound after Part 3.* Per app: at most `appCap` calls overlap an admission check, so the overshoot past `dollarsPerDay` is at most `appCap x worst-case call cost`, where worst-case cost is `maxTokens x output price` for the priciest allowed model. Platform: at most the ceiling plus the in-flight calls admitted before the cached read caught up. This is a bound, not an exact gate.
- *Wall-clock deadline.* Today's timeouts are idle timeouts (`bodyTimeout` in `HttpEgressProvider` and the egress dispatcher), so a slow stream can run indefinitely. **Hypothesis:** undici's `bodyTimeout` resets on each chunk; I did not check it in 7.30. Add `EDGE_LLM_MAX_CALL_MS` (default 10 minutes) and abort with `AbortSignal.any([abort.signal, AbortSignal.timeout(maxCallMs)])`. A deadline abort is an upstream-style error, not a hang-up, and is charged by the same Part 2 rule. It is also what bounds the lease TTL.

## Options not chosen

- **1B: use Fastify's `request.signal`.** The edge comments at `llm.ts:232-243` and `fetch.ts:330-337` record that it is wired to an unguarded `req.on('close')`, which fires when the body finishes arriving, so it would abort every POST at once.
- **1C: do nothing, document the pre-header residual.** The vendor still bills the input of every abandoned call, and egress sockets stay held for the whole time to first byte (bounded by `EGRESS_TIMEOUT_MS`, default 120 s, `apps/egress/src/config.ts:245`). Part 1 is small and removes that. It remains the fallback if 1A shows a defect.
- **2A: charge counted tokens only.** A cut Anthropic stream charges the input plus about one output token, an OpenAI stream charges $0, and a hang-up before `message_start` charges $0, so the exploit still pays nothing.
- **2C: pre-charge at admission, settle with a second row.** Two rows per call, a recovery story for orphaned pre-charges, and counting rules to revisit. It is the only option that also covers an edge crash mid-stream; revisit if that residual matters.
- **2D: do nothing, document the $0.** The exploit remains and the gate is blind to it.
- **Event-versus-callback for counts (an `onUsage` sink on `LlmStreamOpts`).** Same effect, but side-channel state in a pure generator. The event is used unless test churn proves too large.
- **3a-2: require a number at approval.** Needs a portal change and a data backfill, and the edge would still need the 3a-1 fallback for rows it has not seen. It could be added later; it does not replace 3a-1.
- **3a-3: leave unset as unbounded and document it.** An unbounded spend path for any approved app, which D1 rules out.
- **3b-2: dedicated accumulator table.** A second source of truth that can drift from `gateway_calls`, and `helix_edge` would need UPDATE on it, which lets a compromised edge reset the ceiling. A shared `rate_counters` row does not work: its `count` is `INTEGER` and `bump` adds 1 (`counterStore.ts`), and micro-USD would overflow at about $2,147 per day.
- **3b-3: portal computes a flag and pushes it through the registry projection.** Adds a polling loop and stale control-plane data for a number the gateway should own.
- **3b-4: alert only, as today.** Ruled out by D1: the ceiling is required.
- **3c-1: per-process in-memory semaphore as the only cap.** Each replica admits up to the cap, so the effective limit is `cap x replicas` (up to 3x here), the failure mode ADR-0011 documents. Kept only for the replica's own resources.
- **3c-3: reserve the worst-case cost at admission.** Changes the rule from block-new to block-if-it-might-exceed, an ADR-0021 amendment of substance, and `maxTokens` up to 128,000 (`packages/shared/src/llm.ts:119`) would block most requests near the cap.

## Recommendation

- **Part 1:** Option 1A, after a characterization test that records what happens today. It is a small, local change that matches the edge's pattern. Its value is the pre-header window and egress socket hygiene; the dollars come from Part 2.
- **Part 2:** Option 2B with the `usage` event (D4). It is the only option that makes the exploit visible to the gate under the worst cadence, and the row is honest about being an estimate.
- **Part 3:** 3a-1 (edge default at the approval baseline, with the classifier aligned), 3b-1 (definer aggregate function plus a per-replica cache, required and on by default per D1), and 3c-2 (Postgres leases) with a per-replica semaphore. Each stricter control is a per-install setting, so installs on ADR-0028's documented model can relax it. Together they bound spend by construction instead of relying on the post-hoc gate being timely.

The order is 1, 2, 3, and each part lands as separate changes. Part 2 is the highest value alone, because it makes the existing per-app gate see abandoned calls. Part 3a is the cheapest large fix. Parts 3b and 3c need migrations.

## Change by file

| File | Change | Notes |
| --- | --- | --- |
| `apps/egress/src/proxy.ts` | Part 1. Create an `AbortController` at the top of `runProxy`; `reply.raw.once("close")` aborts when `!writableEnded` and sets `clientGone`; pass `signal` to `request()` (`:606`); add a `clientGone` branch first in the `catch` (`:693`) that returns without `fail()` or the `warn`. | Body caps (`:598, :686`), response header stripping (`:660-685`) and the 401 flag are after `await request()`, unchanged. Existing `finally` already sets `helix.client_disconnected` (`:798`). |
| `apps/egress/src/proxy.test.ts`, `apps/egress/src/adversarial.test.ts` | Part 1 tests (see Tests). | Real-socket harness already exists at `adversarial.test.ts:464-515`; `inject()` cannot express a hang-up. |
| `apps/egress/src/telemetry.ts` | Part 1. Add a counter `upstreamAborts` on the `instruments()` object. | Dimension: `helix.capability` only. |
| `packages/shared/src/telemetry.ts` | Constants: `INSTR_GATEWAY_ADMISSION_DENIED`, `INSTR_GATEWAY_CUT_CHARGES`, `INSTR_EGRESS_UPSTREAM_ABORTS`, `ADMISSION_DENIAL_REASONS`, `CUT_CHARGE_BASES`, and `ATTR_USAGE_BASIS`. | Names are constants, never literals (AGENTS.md). Each constant lands in the change that first uses it. |
| `packages/shared/src/pricing.ts` or a new `packages/shared/src/usageEstimate.ts` | Part 2. `BYTES_PER_TOKEN` and `estimateCutUsage({ measured, requestBytes, relayedBytes })` returning counts plus a basis. | Pure function with unit tests; single place for the heuristic. |
| `apps/edge/src/gateway/provider.ts` | Part 2. Add `{ type: "usage"; usage: LlmUsage }` to `LlmStreamEvent`; yield it from `mapAnthropicStream` at `message_start` and `message_delta`, and from `mapOpenAiStream` before `done`. | `RoutingLlmProvider` and `EgressLlmProvider` forward unchanged. |
| `apps/edge/src/gateway/llm.ts` | Part 2: handle `usage` in both loops (`:342`, `:383`); count request and relayed bytes; in `recordOnce` apply `estimateCutUsage` for hang-up and post-200 errors; mark `errorDetail`; write `stopReason: null` on those rows; emit the cut-charge counter and `ATTR_USAGE_BASIS`. Part 3: `cap = entry.llm.dollarsPerDay ?? defaultDollarsPerDay` (`:187`); platform ceiling check after the app check; acquire and release leases around the call; `AbortSignal.any` with the deadline; route denials through `DenialThrottle`. | The block-new comment (`:185`) stays true; add a sentence that an abort by the client or the deadline is not a quota cut. |
| `apps/edge/src/gateway/usage.ts` | Part 3. `UsageStore.platformLlmSpendMicroUsd(env)` calling the definer function (outside `withPartition`, which would set a pointless app GUC), with a short per-instance cache. Add to the `UsageStore` interface and `FakeUsageStore`. | Interface change; check the dev gateway wiring for another implementer. |
| `apps/edge/src/gateway/leaseStore.ts` (new) | Part 3. `LeaseStore` interface, `PgLeaseStore` (advisory-locked acquire, `release`, `sweep`), `InMemoryLeaseStore` for tests. | Shape follows `counterStore.ts`; pool via `createEdgePool`. |
| `apps/edge/src/gateway/fetch.ts` | Part 3, last. Optional lease acquire and release around the egress call (`:338-421`), behind its own config. | Not vendor spend; separate caps. |
| `apps/edge/src/config.ts`, `apps/edge/src/server.ts` | Part 3. New knobs: `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY`, `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY`, `EDGE_LLM_MAX_APP_IN_FLIGHT`, `EDGE_LLM_MAX_USER_IN_FLIGHT`, `EDGE_LLM_MAX_IN_FLIGHT`, `EDGE_LLM_MAX_CALL_MS`. Build and close the lease store; schedule its sweep with the existing interval sweeps. | Defaults documented in `config.ts` comments; starting values are decision S2. Every control has an off value (`0`). |
| `packages/shared/src/approval.ts` | Part 3a. `budgetPrivilege` treats an unset LLM budget as `BASELINE_DOLLARS_PER_DAY`. | Only the LLM budget; data and fetch budgets are unchanged (S4). `approval.test.ts` cases move. |
| `packages/shared/src/manifest.ts`, `capabilityHelp.ts`, `catalogue.ts` | Part 3a. Reword "unset => unbounded" to "unset => the install default". | Agents read the catalogue; wrong text sends them chasing rejections. |
| `apps/portal/prisma/schema.prisma` and two new migrations | Part 3. Migration one: `platform_llm_spend_micro_usd` definer function and the owner-readable `SELECT` policy on `gateway_calls`, optional partial index. Migration two: `inflight_leases` table and grants. | Guarded `IF EXISTS (pg_roles ...)` idiom like the other grant migrations. Add cases to `role-split.integration.test.ts`. |
| `infra/azure/main.bicep` (+ the edge container-app env block), `main.bicepparam` | Part 3. Parameters `llmDefaultDollarsPerDay`, `llmPlatformDollarsPerDay`, concurrency caps; pass them as the edge env vars. | **Hypothesis:** the edge env block is near the other `EDGE_*` settings; I opened only the portal's `PLATFORM_MONTHLY_USD_CAP` at `main.bicep:1341`. Compile-checked only (`just infra build`); unverified in Azure. |
| `infra/azure/modules/alerts.bicep` | Part 3. A rule on `helix.gateway.admission_denied` with `reason = platform_ceiling`. | Presence alert; see Telemetry. Compile-checked only; unverified in Azure. |
| `.env.example`, `docs/features/llm-gateway.md`, `docs/features/observability.md`, `docs/features/capabilities-and-manifests.md`, `infra/azure/README.md` (Cost), `TODO.md:58` | New knobs and meanings, the instrument inventory, the unset-budget wording, the operator rollout notes, and closing the TODO. | The TODO text should state the corrected scope (pre-header window; $0 ledger). |
| `docs/adr/0021-metering-ledger.md`, `docs/adr/0002-postgres-role-split-rls.md`, new `docs/adr/0051-llm-admission-control.md` | See ADR impact. | |

## Failure paths

**Part 1.**
- *Signal fires after the upstream has answered:* a no-op; `request()` has already resolved, and the Fastify teardown handles the stream.
- *Signal fires while undici is connecting:* **Hypothesis:** undici rejects the request and drops the connecting socket; the validating connector (`makeValidatingConnector`) is not interrupted, so a connect may complete and idle in the pool. The abort-then-reuse test covers the observable result.
- *`close` fires spuriously on a keep-alive socket:* the `writableEnded` guard covers normal completion. Under `app.inject()` the response closes with `writableEnded` true, so no abort; tests that need a real hang-up use a listening server.
- *The abort and the request-cap trip race:* `clientGone` is checked first, so a disconnected client is not sent a 413 on a dead socket.
- *Listener removal:* `once` plus a per-request controller; nothing is registered on the shared dispatcher.

**Part 2.**
- *The ledger write fails or the DB is down:* unchanged. `recordOnce` swallows and logs `gateway.usage_record_failed` (`llm.ts:254-300`); the row is lost. The estimate does not make this worse.
- *Counts are incomplete or the vendor sends garbage:* `wireCount` already throws on a present-but-invalid count (`provider.ts`), which lands in the error path with whatever was measured so far. A throw in the middle of a `usage` event leaves earlier counts in `finalUsage`.
- *Estimate is wrong:* the row says `usage=estimated`, so a dashboard can separate it. An over-estimate charges the app's own budget; an under-estimate leaves some spend invisible, bounded by Part 3's overshoot bound.
- *Reasoning tokens and an edge crash mid-stream:* not covered. Reasoning tokens are billed and not streamed. A crash writes no row at all. Both are documented residuals; Option 2C is the answer to the crash if it matters.
- *Zero-length abort:* a hang-up with no prompt bytes still charges the input estimate. That is correct when the call reached the vendor, and a slight over-charge in the few-millisecond window before dispatch.

**Part 3.**
- *Platform ceiling disabled by an install:* `0` is the explicit off value, for installs on ADR-0028's one-organization model. A deployed edge always receives a value from Bicep, so off is a deliberate operator choice.
- *Definer function errors, the DB is down, or `EXECUTE` is missing:* the ceiling read throws. The per-app check at `llm.ts:189` already throws on a DB error and the request fails with a server error; the ceiling follows the same fail-closed behavior. A stale cache entry is used only within its TTL; after that a failed read refuses the call. **Hypothesis:** the unhandled throw becomes a 500 through Fastify's error handler; I did not trace it. A misconfigured migration (owner policy missing) returns zeros, which would silently disable the ceiling. Guard it: a startup self-test reads the function once, and an integration test pins a non-zero result with rows present.
- *Ceiling configured as zero, negative or non-numeric:* config parsing throws at boot for anything that is not a non-negative finite number; `0` is the explicit "off".
- *Lease acquire fails (DB down, lock timeout):* fail closed with `503 capability_unavailable`. The edge's statement timeout (`createEdgePool`) bounds how long a call waits on the advisory lock.
- *Lease release fails or the replica dies:* the row expires at `expiresAt`. The sweeper (`DELETE ... WHERE "expiresAt" < now()`) and the `> now()` predicate in the count mean an expired lease never counts even before it is swept.
- *Deadline fires:* the call ends as an upstream error, is charged by Part 2, and releases its lease. A lease TTL shorter than the deadline would let a live call hold no slot; the TTL is `maxCallMs` plus a grace period, so it never is.
- *Anonymous caller:* no user scope, only the app scope; the per-IP limiter still applies.
- *Default misconfigured high:* `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` is an operator knob and is not clamped to the baseline (the classifier reads the baseline constant). If it is raised, an unset grant is enforced above what the classifier showed the approver. The config comment and the ADR say so; the boot log prints the effective default.

## Tests

All tests run locally: unit and integration suites through `./check-and-lint.sh` in the dev container (Postgres integration tests against the dev database), and the smoke runner (`node .claude/skills/run-helix/smoke.mjs`) for changes that touch running services. Azure behavior is not tested; Bicep is compile-checked only and labeled **unverified in Azure**.

**Part 1: `apps/egress/src/proxy.test.ts` (new `describe`, real socket as in `adversarial.test.ts:464-515`).**
1. *Characterization, written first and committed green before the fix:* an upstream that streams slowly; the client aborts after the first chunk; assert the upstream sees its request close and egress opens no new connection. This tests the Hypothesis that the post-header case already propagates. If it fails, the current-behavior section here is wrong.
2. *Pre-header abort (red before the fix):* an upstream that delays its response headers; the client aborts the egress call; assert the upstream request is closed well before the delay elapses and that the egress span carries `helix.client_disconnected = true`.
3. *Abort during secret resolution:* a resolver that waits, abort while it waits, assert `request()` is never dialled (upstream sees no connection).
4. *Pooling survives:* after an abandoned call, a second call to the same origin succeeds, and N sequential completed calls still reuse sockets (the existing test at `proxy.test.ts:427-453` stays unchanged and green).
5. *Caps unchanged under the signal:* the existing request-cap 413 and chunked-response truncation tests in `adversarial.test.ts` (the `egress body-size cap (issue #8)` block) stay green; add one where the cap trips with the client still connected and assert 413, and one where the client is gone and assert no write and no `warn` for `upstream request failed`.
6. *Header stripping unchanged:* the echo-back tests in `adversarial.test.ts:278` stay green.
7. *Both capabilities:* one test for an `llm` instruction and one for a `fetch` instruction.

**Part 2: `apps/edge/src/gateway/llm.test.ts` and `provider.test.ts`.**
1. Extend the real-socket hang-up test at `llm.test.ts:560-607`: the abort now writes a row with `outcome: "error"`, `errorDetail` starting `client_disconnected;usage=`, `costMicroUsd > 0`, `stopReason` null. Today it asserts only outcome and detail.
2. *The exploit:* abort before any delta (provider emits no `usage` event) and assert the input estimate is charged, so the daily gate moves; then a second request against a budget set just below that figure is `quota_blocked`.
3. *Measured wins where exact:* provider emits `usage { inputTokens: 1200 }` then deltas, abort; assert input is exactly 1200 (not the estimate) and output is `max(measured, estimate)`.
4. *OpenAI shape:* the stream throws `openai stream ended without a usage block`; the post-200 error path charges the estimate; an upstream 429 or 400 before any event charges 0.
5. *Non-streaming path:* same abort with `stream: false`.
6. *Mapper tests:* `provider.test.ts` and `openaiProvider.test.ts` assert the new `usage` events, including a numeric-string count and a `1e999` count still failing through `wireCount`.
7. `estimateCutUsage` unit tests in `packages/shared`: zero bytes, multibyte text, huge input does not overflow, never negative, never `NaN`.

**Part 3.**
- `llm.test.ts`: unset `dollarsPerDay` is refused at the default cap (day and burst); an explicit larger number is honored; the platform ceiling refuses an app that is under its own budget; the denial row is throttled after the window max; a ceiling read failure refuses the call.
- `leaseStore` unit tests with the in-memory store, and `leaseStore.integration.test.ts` against Postgres: concurrent acquires never exceed the cap (the race a bare count would lose); an expired lease frees its slot without a sweep; release after crash-simulation; two stores on separate pools (two replicas) share the cap.
- `llm.test.ts`: per-user cap 1 refuses a second concurrent call from the same user and admits a different user; an anonymous caller is not bucketed by user; a lease is released after the ledger row is written (assert order).
- `usage.integration.test.ts` and `usage.rls.integration.test.ts`: the definer function returns the cross-app sum while a direct `SELECT` as `helix_edge` without a GUC still returns zero rows, and the function returns no per-app breakdown.
- `role-split.integration.test.ts`: `helix_edge` can `EXECUTE` the function; `helix_portal` and `helix_egress` cannot; `helix_edge` still has no `UPDATE` or `DELETE` on `gateway_calls`.
- `approval.test.ts`: unset LLM budget classifies as baseline; a raise above 50 is elevated; removing a cap is a reduction.
- Adversarial: an app that opens many concurrent streams and hangs up (the KP-2 exploit end to end with the fake provider): the ledger moves, the lease count returns to zero, and the platform spend read reflects the charge.

## Telemetry

New signals, with names added to `packages/shared/src/telemetry.ts` and instruments added to the edge and egress `instruments()` objects.

| Signal | Kind | Dimensions | Notes |
| --- | --- | --- | --- |
| `helix.gateway.admission_denied` | edge counter | `helix.capability`, `helix.reason` in `ADMISSION_DENIAL_REASONS`, `helix.app_id` | Reasons: `app_budget_day`, `app_budget_burst`, `platform_ceiling`, `concurrency_app`, `concurrency_user`, `concurrency_replica`. Bounded set. `userOid` is never a dimension. |
| `helix.gateway.cut_charges` | edge counter | `helix.app_id`, `helix.usage.basis` in `measured`, `estimated`, `mixed` | Operational only; never reconciled with the ledger (ADR-0037 decision 9). Alert on a high share of `estimated`, which means the vendor is not delivering counts. |
| `helix.egress.upstream_aborts` | egress counter | `helix.capability` (`llm` or `fetch`) | Incremented in the `clientGone` branch. |
| span attribute `helix.usage.basis` | on `helix.gateway.llm` | none | Set when a call ends without `done`. |
| span attribute `helix.reason` | on `helix.gateway.llm` | none | Already exists (`ATTR_REASON`); set to the denial reason on a refusal. |
| Optional gauge `helix.gateway.platform_spend_ratio` | edge observable gauge | `helix.env` | Cached spend over the ceiling, attached in `server.ts` like the registry gauges. Lets an alert fire at 80% before the block. Omit if the cache is not wired. |

No new egress span attribute is needed: `helix.client_disconnected` is already allowlisted. Metering rows are not telemetry; the ledger remains the authority.

**Adversarial suites to extend.** `apps/egress/src/spanAttributes.test.ts`: add a recorded span for a hang-up and assert its keys stay within `EGRESS_SPAN_ATTRS` and carry no header names or error text. `apps/edge/src/spanRedaction.test.ts`: add denial and cut-charge calls and assert no attribute value contains a URL, a `userOid`, a prompt fragment or a lease scope string. `apps/edge/src/traceBoundary.test.ts` needs no change (nothing new extracts context). `apps/edge/src/gateway/telemetry.test.ts`: assert each new counter's dimensions with `startRecordingTelemetry`. Update the span and instrument tables in `docs/features/observability.md`. Verify the change still behaves with `OTEL_SDK_DISABLED=1`.


## Rollout and migration

Nothing here is rolled out to the two live installs. The work stays in the private fork (V1), CI stays off, and every change is proven locally with `./check-and-lint.sh` (or `just check`) in the dev container, plus the smoke runner (`node .claude/skills/run-helix/smoke.mjs`, also `just dev smoke`) where a change affects running services. Bicep is compile-checked with `just infra build`. Anything that only Azure can prove is labeled **unverified in Azure**.

**New installs built from the fork.** All parts arrive with the template. Bicep supplies the platform ceiling and the default budget, so a fresh deployment is enforced from the first request. The Part 3 migrations run with the others.

**Operator rollout notes.** For the operator of an existing install, in this order:
1. **Parts 1 and 2 (egress and edge images).** Build and deploy the new egress and edge images. No data migration. Part 2 changes what new `error` rows contain; historical rows keep their $0.
2. **List approved apps with no budget (S1).** Run `SELECT slug FROM apps WHERE capabilities->'llm' IS NOT NULL AND capabilities->'llm'->>'dollarsPerDay' IS NULL` (**Hypothesis:** the column and JSON path names are inferred from `parseLlmCapability`, not checked against the Prisma schema). These apps are unlimited today and become $50 per day when Part 3a deploys. Set an explicit number for each through the portal, or deploy with `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` set higher for a transition and lower it afterwards. Skipping this step means refusals on the first busy day.
3. **Apply the Part 3 migrations before the edge image that uses them.** An edge that starts without the function or the lease table fails closed on its first ceiling or lease call, so the migrate step goes first. Before applying, confirm the migration identity's role name matches the owner policy on `gateway_calls` (see `infra/azure/sql/01-roles.sql`).
4. **Choose the platform ceiling.** The Bicep default is one tenth of `platformMonthlyUsdCap` per day. Set it from the install's own ledger data; an untuned value either blocks real use or never trips. An install on ADR-0028's one-organization model may set `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY=0` to switch it off, and should say so in its own notes.
5. **Apply the new IaC template.** A Bicep default does not reach an install until the operator applies the template with their own parameters. Set the concurrency caps and call deadline there.
6. **Mixed replicas.** The edge tolerates an unset ceiling (disabled), so a rolling deploy with old and new replicas does not refuse calls.

**Rollback.** Parts 1 and 2 roll back with the image. Each Part 3 control has an off value (`0`); the migrations are additive and can stay.

**Verification limits.** The ceiling, leases, defaults and abort behavior are proven against local Postgres and the dev container. The Bicep parameters, edge environment wiring and the alert rule are compile-checked only and stay **unverified in Azure**.

## ADR impact

- **ADR-0021 (amendment).** (1) A frozen `costMicroUsd` may be an estimate for a call that ended without a final usage block, and the row says so. (2) The Decision's wording is stale: budgets are USD, not tokens, and the ADR already notes the doc was reconciled; align the Decision. (3) Block-new is unchanged. State that aborts by the client or by the wall-clock deadline are not quota cuts, so the "never cut" rule still holds. No change to append-only.
- **ADR-0002 (amendment).** Record the new definer function and the owner `SELECT` policy on `gateway_calls`, and why they add no reach (aggregate-only, to a role that can already read per app by setting the GUC), citing the 2026-07-21 framing paragraph. Record the `inflight_leases` grants.
- **New ADR-0051, LLM admission control.** Decisions: an unset budget means the install default; a platform-wide daily ceiling enforced at the gateway, required and on by default; per-app and per-user in-flight caps as Postgres leases with a TTL, plus a per-replica semaphore for replica resources; each control a per-install setting; refusal semantics (`503 capability_unavailable`, throttled `quota_blocked` rows with an `errorDetail` marker); and the rejected alternatives (worst-case reservation, accumulator table, alert-only). It supersedes nothing; it extends ADR-0021.
- **ADR-0011 (one-line pointer).** The lease store follows the Postgres-counter choice in its Resolution.
- **ADR-0028.** The platform ceiling and concurrency caps are per-install settings so one-organization installs can relax them. The amendment is shared with the other two designs (review.md, dependency 2).
- **ADR-0008** is not changed; Part 1 does not alter who holds the vendor key.

## Open questions

The decisions answered the earlier questions: D1 (ceiling required and on by default), D4 (measured else estimate), S1 (list apps, then deploy the default, now an operator rollout note), S2 (starting values), S3 (owner policy), S4 (no change to `writesPerDay` and `fetch.requestsPerDay`). Two items remain:

1. **Production migration owner role.** S3 chooses a `SELECT` policy for the migration owner. SP-8 must first read `infra/azure/sql/01-roles.sql` and confirm the production owner name; if the policy cannot be bound to the role that runs migrations, the dedicated NOLOGIN role needs `CREATEROLE`, which is unconfirmed.
2. **Starting values are not measured.** The S2 values ($50 per app, $100 per day platform, 10 per app, 3 per user, 10-minute deadline) and `BYTES_PER_TOKEN = 3` are guesses until an install shows its traffic. Each is a setting or a named constant, so they can change without a redesign.

## Work breakdown

Changes in the order they should land. Parts 1, 2 and 3 are separate changes; no change below mixes two parts. Each runs `./check-and-lint.sh` in the dev container before it lands; "smoke" means `node .claude/skills/run-helix/smoke.mjs`.

### SP-1 Characterization test for hang-up propagation (Part 1)
- **Depends on:** none
- **Files:** `apps/egress/src/proxy.test.ts` (new `describe`, real socket as in `adversarial.test.ts:464-515`)
- **Done when:** a test starts a slow-streaming upstream, has the client hang up after the first chunk, and asserts whether the upstream sees its request close and egress opens no new connection. The test is committed passing on current code with its result recorded in the test comment, and this document's "What actually happens after a hang-up" section is corrected if the result disagrees.
- **Evidence:** the new test and `./check-and-lint.sh` in the dev container. Nothing Azure-specific.

### SP-2 Propagate the edge hang-up into the egress upstream call (Part 1)
- **Depends on:** SP-1
- **Files:** `apps/egress/src/proxy.ts`, `apps/egress/src/telemetry.ts`, `packages/shared/src/telemetry.ts` (`INSTR_EGRESS_UPSTREAM_ABORTS`), `apps/egress/src/proxy.test.ts`, `apps/egress/src/adversarial.test.ts`, `apps/egress/src/spanAttributes.test.ts`, `docs/features/observability.md`
- **Done when:** a hang-up before the upstream headers arrive closes the upstream connection well before the upstream's delay elapses; a hang-up during secret resolution never dials the vendor; a hang-up writes no 502 and no `upstream request failed` warning; a cap trip with the client connected still returns 413; both `llm` and `fetch` instructions are covered; pooling still works after an abandoned call; `helix.egress.upstream_aborts` increments with `helix.capability` only.
- **Evidence:** Tests, Part 1 items 2 to 7; existing cap, header-stripping and pooling tests unchanged and green; `spanAttributes.test.ts` key allowlist check; smoke confirms egress still proxies a call. Nothing here is Azure-specific.

### SP-3 Cut-stream usage estimate in shared (Part 2)
- **Depends on:** none (ordered after Part 1 by the plan)
- **Files:** `packages/shared/src/usageEstimate.ts` (or `pricing.ts`) and its test
- **Done when:** `BYTES_PER_TOKEN` and `estimateCutUsage({ measured, requestBytes, relayedBytes })` exist and return input as measured else `ceil(requestBytes / BYTES_PER_TOKEN)`, output as `max(measured, ceil(relayedBytes / BYTES_PER_TOKEN))`, and a basis of `measured`, `estimated` or `mixed`.
- **Evidence:** unit tests for zero bytes, multibyte text, huge input without overflow, never negative, never `NaN`; `./check-and-lint.sh`.

### SP-4 `usage` events from the provider mappers (Part 2)
- **Depends on:** none (ordered after SP-3 by the plan)
- **Files:** `apps/edge/src/gateway/provider.ts`, `provider.test.ts`, `openaiProvider.test.ts`, `egressLlmProvider.test.ts`
- **Done when:** `mapAnthropicStream` yields `usage` at `message_start` and `message_delta`, `mapOpenAiStream` yields it before `done`, routing and egress providers forward it, and `wireCount` still rejects a present-but-invalid count (a `1e999` count fails, a numeric string passes).
- **Evidence:** updated mapper tests; `./check-and-lint.sh`; smoke confirms a normal LLM call still completes.

### SP-5 Charge cut and failed LLM calls (Part 2)
- **Depends on:** SP-3, SP-4
- **Files:** `apps/edge/src/gateway/llm.ts`, `llm.test.ts`, `packages/shared/src/telemetry.ts` (`INSTR_GATEWAY_CUT_CHARGES`, `CUT_CHARGE_BASES`, `ATTR_USAGE_BASIS`), `apps/edge/src/gateway/telemetry.test.ts`, `apps/edge/src/spanRedaction.test.ts`, `docs/adr/0021-metering-ledger.md`, `docs/features/observability.md`
- **Done when:** a client hang-up, or an error after a 200 with at least one event, writes a row with `outcome: "error"`, `errorDetail` ending `;usage=measured|estimated|mixed`, `costMicroUsd > 0` and `stopReason: null`; an upstream 4xx or 5xx before the stream starts charges 0; measured input wins where delivered; the daily gate then refuses the next request when the estimate crosses the budget; the non-streaming path behaves the same; ADR-0021 is amended.
- **Evidence:** Tests, Part 2 items 1 to 5; telemetry assertions with `startRecordingTelemetry` and the redaction suite (no URL, `userOid` or prompt fragment in attributes); behavior with `OTEL_SDK_DISABLED=1`; `./check-and-lint.sh`; smoke. Estimate accuracy against real vendors is not tested here; the heuristic is labeled an estimate in every row.

### SP-6 Install default for unset `dollarsPerDay` (Part 3a)
- **Depends on:** none (ordered after Part 2 by the plan)
- **Files:** `apps/edge/src/config.ts`, `apps/edge/src/server.ts`, `apps/edge/src/gateway/llm.ts`, `packages/shared/src/approval.ts`, `manifest.ts`, `capabilityHelp.ts`, `catalogue.ts`, their tests, `.env.example`, `infra/azure/main.bicep` and `main.bicepparam` (`llmDefaultDollarsPerDay`)
- **Done when:** an unset `dollarsPerDay` is enforced at `EDGE_LLM_DEFAULT_DOLLARS_PER_DAY` (default 50) for both the day cap and the hourly burst cap; an explicit larger number is honored; an unset grant classifies as baseline, a raise above 50 as elevated, and removing a cap as a reduction; the boot log prints the effective default; catalogue text no longer says "unbounded".
- **Evidence:** `llm.test.ts` and `approval.test.ts` cases (Tests, Part 3); catalogue and snapshot tests updated; `./check-and-lint.sh`; `just infra build` compile-checks the Bicep parameter. Bicep wiring is unverified in Azure.

### SP-7 Throttle and count admission denials (Part 3)
- **Depends on:** SP-6
- **Files:** `apps/edge/src/gateway/llm.ts`, `llm.test.ts`, `packages/shared/src/telemetry.ts` (`INSTR_GATEWAY_ADMISSION_DENIED`, `ADMISSION_DENIAL_REASONS`), `apps/edge/src/gateway/telemetry.test.ts`, `docs/features/observability.md`
- **Done when:** existing per-app `quota_blocked` rows go through `DenialThrottle`; each refusal increments `helix.gateway.admission_denied` with `helix.capability`, `helix.reason` (`app_budget_day`, `app_budget_burst` for now) and `helix.app_id`; the span carries `ATTR_REASON`; `userOid` is never a dimension.
- **Evidence:** a test that the denial row count stops at the throttle window max; telemetry dimension assertions; redaction test; `./check-and-lint.sh`.

### SP-8 Platform spend definer function and migration (Part 3b)
- **Depends on:** none (ordered after SP-7 by the plan)
- **Files:** a new migration under `apps/portal/prisma/migrations/`, `apps/portal/prisma/schema.prisma` if affected, `usage.integration.test.ts`, `usage.rls.integration.test.ts`, `role-split.integration.test.ts`, `docs/adr/0002-postgres-role-split-rls.md`
- **Done when:** the production owner role name is checked against `infra/azure/sql/01-roles.sql` and recorded in the PR; `platform_llm_spend_micro_usd(p_env)` is `SECURITY DEFINER` with pinned `search_path`, returns only `today` and `hour`, has `EXECUTE` revoked from `PUBLIC` and granted to `helix_edge` only; the owner `SELECT` policy exists on `gateway_calls`; a direct `SELECT` as `helix_edge` without a GUC still returns zero rows; `helix_edge` still has no `UPDATE` or `DELETE` on `gateway_calls`; ADR-0002 is amended.
- **Evidence:** integration tests against local Postgres: cross-app sum is non-zero with rows present (the case that catches a missing owner policy), no per-app breakdown, `helix_portal` and `helix_egress` cannot execute. The production Azure SQL role bootstrap is not exercised; that stays **unverified in Azure**. This change gets the same dedicated review the auth code gets.

### SP-9 Enforce the platform daily ceiling (Part 3b)
- **Depends on:** SP-7, SP-8
- **Files:** `apps/edge/src/gateway/usage.ts` (interface, `PgUsageStore`, `FakeUsageStore`), `apps/edge/src/gateway/llm.ts`, `apps/edge/src/config.ts`, `apps/edge/src/server.ts`, `infra/azure/main.bicep`, `main.bicepparam`, `infra/azure/modules/alerts.bicep`, `.env.example`, `docs/features/llm-gateway.md`, `infra/azure/README.md`
- **Done when:** with `EDGE_LLM_PLATFORM_DOLLARS_PER_DAY` set, an app under its own budget is refused with `503 capability_unavailable` and a `retry-after` to local midnight once the platform sum reaches the ceiling; the denial row (`errorDetail = platform_ceiling`) is throttled; a failed ceiling read with an expired cache refuses the call; a startup self-test reads the function once and fails loudly on a misconfigured owner policy; a bad config value (negative, non-numeric) fails at boot and `0` disables; the Bicep default is one tenth of `platformMonthlyUsdCap` and is always passed to a deployed edge; the `platform_ceiling` reason is recorded.
- **Evidence:** `llm.test.ts` ceiling cases; integration test that the platform read reflects a charged cut call; the optional `helix.gateway.platform_spend_ratio` gauge only if the cache is wired; `just infra build` for Bicep and the alert rule; `./check-and-lint.sh`; smoke with the ceiling set low. The Bicep parameters, edge env wiring and alert rule are **unverified in Azure**.

### SP-10 Lease store and `inflight_leases` migration (Part 3c)
- **Depends on:** none (ordered after SP-9 by the plan)
- **Files:** `apps/edge/src/gateway/leaseStore.ts` (new) and tests, a new migration (`inflight_leases` table, index, grants), `role-split.integration.test.ts`, `leaseStore.integration.test.ts`
- **Done when:** `PgLeaseStore` acquires every scope atomically under advisory locks taken in sorted order, never exceeds a cap under concurrency, ignores expired leases without a sweep, releases by lease id, and sweeps expired rows; `helix_edge` has `SELECT, INSERT, DELETE` and the portal and egress roles have none.
- **Evidence:** in-memory unit tests; integration tests against local Postgres: concurrent acquires never exceed the cap, expiry frees a slot, two stores on separate pools share the cap, role grants as stated. Nothing Azure-specific.

### SP-11 Wire concurrency caps and the call deadline into the LLM handler (Part 3c)
- **Depends on:** SP-5, SP-7, SP-10
- **Files:** `apps/edge/src/gateway/llm.ts`, `llm.test.ts`, `apps/edge/src/config.ts`, `apps/edge/src/server.ts`, `infra/azure/main.bicep`, `main.bicepparam`, `.env.example`, `docs/features/llm-gateway.md`
- **Done when:** per-app and per-user caps (`llm:app:<appId>`, `llm:user:<appId>:<userOid>`) refuse over-cap calls with `503 capability_unavailable` and reasons `concurrency_app` and `concurrency_user`; anonymous callers get the app scope only; the per-replica semaphore refuses with `concurrency_replica`; the lease is released after `recordOnce` has written the row; `EDGE_LLM_MAX_CALL_MS` aborts a slow call, which is charged by the Part 2 rule; lease TTL is the deadline plus a grace period; a lease acquire failure fails closed; setting a cap to `0` disables it.
- **Evidence:** Tests, Part 3 concurrency items, including the order assertion (row written before release) and the adversarial test where an app opens many concurrent streams and hangs up (ledger moves, lease count returns to zero, platform spend reflects the charge); telemetry dimension tests; `just infra build`; `./check-and-lint.sh`; smoke. Bicep wiring is **unverified in Azure**.

### SP-12 Optional lease caps on the fetch path (Part 3c)
- **Depends on:** SP-10, SP-11
- **Files:** `apps/edge/src/gateway/fetch.ts`, `fetch.test.ts`, `apps/edge/src/config.ts`, `.env.example`
- **Done when:** with its own config set, `fetch:app:<appId>` leases bound concurrent egress calls per app and are released in `finally`; with the config unset, behavior is unchanged.
- **Evidence:** fetch handler tests for refusal at the cap, release on hang-up, and no change when disabled; `./check-and-lint.sh`; smoke.

### SP-13 ADR-0051, remaining docs and TODO (documentation)
- **Depends on:** SP-11
- **Files:** `docs/adr/0051-llm-admission-control.md` (new), `docs/adr/0011-*.md`, `docs/adr/0028-*.md` (shared amendment, coordinate with the other two designs), `docs/features/llm-gateway.md`, `docs/features/capabilities-and-manifests.md`, `infra/azure/README.md`, `TODO.md:58`
- **Done when:** ADR-0051 records the decisions listed under ADR impact; the operator rollout notes from this document are in the release or upgrade documentation; `TODO.md:58` states the corrected scope (pre-header window; $0 ledger) and is closed.
- **Evidence:** docs checks in `./check-and-lint.sh`; a read-through that every knob in `config.ts` appears in `.env.example` and the docs.
