# EG-4 result: fixed private-endpoint addresses (opt-in)

**Result: done, with a change from the design.** The four private endpoints (three Key Vaults and Blob) can have fixed addresses in `snet-pe`. `infra/azure/modules/private-endpoint.bicep` takes an optional `privateIpAddress` and `memberName`; `network.bicep` exposes the subnet prefixes as parameters and outputs; `keyvault.bicep` and `storage.bicep` pass the addresses through; `main.bicep` derives defaults (.4 to .7 of `snet-pe` via `cidrHost`), accepts overrides in `privateEndpointAddresses`, rejects bad or duplicate addresses with `fail()` at deploy time, and outputs whether pinning is on and the addresses.

## Change from the design, made in review

The agent's first version pinned addresses on every apply. On an existing install that changes the IP configuration of live private endpoints, which Azure may not allow after creation (unverified); if so, every existing install's next deployment would fail. Pinning is now opt-in: `pinPrivateEndpointAddresses` (default false). With it off, the module omits `ipConfigurations` entirely (Bicep object spread; the coordinator changed the agent's `ipConfigurations: null` to a spread so the property is absent rather than null), matching endpoints created before this change. New installs should turn it on; existing installs only after listing current endpoint addresses and accepting a possible endpoint recreation. EG-5's NSG names the pinned addresses when on and falls back to the whole `snet-pe` prefix when off. Recorded in `decisions.md`.

The agent's follow-up run also edited spend-control files (`apps/edge/src/gateway/llm.ts`, its tests, `fetch.test.ts`, `TODO.md`) because the coordinator reused the wrong shared prompt; those edits were discarded unreviewed.

## Evidence

- `just infra build` passed. The compiled module merges an empty object when no address is pinned, so `ipConfigurations` is absent.
- Gate: all test files passed (`eg4-gate.txt`).

## Unverified in Azure

Whether API version 2024-05-01 accepts `ipConfigurations` for these endpoint types; the `memberName` values (`default` for Key Vault, `blob` for Blob); and whether turning pinning on for an existing endpoint updates it in place or requires recreating it.

## Executor

cursor-agent, `composer-2.5`: 89 tool calls, plus 101 for the follow-up (out-of-scope edits discarded); coordinator edit to `private-endpoint.bicep`.
