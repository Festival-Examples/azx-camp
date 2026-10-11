# EG-7 result: firewall allow-list tier and drift tooling

**Result: done.** With the firewall on, `egressFqdnMode` chooses the egress subnet's internet rule: `any` (today's behavior, the Bicep default so an existing firewall install does not fail closed on a template update) or `allowlist` (only the product FQDNs: LLM vendor hosts derived from the `llm*` parameters plus `egressAllowedFqdns` for connection-provider hosts and approved fetch origins; a compile-time guard refuses an empty list). The reference parameter files set `allowlist`, as the design recommends for new installs. New `infra/azure/modules/firewall-diagnostics.bicep` sends firewall logs to the apps Log Analytics workspace and adds a scheduled-query alert on application-rule denials from the egress subnet (`docs/features/observability.md` updated).

Drift tooling (N3: static list plus drift check, no generator): `just infra egress-hosts` (`apps/portal/scripts/egress-hosts.ts`, pure helpers in `apps/portal/src/netControls/egressHosts.ts`) lists the hosts that approved apps' fetch origins and connection providers' token and API hosts need, and with `--deployed` or `--deployed-file` marks any that are missing from the deployed list; `--check` exits non-zero on drift. It prints hosts, their sources (app slug or provider), and status; no credentials.

## Evidence

- `egressHosts.test.ts` (host parsing, shared-host merge, provider hosts, unparseable capabilities, wildcard matching, diff), `egressHosts.integration.test.ts` (an active app's origin and production provider hosts included, an archived app excluded).
- `just infra build` passed. Gate: 240 of 240 test files (`eg7-gate.txt`). Smoke: 31 passed, 0 failed, 1 skipped (`eg7-smoke.txt`). `just infra egress-hosts` runs against the dev database (no approved origins there, so the table is empty).

## Unverified in Azure

`allowlist` behavior on a real firewall, SNI-only application-rule matching, rule-collection limits, the diagnostic table and column names (`AZFWApplicationRule`, `Action`, `SourceIp`, `Fqdn`), whether the denial alert fires, and the `az containerapp exec` path for running the drift check in a portal replica.

## Executor

cursor-agent, `composer-2.5`, 79 tool calls.
