# Baseline gate on main (792557a), before any task

Run 2026-10-09 inside the dev container (`docker compose -f .devcontainer/docker-compose.yml -p helix exec -T app bash -lc 'cd /workspace && ./check-and-lint.sh'`).

```
▶ typecheck
✔ typecheck passed (21s)
▶ lint
✔ lint passed (10s)
▶ refs
✔ refs passed (0s)
▶ format
✔ format passed (9s)
▶ docs
✔ docs passed (8s)
▶ tests
 Test Files  1 failed | 230 passed (231)
✗ tests FAILED (138s)
timing: typecheck=21s lint=10s refs=0s format=9s docs=8s tests=138s total=186s
✗ 1 step(s) failed: tests
```

The single failure is the known flaky test `apps/edge/src/routing/connectionsJourney.integration.test.ts` > "two approved apps share one connection" (`AssertionError: expected 403 to be 200`), the same failure seen upstream on a docs-only commit (explore notes, HEALTH-1). Rerun alone three times: failed once, passed twice (11/11).

**Gate rule for this festival:** a task passes when `./check-and-lint.sh` passes, or when its only failure is that one test and a solo rerun of that file passes. Any other failure blocks the task.
