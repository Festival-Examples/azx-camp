# SP-8 dedicated review

_Reviewer:_ the coordinating Claude session (not the author; the author was cursor-agent `composer-2.5`). _Reviewed:_ `apps/portal/prisma/migrations/20261009223800_platform_llm_spend_definer/migration.sql`, `apps/edge/src/gateway/platformSpendDefinerCheck.ts`, the new cases in `usage.rls.integration.test.ts` and `role-split.integration.test.ts`, and the ADR-0002 amendment.

## Function

- `platform_llm_spend_micro_usd(p_env text) RETURNS TABLE (today bigint, hour bigint)`, `LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public`. It returns two sums for one env and capability `llm`, nothing row-level. **OK.**
- The table is schema-qualified (`public.gateway_calls`) and every function and operator used (`SUM`, `COALESCE`, `date_trunc`, `now`, `>=`, `-`, `=`) is built in and resolves from `pg_catalog` first. **OK.**
- The day and hour windows match the per-app query in `apps/edge/src/gateway/usage.ts:309-313` (`date_trunc('day', now())`, `now() - interval '1 hour'`), so the platform total and the per-app budgets agree on when a day starts. **OK.**
- **Low, hardening:** PostgreSQL's guidance for `SECURITY DEFINER` functions is to list `pg_temp` last in `search_path` (`pg_catalog, pg_temp`). Not exploitable here because the only relation is schema-qualified and functions and operators are never looked up in `pg_temp`, but worth adopting if the function is ever edited.

## Policy

- `gateway_calls_owner_read`: `FOR SELECT TO <current_user> USING (true)`, bound at migration time to the role that runs migrations (`helixadmin` in production, `helix` in dev; confirmed in `sp8-owner-role.md`). It lets the definer function, owned by that role, see every row under `FORCE ROW LEVEL SECURITY`. It gives the migration owner nothing it could not already do: as table owner it could `ALTER TABLE ... DISABLE ROW LEVEL SECURITY`. **OK.**
- The probe test shows the sum is zero without the policy and non-zero with it (`sp8-owner-policy-probe-without-policy.txt`), so a missing policy fails visibly in tests rather than silently disabling the ceiling.

## Grants

- `REVOKE EXECUTE ... FROM PUBLIC`, then `GRANT EXECUTE ... TO helix_edge` only. `role-split.integration.test.ts` asserts `helix_edge` may execute it and `helix_portal`, `helix_egress`, `helix_dev` get permission denied, and that `helix_edge` still has no `UPDATE` or `DELETE` on `gateway_calls`. **OK.**
- **Medium, rollout:** the grant is inside `IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'helix_edge')`. If the roles are bootstrapped after this migration on some install, the grant is silently skipped and the edge cannot call the function. SP-9 must treat "function missing or not executable" as a failure its startup self-check reports (the catalog SQL in `platformSpendDefinerCheck.ts` is meant for that), and the operator rollout notes (SP-13) must say to run the role bootstrap before this migration.

## Verdict

Approved for commit. Two follow-ups carried forward: the `pg_temp` hardening (low) and the SP-9 self-check for a missing grant (medium).
