-- 020_fix_rls_recursion_auth_helpers.sql
-- BLOCKER found during staging QA: auth_is_commissioner() reads app_role, and app_role's own RLS
-- policy calls auth_is_commissioner() -> direct self-recursion. The role-resolution helpers are a
-- trust boundary by design; make them SECURITY DEFINER. No visibility change.

create or replace function auth_family_ids()
returns setof uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select family_id from app_role
  where auth_user_id = auth.uid() and role = 'guardian' and family_id is not null
$$;

create or replace function auth_team_ids()
returns setof uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select team_id from app_role
  where auth_user_id = auth.uid() and role in ('team_parent', 'coach') and team_id is not null
$$;

create or replace function auth_is_commissioner()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from app_role where auth_user_id = auth.uid() and role = 'commissioner'
  )
$$;

create or replace function auth_is_platform_owner()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from app_role where auth_user_id = auth.uid() and role = 'platform_owner'
  )
$$;

comment on function auth_is_commissioner is
  'Role check is server-side via RLS, never trusted from a client-sent flag. SECURITY DEFINER is required here (schema/020): app_role''s own RLS policy calls this function, so it must bypass RLS internally or it recurses into itself.';
-- NOTE: long explanatory header abbreviated; SQL statements identical to the applied migration.
