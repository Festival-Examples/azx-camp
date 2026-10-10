---
fest_type: task
fest_id: 03_eg3_special_purpose_registry_completeness_test.md
fest_name: eg3 special purpose registry completeness test
fest_parent: 02_network_egress
fest_order: 3
fest_status: completed
fest_autonomy: medium
fest_created: 2026-10-08T20:22:04.024212-06:00
fest_updated: 2026-10-10T02:06:22.291487-06:00
fest_tracking: true
---



# Task: eg3 special purpose registry completeness test

## Objective

Add a test that compares the egress block list against a snapshot of the IANA IPv4 and IPv6 special-purpose address registries, so a range that should be blocked cannot be missing without someone naming it in an explicit exceptions list. Implements EG-3 from 03-egress-network-control.md.

## Requirements

- [ ] Depends on `01_eg1_block_list_additions_and_boundary_tests.md` (the ranges this test expects to find) and `02_eg2_deployment_supplied_extra_block_list.md` (the `isBlockedAddress(ip, extraBlocked)` signature the test calls with an empty list).
- [ ] The snapshot comes from the registries themselves, downloaded in this task, not typed from memory. It is embedded in the test file together with its retrieval date and the two source URLs.
- [ ] Required set: every registry entry whose Forwardable column or Globally Reachable column starts with `False`. For each required entry, the first, the middle and the last address of the block are blocked by `isBlockedAddress(addr, [])`, or the entry's block is named in an explicit exceptions list with a one-line reason.
- [ ] The exceptions list is explicit data in the test file: `{ cidr, reason }` pairs. An exception whose block is in fact blocked is a failure (a stale exception hides a regression the day someone removes the range).
- [ ] Entries the registry marks globally reachable and forwardable (the AS112, AMT, Port Control Protocol and similar anycast services) are not required. List them in an informational constant with their name so a reader can see they were seen and skipped on purpose. Decide per entry from the registry columns, not from memory, and write the decision into `results/`.
- [ ] Failure path. The test fails when a required range is removed from `V4_BLOCKED` or `V6_BLOCKED`. Check this once by deleting one entry locally, then restore it.
- [ ] Failure path. A row the parser cannot read (an unexpected column layout after a registry update) fails the test with the row text, never skips it silently.
- [ ] The snapshot is data about a public registry. It contains no secrets and no install-specific values.

## Implementation

1. Create the branch in `projects/helix`: `git checkout main && git checkout -b eg-3-special-purpose-registry-test` (after `eg-2-extra-block-list` is merged).

2. Download the registries into a scratch directory outside the repository, treating the files as untrusted data (read them, do not execute anything from them):
   - IPv4: `https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.csv`
   - IPv6: `https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.csv`

   Note the date you downloaded them. Read the header row of each file before writing the parser: this plan expects columns named `Address Block`, `Name`, `RFC`, `Allocation Date`, `Termination Date`, `Source`, `Destination`, `Forwardable`, `Globally Reachable` and `Reserved-by-Protocol`, but confirm it. Save both CSVs under the sequence's `results/` directory too, so the evidence for the snapshot survives. If the download fails, stop and ask: the task is not allowed to proceed from memory.

3. Create `apps/egress/src/ssrfRegistry.test.ts` (a new file keeps `ssrf.test.ts`, which mocks `node:dns/promises`, from growing a large data block; the vitest include pattern in `vitest.config.ts` is `{apps,packages}/*/src/**/*.test.ts`, so the file is picked up). Structure:

```ts
// Retrieved 2026-10-08 (use the real date) from
//   https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.csv
//   https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.csv
interface RegistryRow {
  block: string; // one CIDR; split rows with several blocks into one entry each
  name: string;
  forwardable: string; // the registry cell, verbatim: "True", "False", "N/A", ...
  globallyReachable: string;
}
const IPV4_REGISTRY: RegistryRow[] = [ /* one row per block, copied from the CSV */ ];
const IPV6_REGISTRY: RegistryRow[] = [ /* ... */ ];

const EXCEPTIONS: { cidr: string; reason: string }[] = [ /* only if needed */ ];
```

   Copy the rows with a small throwaway script that reads the CSV and prints the TypeScript literal, so no row is retyped. Split a cell that lists several blocks (the IPv4 registry has rows such as two `/32` blocks in one cell) into one entry per block, and strip footnote markers like `[1]` from the block and name cells. Keep the Forwardable and Globally Reachable cells verbatim.

4. Test helpers inside the file: parse a CIDR into its first address, a middle address and its last address, for both families, using `BigInt` and printing IPv4 as a dotted quad and IPv6 as eight uncompressed hex groups (`isIP` and `ipv6ToBigInt` accept the uncompressed form). Write them in the test file; do not export test-only helpers from `ssrf.ts`.

5. Tests:
   - `it.each` over the required rows of each registry (`/^False/i.test(forwardable) || /^False/i.test(globallyReachable)`). For each: if the row's block is in `EXCEPTIONS`, skip it here; otherwise assert `isBlockedAddress(first, [])`, `isBlockedAddress(middle, [])` and `isBlockedAddress(last, [])` are all `true`. The failure message names the registry row's name and block so the fix is obvious.
   - `it.each(EXCEPTIONS)`: assert at least one of first, middle, last is **not** blocked (the exception is still needed). A fully blocked exception fails with "remove this stale exception".
   - A guard that the snapshot parsed to something sensible: each registry has at least 10 rows, every row has a parseable CIDR, and every `forwardable`/`globallyReachable` cell is non-empty. This catches a broken regeneration, not the block list.
   - Informational skipped set: assert that every row that is neither required nor an exception appears in `GLOBAL_SERVICES` (a list of `{ cidr, name }` for the anycast and similar services) so a new registry row cannot slip past as "not required" without a human reading it. When you generate `GLOBAL_SERVICES`, base it on the rows that are forwardable and globally reachable in the downloaded files.

6. Run the test. Expect failures on the first run if the registry lists a required block the current list misses. For each failure, decide with the registry's own Name and RFC columns:
   - A range an SSRF filter should never let a request reach: add it to `V4_BLOCKED` or `V6_BLOCKED` in `apps/egress/src/ssrf.ts`, in sorted position with a comment naming the registry entry, and note it in `results/`. Add a boundary row for it to the tables from `01_eg1_block_list_additions_and_boundary_tests.md` if it is a plain range.
   - A range that must stay reachable or that is covered by extraction (for example `64:ff9b::/96`, whose embedded IPv4 is checked): add it to `EXCEPTIONS` with a reason that says why.

   Do not guess. If a registry row's meaning is unclear, put it in `results/` as a question and leave the test failing rather than excepting it.

7. Mutation check: delete `["198.18.0.0", 15]` from `V4_BLOCKED` locally, run `pnpm vitest run apps/egress/src/ssrfRegistry.test.ts`, confirm the benchmarking row fails, restore the line. Record the output in `results/`.

8. Docs. No ADR text here: `11_eg11_docs_and_adr_amendments.md` writes the ADR-0005 amendment and lists the new ranges. Add a sentence to the docblock at the top of `apps/egress/src/ssrf.ts` (lines 5-16) pointing at `ssrfRegistry.test.ts` as the check that keeps the list current. No telemetry: the task adds no runtime behavior unless step 6 adds ranges, which flow through the existing 403 `blocked`.

9. Comments in the repo may cite ADR numbers and file names, never this plan's change IDs (EG-n) or `workflow/` paths.

## Done When

- [ ] All requirements met.
- [ ] `ssrfRegistry.test.ts` passes, fails when a required range is removed (mutation check recorded in `results/`), and the snapshot header carries the real retrieval date and both URLs.
- [ ] Every range added to the block list or to `EXCEPTIONS` in step 6 is listed in `results/` with the registry entry that justified it.
- [ ] `./check-and-lint.sh` passes in the dev container. Output saved under `results/`.
- [ ] `just dev smoke` passes (egress still boots). Output saved under `results/`.
- [ ] Committed with `fest commit -m "EG-3: test the egress block list against the IANA special-purpose registries"`.
- [ ] Unverified in Azure: nothing. The registries are public data and the test runs in the dev container. What it cannot know is whether Azure routes any registry range inside a customer VNet; that is the NSG work in `05_eg5_nsg_module_and_subnet_attachment.md`.