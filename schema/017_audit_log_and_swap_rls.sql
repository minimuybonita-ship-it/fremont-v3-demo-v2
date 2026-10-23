alter table assignment_audit_log enable row level security;
alter table swap_request enable row level security;

create policy assignment_audit_log_scoped_read on assignment_audit_log
  for select using (
    assignment_id in (
      select a.id from assignment a where a.family_id in (select auth_family_ids())
    )
    or assignment_id in (
      select a.id from assignment a
      join job_instance ji on ji.id = a.job_instance_id
      join game_event ge on ge.id = ji.game_event_id
      where ge.team_id in (select auth_team_ids())
    )
    or auth_is_commissioner()
  );
create policy assignment_audit_log_insert on assignment_audit_log for insert with check (true);

create policy swap_request_scoped_read on swap_request
  for select using (
    requested_by_family_id in (select auth_family_ids())
    or offered_to_family_id in (select auth_family_ids())
    or assignment_id in (
      select a.id from assignment a
      join job_instance ji on ji.id = a.job_instance_id
      join game_event ge on ge.id = ji.game_event_id
      where ge.team_id in (select auth_team_ids())
    )
    or auth_is_commissioner()
  );
create policy swap_request_family_insert on swap_request
  for insert with check (requested_by_family_id in (select auth_family_ids()));
create policy swap_request_resolve on swap_request
  for update using (
    offered_to_family_id in (select auth_family_ids())
    or requested_by_family_id in (select auth_family_ids())
    or auth_is_commissioner()
  );
