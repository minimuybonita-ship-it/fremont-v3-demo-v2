-- 023_revoke_anon_execute_security_definer_helpers.sql  (AS APPLIED — INCOMPLETE; see 027)
-- Intended to stop anon/authenticated calling internal SECURITY DEFINER helpers via RPC.
-- DEFECT: it revokes from the roles anon and authenticated by name, but the functions' default
-- EXECUTE privilege is held by PUBLIC (ACL "=X/postgres"), and anon/authenticated inherit PUBLIC.
-- Revoking from a role does not remove a PUBLIC grant, so anon kept EXECUTE. Fixed in 027.

revoke execute on function auth_family_ids() from anon, authenticated;
revoke execute on function auth_team_ids() from anon, authenticated;
revoke execute on function auth_is_commissioner() from anon, authenticated;
revoke execute on function auth_is_platform_owner() from anon, authenticated;
revoke execute on function auth_team_scoped_player_ids() from anon, authenticated;
revoke execute on function auth_team_scoped_family_ids() from anon, authenticated;
revoke execute on function enforce_player_match_status_commissioner_only() from anon, authenticated;
