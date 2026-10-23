alter table game_event add column if not exists closed_at timestamptz;
alter table game_event add column if not exists closed_by uuid references auth.users(id);

comment on column game_event.closed_at is
  'Set by the Game Complete action once every job_instance at this event has a resolved assignment status. Null = event still open operationally.';

create table if not exists game_event_incident (
  id uuid primary key default gen_random_uuid(),
  game_event_id uuid not null references game_event(id) on delete cascade,
  reported_by uuid references auth.users(id),
  reported_at timestamptz not null default now(),
  description text not null,
  resolved boolean not null default false
);

alter table game_event_incident enable row level security;
create policy game_event_incident_staff_access on game_event_incident
  for all using (
    auth_is_commissioner()
    or game_event_id in (
      select id from game_event where team_id in (select auth_team_ids())
    )
  );

create or replace function job_instance_coverage(p_game_event_id uuid)
returns table (
  job_instance_id uuid,
  role_name text,
  volunteers_needed integer,
  assignment_count bigint,
  unresolved_count bigint
)
language sql stable
as $$
  select
    ji.id as job_instance_id,
    jrc.role_name,
    ji.volunteers_needed,
    count(a.id) as assignment_count,
    count(a.id) filter (
      where a.status in ('open', 'claimed', 'confirmed', 'scheduled')
    ) as unresolved_count
  from job_instance ji
  join job_role_config jrc on jrc.id = ji.job_role_config_id
  left join assignment a on a.job_instance_id = ji.id
  where ji.game_event_id = p_game_event_id
  group by ji.id, jrc.role_name, ji.volunteers_needed;
$$;
