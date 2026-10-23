alter table app_role enable row level security;

create policy app_role_self_read on app_role
  for select using (auth_user_id = auth.uid());

create policy app_role_commissioner_read on app_role
  for select using (auth_is_commissioner());
create policy app_role_commissioner_insert on app_role
  for insert with check (auth_is_commissioner());
create policy app_role_commissioner_delete on app_role
  for delete using (auth_is_commissioner());

comment on policy app_role_commissioner_insert on app_role is
  'Bootstrap note: the very first commissioner role row cannot be created through this policy. That first row must be inserted once via direct database access as part of initial deployment setup.';
