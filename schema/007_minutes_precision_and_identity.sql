-- ---------- 1. Minutes, not hours ----------

alter table job_role_config add column if not exists credited_minutes integer;
update job_role_config set credited_minutes = round(credited_hours * 60) where credited_minutes is null;
alter table job_role_config alter column credited_minutes set not null;
alter table job_role_config alter column credited_minutes set default 120;
comment on column job_role_config.credited_hours is 'DEPRECATED display convenience only (credited_minutes / 60). credited_minutes is the source of truth.';

alter table job_instance add column if not exists credited_minutes_override integer;

alter table assignment add column if not exists actual_minutes_worked integer;
alter table season_config alter column hours_per_child type numeric using hours_per_child;
alter table season_config add column if not exists minutes_per_child integer;
update season_config set minutes_per_child = round(hours_per_child * 60) where minutes_per_child is null;
alter table season_config alter column minutes_per_child set not null;
comment on column season_config.hours_per_child is 'Human-facing policy value (e.g. "3"). minutes_per_child (180) is what calculations actually use.';

create or replace function families_owing_hours(p_season_id uuid)
returns table (
  family_id uuid,
  registered_children integer,
  required_minutes integer,
  scheduled_minutes integer,
  completed_minutes integer,
  verified_minutes integer,
  remaining_minutes integer
)
language sql stable
as $$
  with household_children as (
    select f.id as family_id, count(ps.id) as registered_children,
           max(sc.minutes_per_child) as minutes_per_child
    from family f
    join player p on p.family_id = f.id
    join player_season ps on ps.player_id = p.id and ps.season_id = p_season_id
    join season_config sc on sc.id = ps.season_config_id
    group by f.id
  ),
  assignment_minutes as (
    select
      a.family_id,
      sum(case when a.status in ('claimed', 'confirmed', 'scheduled') then
            coalesce(ji.credited_minutes_override, jrc.credited_minutes)
          else 0 end) as scheduled_minutes,
      sum(case when a.status = 'completed' then
            coalesce(a.actual_minutes_worked, ji.credited_minutes_override, jrc.credited_minutes)
          else 0 end) as completed_minutes,
      sum(case when a.status in ('verified', 'credited') then
            coalesce(a.actual_minutes_worked, ji.credited_minutes_override, jrc.credited_minutes)
          else 0 end) as verified_minutes
    from assignment a
    join job_instance ji on ji.id = a.job_instance_id
    join job_role_config jrc on jrc.id = ji.job_role_config_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.season_id = p_season_id
      and jrc.earns_organization_volunteer_credit = true
    group by a.family_id
  )
  select
    hc.family_id,
    hc.registered_children,
    (hc.registered_children * hc.minutes_per_child)::integer as required_minutes,
    coalesce(am.scheduled_minutes, 0) as scheduled_minutes,
    coalesce(am.completed_minutes, 0) as completed_minutes,
    coalesce(am.verified_minutes, 0) as verified_minutes,
    greatest(0, (hc.registered_children * hc.minutes_per_child) - coalesce(am.verified_minutes, 0))::integer as remaining_minutes
  from household_children hc
  left join assignment_minutes am on am.family_id = hc.family_id;
$$;

comment on function families_owing_hours is
  'Household obligation in minutes, per manual p.16. remaining_minutes counts only VERIFIED (or credited) time against the requirement.';

-- ---------- 2. $25 replacement credit — household-level ----------

alter table fundraising_credit_ledger alter column player_season_id drop not null;
alter table fundraising_credit_ledger add column if not exists family_id uuid references family(id);
alter table fundraising_credit_ledger add constraint chk_credit_has_a_target
  check (player_season_id is not null or family_id is not null);

comment on column fundraising_credit_ledger.family_id is
  'Household-level credit target (e.g. $25 replacement credit).';

create or replace function family_fundraising_summary(p_family_id uuid, p_season_id uuid)
returns table (
  required_total numeric,
  cash_total numeric,
  credit_total numeric,
  remaining_total numeric
)
language sql stable
as $$
  with children as (
    select ps.id as player_season_id, sc.fundraising_goal_per_child
    from player p
    join player_season ps on ps.player_id = p.id and ps.season_id = p_season_id
    join season_config sc on sc.id = ps.season_config_id
    where p.family_id = p_family_id
  ),
  cash as (
    select coalesce(sum(fcl.amount), 0) as total
    from fundraising_cash_ledger fcl
    where fcl.player_season_id in (select player_season_id from children)
  ),
  credit as (
    select coalesce(sum(fcrl.amount), 0) as total
    from fundraising_credit_ledger fcrl
    where fcrl.player_season_id in (select player_season_id from children)
       or fcrl.family_id = p_family_id
  )
  select
    (select coalesce(sum(fundraising_goal_per_child), 0) from children) as required_total,
    (select total from cash) as cash_total,
    (select total from credit) as credit_total,
    greatest(0, (select coalesce(sum(fundraising_goal_per_child), 0) from children)
                - (select total from cash) - (select total from credit)) as remaining_total;
$$;

-- ---------- 3. Identity match states (manual p.18) ----------

alter table family add column if not exists match_status text not null default 'unmatched'
  check (match_status in ('unmatched', 'possible_match', 'needs_review', 'verified', 'confirmed_different_person', 'rejected', 'stale'));
alter table player add column if not exists match_status text not null default 'unmatched'
  check (match_status in ('unmatched', 'possible_match', 'needs_review', 'verified', 'confirmed_different_person', 'rejected', 'stale'));

comment on column family.match_status is 'Manual p.18 identity crosswalk.';
comment on column player.match_status is 'See family.match_status.';
