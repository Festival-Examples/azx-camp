# SP-8 migration owner role (confirmed)

| Environment              | Role that runs `db:deploy` | Evidence                                                                                                                                                                                                                                                                  |
| ------------------------ | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production (Azure)       | `helixadmin`               | `infra/azure/sql/01-roles.sql` lines 68–70: `FOR ROLE helixadmin` must name the object owner; `infra/azure/main.bicep` line 87: `postgresAdminLogin` defaults to `helixadmin`; `apps/portal/scripts/migrate-deploy.ts` documents migrations as schema owner `helixadmin`. |
| Dev container / CI tests | `helix`                    | `.devcontainer/db-init/01-roles.sql` line 4: `POSTGRES_USER` / object owner; Prisma migrations run as `helix`.                                                                                                                                                            |

The owner `SELECT` policy on `gateway_calls` is bound with `format('%I', current_user)` at migration apply time, so it matches whichever role runs the migration on that cluster.

**Unverified in Azure:** `helixadmin` on Azure Database for PostgreSQL is a member of `azure_pg_admin`, not a superuser. This task assumes that role is still subject to `FORCE` RLS like the dev non-superuser owner and that `CREATE POLICY ... TO helixadmin` and `SECURITY DEFINER` ownership behave the same as in the dev container.

**Operator rollout:** Apply this migration before deploying an edge image that calls `platform_llm_spend_micro_usd`. Confirm the migration identity's login matches the policy role name on the target cluster.
