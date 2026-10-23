alter table app_role drop constraint if exists app_role_role_check;
alter table app_role add constraint app_role_role_check
  check (role in ('guardian', 'team_parent', 'coach', 'commissioner', 'platform_owner'));
