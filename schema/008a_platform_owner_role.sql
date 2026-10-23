create or replace function auth_is_platform_owner()
returns boolean
language sql stable
as $$
  select exists (
    select 1 from app_role where auth_user_id = auth.uid() and role = 'platform_owner'
  )
$$;

comment on function auth_is_platform_owner is
  'Manual p.6: operational/config role, not a league-data role by default.';
