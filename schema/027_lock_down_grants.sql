-- ============================================================
-- 027_lock_down_grants.sql
--
-- SECURITY. Root-cause fix for the advisor finding that 7 SECURITY DEFINER
-- helpers were executable by anon (migration 023 did not work), plus the
-- table-privilege hardening needed for the "no broad client writes" rule.
--
-- ROOT CAUSE of the 023 failure
--   Postgres grants EXECUTE on every new function to PUBLIC by default
--   (ACL entry "=X/postgres"). anon and authenticated inherit PUBLIC.
--   023 ran "REVOKE ... FROM anon, authenticated", which removes only
--   grants made directly to those roles. The PUBLIC grant was untouched,
--   so anon kept EXECUTE. Verified on staging via pg_proc.proacl:
--   {=X/postgres,postgres=X/postgres,service_role=X/postgres}.
--
-- DEPENDENCIES (why authenticated keeps EXECUTE on 6 of the 7)
--   auth_family_ids / auth_team_ids / auth_is_commissioner /
--   auth_is_platform_owner / auth_team_scoped_player_ids /
--   auth_team_scoped_family_ids are called INSIDE RLS policy expressions.
--   Postgres checks EXECUTE as the querying role, so authenticated must
--   keep it or every RLS-protected read fails for signed-in users.
--   They are documented as "internal helper, signed-in only": each keys
--   off auth.uid() and only ever reveals the caller's own scope.
--   enforce_player_match_status_commissioner_only is a trigger function;
--   triggers do not need EXECUTE for the firing role, so NO client role
--   keeps it.
--   anon needs none of them: the app requires sign-in before any data call.
-- ============================================================

-- 1. The seven helpers -------------------------------------------------
revoke execute on function auth_family_ids()                  from public, anon;
revoke execute on function auth_team_ids()                    from public, anon;
revoke execute on function auth_is_commissioner()             from public, anon;
revoke execute on function auth_is_platform_owner()           from public, anon;
revoke execute on function auth_team_scoped_player_ids()      from public, anon;
revoke execute on function auth_team_scoped_family_ids()      from public, anon;
grant  execute on function auth_family_ids()                  to authenticated;
grant  execute on function auth_team_ids()                    to authenticated;
grant  execute on function auth_is_commissioner()             to authenticated;
grant  execute on function auth_is_platform_owner()           to authenticated;
grant  execute on function auth_team_scoped_player_ids()      to authenticated;
grant  execute on function auth_team_scoped_family_ids()      to authenticated;
revoke execute on function enforce_player_match_status_commissioner_only() from public, anon, authenticated;

-- 2. Every other public function was also PUBLIC-executable ------------
-- (SECURITY INVOKER read helpers; RLS still applies, but anon has no business calling them.)
revoke execute on function families_owing_hours(uuid)                 from public, anon;
revoke execute on function family_fundraising_summary(uuid, uuid)     from public, anon;
revoke execute on function job_instance_coverage(uuid)                from public, anon;
revoke execute on function player_season_readiness(uuid)              from public, anon;
revoke execute on function season_closeout_summary(uuid)              from public, anon;
revoke execute on function can_close_season(uuid)                     from public, anon;
revoke execute on function scan_for_possible_duplicate_players(uuid)  from public, anon;
grant  execute on function families_owing_hours(uuid)                 to authenticated;
grant  execute on function family_fundraising_summary(uuid, uuid)     to authenticated;
grant  execute on function job_instance_coverage(uuid)                to authenticated;
grant  execute on function player_season_readiness(uuid)              to authenticated;
grant  execute on function season_closeout_summary(uuid)              to authenticated;
grant  execute on function can_close_season(uuid)                     to authenticated;
grant  execute on function scan_for_possible_duplicate_players(uuid)  to authenticated;

-- 3. Functions created in future must not be PUBLIC/anon-executable by default
alter default privileges in schema public revoke execute on functions from public, anon;

-- 4. Table privileges --------------------------------------------------
-- Supabase grants ALL on every public table to anon and authenticated and relies on RLS alone.
-- TRUNCATE is not subject to RLS at all. Remove everything the app never needs.
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke delete on all tables in schema public from authenticated;
grant  delete on app_role to authenticated;          -- policy app_role_commissioner_delete (role admin is manual in V1, kept for the policy)
alter default privileges in schema public revoke all on tables from anon;

-- 5. Consequential tables: NO direct client writes (business-action functions only, see 029+)
revoke insert, update on assignment                 from authenticated;
revoke insert, update on assignment_audit_log       from authenticated;
revoke insert, update on replacement_pool_entry     from authenticated;
revoke insert, update on fundraising_cash_ledger    from authenticated;
revoke insert, update on fundraising_credit_ledger  from authenticated;
revoke insert, update on no_show_record             from authenticated;
revoke update          on social_share_submission   from authenticated;   -- family INSERT stays (guarded by trigger in 028)
revoke insert          on family                    from authenticated;
revoke insert, update on guardian                   from authenticated;
revoke update (status) on season                    from authenticated;
revoke update          on season                    from authenticated;
grant  update (name, starts_on, ends_on) on season  to authenticated;      -- status changes only via set_season_status()
