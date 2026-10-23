alter table player_season add column if not exists registration_stage text not null default 'draft'
  check (registration_stage in (
    'draft', 'submitted', 'review', 'correction_needed',
    'approved', 'waitlisted', 'withdrawn', 'refunded', 'season_ready'
  ));

alter table player_season add column if not exists correction_note text;
alter table player_season add column if not exists correction_due_at timestamptz;
alter table player_season add column if not exists reviewed_by uuid references auth.users(id);
alter table player_season add column if not exists reviewed_at timestamptz;
alter table player_season add column if not exists submitted_at timestamptz;

comment on column player_season.registration_stage is
  'Manual §10 stage model.';

create or replace function player_season_readiness(p_player_season_id uuid)
returns table (
  has_team boolean,
  has_uniform_order boolean,
  has_emergency_contact boolean,
  acknowledgments_complete boolean,
  is_season_ready boolean
)
language sql stable
as $$
  select
    (ps.team_id is not null) as has_team,
    exists (select 1 from uniform_order uo where uo.player_season_id = ps.id) as has_uniform_order,
    (p.emergency_contact_name is not null and p.emergency_contact_phone is not null) as has_emergency_contact,
    not exists (
      select 1 from acknowledgment a where a.player_season_id = ps.id and a.completed_at is null
    ) as acknowledgments_complete,
    (
      ps.team_id is not null
      and exists (select 1 from uniform_order uo where uo.player_season_id = ps.id)
      and p.emergency_contact_name is not null and p.emergency_contact_phone is not null
      and not exists (select 1 from acknowledgment a where a.player_season_id = ps.id and a.completed_at is null)
      and ps.registration_stage in ('approved', 'season_ready')
    ) as is_season_ready
  from player_season ps
  join player p on p.id = ps.player_id
  where ps.id = p_player_season_id;
$$;

comment on function player_season_readiness is
  'Backs the guided Registration flow''s Review step and the Season Ready gate.';
