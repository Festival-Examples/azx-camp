---
fest_type: task
fest_id: 01_sp1_hangup_characterization_test.md
fest_name: sp1 hangup characterization test
fest_parent: 01_spend_controls
fest_order: 1
fest_status: pending
fest_autonomy: medium
fest_created: 2026-10-08T19:47:17.332954-06:00
fest_tracking: true
---

# Task: sp1 hangup characterization test

## Objective

Add a real-socket test to the egress suite that records whether a client hang-up after the upstream's first response byte already tears down the vendor connection. Implements SP-1 from 01-spend-controls.md.

## Requirements

- [ ] A new `describe` in `apps/egress/src/proxy.test.ts` drives egress over a real listening socket. `app.inject()` cannot express a hang-up.
- [ ] The test starts a slow-streaming upstream, calls `POST /proxy` through a real socket, reads the first chunk, then hangs up. It asserts that the upstream's response is closed without ever being ended, and that egress opened no second connection to the upstream.
- [ ] A control test proves the harness can fail: with no hang-up, a finite upstream finishes normally and the "closed early" flag stays false. Without it the main test could pass because the flag is wrong.
- [ ] The tests pass on unmodified `main` (792557a). No file outside the test file changes.
- [ ] The measured result is written in the test's comment and in `results/sp1-hangup-characterization.md` (create the `results/` directory in the sequence directory if it does not exist).
- [ ] Failure path. If the characterization test fails, the design's claim that a post-header hang-up is already propagated is wrong. Stop. Record the failing output and what you observed in `results/sp1-hangup-characterization.md`, leave the test out of the commit, and ask the owner before SP-2 (FESTIVAL_RULES: when the design and the code disagree in a way that changes behavior, stop and ask). The design text that would need correcting is the "What actually happens after a hang-up" section of `workflow/design/helix-spend-containment-egress/01-spend-controls.md`.
- [ ] Dependencies on earlier tasks: none.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b sp-1-hangup-characterization`.

2. Read the code the test characterizes, so you can say why it should pass:
   - `apps/egress/src/proxy.ts:606-611`: `request(target.href, { method, headers, body: requestBody, dispatcher })` has no `signal`.
   - `apps/egress/src/proxy.ts:686-692`: the upstream body goes through `capBody(upstream.body, ...)` and is sent with `reply.send(cappedBody)`.
   - `packages/shared/src/bodyCap.ts:55-86`: `capBody` joins the upstream stream and the cap transform with `pipeline(source, cap, () => {})`, so destroying the cap destroys the source.
   - Fastify's `sendStream` (`node_modules/.pnpm/fastify@5.12.5/node_modules/fastify/lib/reply.js:861-877`) calls `payload.destroy()` when the response closes while the source is still open. undici's response body (`node_modules/.pnpm/undici@7.30.0/node_modules/undici/lib/api/readable.js:85-92`) aborts the request in `_destroy` when it is destroyed before `end`.

   The expected result is that the vendor connection closes shortly after the hang-up.

3. Edit `apps/egress/src/proxy.test.ts`. The file already imports `createServer`, `Server`, `AddressInfo`, `afterAll`, `afterEach`, `beforeAll`, `describe`, `expect`, `it` (lines 1-5), and defines `makeApp(allowPrivate)` (line 97) and `mint({ origin, connection?, appId? })` (line 112). Add `vi` to the vitest import, and add `import { request as undiciRequest } from "undici";`.

4. Append this `describe` after the connection-pooling block (it is the last block in the file, which ends at line 461). Follow the real-socket pattern in `apps/egress/src/adversarial.test.ts:464-515` (a listening upstream, `app.listen({ port: 0, host: "127.0.0.1" })`, then undici against the bound port).

```ts
describe("egress /proxy — client hang-up after the first byte (characterization)", () => {
  // Result on main (792557a): <write the observed result here after running: "passes: the vendor response closed
  // N ms after the hang-up" or "FAILS: ...">. The claim under test is that a hang-up after
  // the upstream headers arrive already tears down the vendor connection, through Fastify's
  // sendStream -> capBody pipeline -> undici body destroy. It says nothing about a hang-up
  // BEFORE the headers arrive; that window is closed by the next change.
  let slow: Server;
  let slowOrigin: string;
  let connections = 0;
  let closedEarly = false;

  beforeAll(async () => {
    slow = createServer((req, res) => {
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.write("data: first\n\n");
      let sent = 1;
      const timer = setInterval(() => {
        res.write("data: more\n\n");
        // /finite ends by itself after a few chunks; /stream would run for 10 s.
        if (req.url === "/finite" && ++sent >= 4) {
          clearInterval(timer);
          res.end();
        }
      }, 25);
      const stop = setTimeout(() => {
        clearInterval(timer);
        res.end();
      }, 10_000);
      // 'close' fires when the socket goes away. writableFinished is still false when
      // the connection was torn down before end() ran.
      res.on("close", () => {
        clearInterval(timer);
        clearTimeout(stop);
        if (!res.writableFinished) closedEarly = true;
      });
    });
    slow.on("connection", () => void connections++);
    await new Promise<void>((resolve) => slow.listen(0, "127.0.0.1", resolve));
    slowOrigin = `http://127.0.0.1:${(slow.address() as AddressInfo).port}`;
  });
  afterAll(async () => {
    slow.closeAllConnections();
    await new Promise<void>((resolve) => slow.close(() => resolve()));
  });

  async function callThroughSocket(path: string) {
    const app = makeApp(true);
    await app.listen({ port: 0, host: "127.0.0.1" });
    const base = `http://127.0.0.1:${(app.server.address() as AddressInfo).port}`;
    connections = 0;
    closedEarly = false;
    const res = await undiciRequest(`${base}/proxy`, {
      method: "POST",
      headers: {
        [INSTRUCTION_HEADER]: await mint({ origin: slowOrigin }),
        [TARGET_HEADER]: `${slowOrigin}${path}`,
        [METHOD_HEADER]: "GET",
      },
    });
    return { app, res };
  }

  it("closes the vendor connection when the client hangs up after the first chunk", async () => {
    const { app, res } = await callThroughSocket("/stream");
    expect(res.statusCode).toBe(200);
    for await (const _chunk of res.body) break; // the first chunk has arrived
    res.body.destroy(); // the hang-up
    const hungUpAt = Date.now();
    await vi.waitFor(() => expect(closedEarly).toBe(true), { timeout: 2_000, interval: 10 });
    // Record this number in the comment above.
    console.info(`vendor closed ${Date.now() - hungUpAt} ms after the hang-up`);
    // Egress did not dial a second connection to recover or retry.
    await new Promise((r) => setTimeout(r, 150));
    expect(connections).toBe(1);
    app.server.closeAllConnections();
    await app.close();
  });

  it("control: a client that stays connected sees the upstream finish normally", async () => {
    const { app, res } = await callThroughSocket("/finite");
    await res.body.text(); // read to the end
    await new Promise((r) => setTimeout(r, 100));
    expect(closedEarly).toBe(false);
    app.server.closeAllConnections();
    await app.close();
  });
});
```

   `makeApp(true)` sets `allowPrivate` so the loopback upstream is reachable, as the other tests in this file do. Because the instruction is minted with no `connection`, no secret is resolved.

5. Run the new tests alone while iterating: `pnpm vitest run apps/egress/src/proxy.test.ts -t "hang-up"` in the dev container. Run them 10 times (`for i in $(seq 10); do ...; done`) and confirm they never flake. If the timing assertion flakes, widen the `vi.waitFor` timeout, never remove the assertion.

6. Complete the `Result on main` comment with the observed millisecond figure. Write `results/sp1-hangup-characterization.md` in the sequence directory: the command, the pass/fail result, the millisecond figure, and one sentence saying whether the design's "post-header already propagated" claim held.

7. No telemetry or docs change: this task adds no production code. The result feeds SP-13, which corrects `TODO.md:58` to the narrower scope.

## Done When

- [ ] All requirements met.
- [ ] Both new tests pass on unmodified `main`, repeated 10 times without a flake.
- [ ] `./check-and-lint.sh` passes in the dev container (Postgres and Azurite running). Output saved under `results/`.
- [ ] `just dev smoke` is not required: the change is test-only and touches no running service.
- [ ] The result (pass, with the measured delay) is recorded in the test comment and in `results/sp1-hangup-characterization.md`. If the test failed, the task stops there and the owner has been told.
- [ ] Committed with `fest commit -m "SP-1: characterize egress behavior on a hang-up after the first byte"`.
- [ ] Unverified in Azure: the test proves behavior over loopback on Node 24 and undici 7.30. It does not prove it through the Container Apps ingress that sits between edge and egress in a deployment.
