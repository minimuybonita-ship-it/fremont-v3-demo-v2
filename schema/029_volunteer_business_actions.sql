-- ============================================================
-- 029_volunteer_business_actions.sql
-- Server-side business actions for volunteer TIME and the no-show / replacement workflows.
-- The browser asks for a defined action; the database checks role, season, state and
-- amounts, writes atomically, and appends to assignment_audit_log. Clients have NO direct
-- INSERT/UPDATE on assignment, assignment_audit_log, replacement_pool_entry, no_show_record (027).
--
-- Every function: SECURITY DEFINER, fixed search_path, explicit role check inside, narrow
-- typed inputs (ids / small enums), fails closed (raises) on anything unexpected,
-- executable by `authenticated` only (never PUBLIC/anon).
--
-- V1 simplification (documented): a family claim or an approved Phase-B pairing creates the
-- assignment directly in 'scheduled' (the intermediate 'confirmed' step has no UI in V1).
-- ============================================================

-- ---------- internal helpers (no client grants) ----------
create or replace function _my_family_id()
returns uuid
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_ids uuid[];
begin
  select array_agg(x) into v_ids from auth_family_ids() as x;
  if v_ids is null or array_length(v_ids, 1) is null then
    raise exception 'Your account is not linked to a household';
  end if;
  if array_length(v_ids, 1) > 1 then
    raise exception 'Your account is linked to more than one household; ask the Commissioner to review';
  end if;
  return v_ids[1];
end;
$$;

create or replace function _family_registered_in_season(p_family uuid, p_season uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from player p
    join player_season ps on ps.player_id = p.id
    where p.family_id = p_family and ps.season_id = p_season
      and ps.registration_stage in ('submitted', 'review', 'correction_needed', 'approved', 'season_ready')
  )
$$;

create or replace function _audit_assignment(p_assignment uuid, p_from text, p_to text, p_note text)
returns void
language sql security definer
set search_path = public, pg_temp
as $$
  insert into assignment_audit_log (assignment_id, from_status, to_status, changed_by, note)
  values (p_assignment, p_from, p_to, auth.uid(), p_note)
$$;

create or replace function _staff_can_manage_event(p_game_event uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth_is_commissioner()
      or exists (select 1 from game_event ge
                 where ge.id = p_game_event and ge.team_id is not null
                   and ge.team_id in (select auth_team_ids()))
$$;

create or replace function _latest_config(p_season uuid)
returns season_config
language sql stable security definer
set search_path = public, pg_temp
as $$
  select * from season_config where season_id = p_season order by effective_at desc limit 1
$$;

-- ---------- read-only views for families (aggregate; no other family is identifiable) ----------
create or replace function open_jobs_for_season(p_season_id uuid)
returns table (
  job_instance_id uuid, game_event_id uuid, opponent text, location text, starts_at timestamptz,
  team_name text, role_name text, credited_minutes integer, volunteers_needed integer,
  filled bigint, i_have_it boolean
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_family uuid;
begin
  v_family := _my_family_id();
  return query
  select ji.id, ge.id, ge.opponent, ge.location, ge.starts_at, t.name, jrc.role_name,
         coalesce(ji.credited_minutes_override, jrc.credited_minutes)::integer,
         ji.volunteers_needed,
         (select count(*) from assignment a where a.job_instance_id = ji.id
            and a.status in ('claimed','confirmed','scheduled','checked_in','completed','verified','credited')),
         exists (select 1 from assignment a where a.job_instance_id = ji.id and a.family_id = v_family and a.status <> 'cancelled')
  from job_instance ji
  join game_event ge on ge.id = ji.game_event_id
  join job_role_config jrc on jrc.id = ji.job_role_config_id
  left join team t on t.id = ge.team_id
  where ge.season_id = p_season_id
    and ge.closed_at is null
    and (ge.starts_at is null or ge.starts_at > now())
    and jrc.earns_organization_volunteer_credit
  order by ge.starts_at nulls last, jrc.role_name;
end;
$$;

create or replace function open_replacement_shifts(p_season_id uuid)
returns table (
  entry_id uuid, opponent text, location text, starts_at timestamptz,
  role_name text, credited_minutes integer, fee_amount numeric
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_family uuid;
begin
  v_family := _my_family_id();
  return query
  select e.id, ge.opponent, ge.location, ge.starts_at, jrc.role_name,
         coalesce(ji.credited_minutes_override, jrc.credited_minutes)::integer, e.fee_amount
  from replacement_pool_entry e
  join assignment a on a.id = e.assignment_id
  join job_instance ji on ji.id = a.job_instance_id
  join game_event ge on ge.id = ji.game_event_id
  join job_role_config jrc on jrc.id = ji.job_role_config_id
  where ge.season_id = p_season_id
    and e.status = 'open'
    and e.released_by_family_id <> v_family
    and (ge.starts_at is null or ge.starts_at > now())
  order by ge.starts_at nulls last;
end;
$$;

-- ---------- Phase A: a household chooses a job ----------
create or replace function claim_volunteer_job(p_job_instance_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_family uuid; v_ji job_instance%rowtype; v_ge game_event%rowtype;
  v_status text; v_earns boolean; v_existing uuid; v_count integer; v_id uuid;
begin
  v_family := _my_family_id();

  select * into v_ji from job_instance where id = p_job_instance_id for update;   -- serialises capacity checks
  if not found then raise exception 'Job not found'; end if;
  select * into v_ge from game_event where id = v_ji.game_event_id;
  select s.status into v_status from season s where s.id = v_ge.season_id;
  select jrc.earns_organization_volunteer_credit into v_earns from job_role_config jrc where jrc.id = v_ji.job_role_config_id;

  if v_status not in ('registration_open', 'active') then raise exception 'This season is not open for volunteer selection'; end if;
  if v_ge.closed_at is not null then raise exception 'This event is already closed'; end if;
  if v_ge.starts_at is not null and v_ge.starts_at <= now() then raise exception 'This event has already started'; end if;
  if not coalesce(v_earns, false) then raise exception 'This job does not earn organization volunteer credit'; end if;
  if not _family_registered_in_season(v_family, v_ge.season_id) then
    raise exception 'Submit a registration for at least one child before choosing volunteer jobs';
  end if;

  select id into v_existing from assignment
    where job_instance_id = p_job_instance_id and family_id = v_family and status <> 'cancelled' limit 1;
  if v_existing is not null then return v_existing; end if;          -- idempotent double-tap

  select count(*) into v_count from assignment
    where job_instance_id = p_job_instance_id
      and status in ('claimed','confirmed','scheduled','checked_in','completed','verified','credited');
  if v_count >= v_ji.volunteers_needed then raise exception 'This job is already full'; end if;

  insert into assignment (job_instance_id, family_id, status, claimed_via)
  values (p_job_instance_id, v_family, 'scheduled', 'family_selection')
  returning id into v_id;
  perform _audit_assignment(v_id, null, 'scheduled', 'Household chose this job (Phase A)');
  return v_id;
end;
$$;

-- ---------- Phase B: apply a Commissioner-approved proposal ----------
-- The proposal itself is computed read-only in the browser (propose). This function is the ONLY way a
-- proposal becomes real rows, it is Commissioner-only, and it RE-VALIDATES every pair at apply time
-- (a stale or tampered proposal fails the whole batch; nothing is partially applied).
create or replace function apply_auto_assignments(p_season_id uuid, p_pairs jsonb)
returns table (inserted integer, skipped integer)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_pair jsonb; v_ji_id uuid; v_fam uuid; v_ji job_instance%rowtype; v_ge game_event%rowtype;
  v_count integer; v_id uuid; v_ins integer := 0; v_skip integer := 0; v_status text;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can apply auto-assignments'; end if;
  if p_pairs is null or jsonb_typeof(p_pairs) <> 'array' then raise exception 'Expected a list of assignments'; end if;
  if jsonb_array_length(p_pairs) = 0 then return query select 0, 0; return; end if;
  if jsonb_array_length(p_pairs) > 500 then raise exception 'Too many assignments in one batch (max 500)'; end if;

  select s.status into v_status from season s where s.id = p_season_id;
  if v_status is null then raise exception 'Season not found'; end if;
  if v_status not in ('registration_open', 'active') then raise exception 'Season is not open'; end if;

  for v_pair in select * from jsonb_array_elements(p_pairs) loop
    v_ji_id := (v_pair ->> 'job_instance_id')::uuid;
    v_fam   := (v_pair ->> 'family_id')::uuid;
    if v_ji_id is null or v_fam is null then raise exception 'Each assignment needs job_instance_id and family_id'; end if;

    select * into v_ji from job_instance where id = v_ji_id for update;
    if not found then raise exception 'Job % not found', v_ji_id; end if;
    select * into v_ge from game_event where id = v_ji.game_event_id;
    if v_ge.season_id <> p_season_id then raise exception 'Job % is not in this season', v_ji_id; end if;
    if v_ge.closed_at is not null then raise exception 'Event for job % is closed', v_ji_id; end if;
    if not exists (select 1 from family where id = v_fam) then raise exception 'Family % not found', v_fam; end if;
    if not _family_registered_in_season(v_fam, p_season_id) then
      raise exception 'Family % has no submitted registration this season', v_fam;
    end if;

    if exists (select 1 from assignment where job_instance_id = v_ji_id and family_id = v_fam and status <> 'cancelled') then
      v_skip := v_skip + 1;                                            -- idempotent re-apply
      continue;
    end if;

    select count(*) into v_count from assignment
      where job_instance_id = v_ji_id
        and status in ('claimed','confirmed','scheduled','checked_in','completed','verified','credited');
    if v_count >= v_ji.volunteers_needed then
      raise exception 'Job % is already full; re-run the proposal', v_ji_id;
    end if;

    insert into assignment (job_instance_id, family_id, status, claimed_via)
    values (v_ji_id, v_fam, 'scheduled', 'auto_assigned') returning id into v_id;
    perform _audit_assignment(v_id, null, 'scheduled', 'Auto-assigned (Phase B), approved by Commissioner');
    v_ins := v_ins + 1;
  end loop;

  return query select v_ins, v_skip;
end;
$$;

-- ---------- Game Day: check in / complete / verify ----------
create or replace function assignment_check_in(p_assignment_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_a assignment%rowtype; v_ge uuid;
begin
  select a.* into v_a from assignment a where a.id = p_assignment_id for update;
  if not found then raise exception 'Assignment not found'; end if;
  select ji.game_event_id into v_ge from job_instance ji where ji.id = v_a.job_instance_id;
  if not _staff_can_manage_event(v_ge) then raise exception 'Not authorized for this event'; end if;
  if v_a.status = 'checked_in' then return; end if;                     -- idempotent
  if v_a.status not in ('scheduled', 'confirmed') then
    raise exception 'Cannot check in from status "%"', v_a.status;
  end if;
  update assignment set status = 'checked_in', checked_in_at = now(), updated_at = now() where id = v_a.id;
  perform _audit_assignment(v_a.id, v_a.status, 'checked_in', 'Checked in at Game Day');
end;
$$;

create or replace function assignment_complete(p_assignment_id uuid, p_minutes integer default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_a assignment%rowtype; v_ji job_instance%rowtype; v_jrc job_role_config%rowtype; v_min integer;
begin
  select a.* into v_a from assignment a where a.id = p_assignment_id for update;
  if not found then raise exception 'Assignment not found'; end if;
  select * into v_ji from job_instance where id = v_a.job_instance_id;
  select * into v_jrc from job_role_config where id = v_ji.job_role_config_id;
  if not _staff_can_manage_event(v_ji.game_event_id) then raise exception 'Not authorized for this event'; end if;
  if v_a.status = 'completed' then return; end if;                      -- idempotent
  if v_a.status <> 'checked_in' then raise exception 'Cannot complete from status "%"', v_a.status; end if;

  v_min := coalesce(p_minutes, v_ji.credited_minutes_override, v_jrc.credited_minutes);
  if v_min is null or v_min < 1 or v_min > 720 then
    raise exception 'Minutes worked must be between 1 and 720';
  end if;
  update assignment set status = 'completed', completed_at = now(), actual_minutes_worked = v_min, updated_at = now()
    where id = v_a.id;
  perform _audit_assignment(v_a.id, v_a.status, 'completed', format('Completed; %s minutes recorded', v_min));
end;
$$;

create or replace function assignment_verify(p_assignment_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_a assignment%rowtype; v_ji job_instance%rowtype; v_jrc job_role_config%rowtype; v_ge game_event%rowtype;
  v_role text;
begin
  select a.* into v_a from assignment a where a.id = p_assignment_id for update;
  if not found then raise exception 'Assignment not found'; end if;
  select * into v_ji from job_instance where id = v_a.job_instance_id;
  select * into v_jrc from job_role_config where id = v_ji.job_role_config_id;
  select * into v_ge from game_event where id = v_ji.game_event_id;

  if auth_is_commissioner() then
    v_role := 'commissioner';
  else
    -- team staff may verify only if they hold the role this job names as its verifier, on this event's team,
    -- and never for their own household
    select ar.role into v_role from app_role ar
      where ar.auth_user_id = auth.uid() and ar.team_id = v_ge.team_id and v_ge.team_id is not null
        and ar.role in ('team_parent', 'coach') and ar.role = v_jrc.verifier_role
      limit 1;
    if v_role is null then raise exception 'You are not the designated verifier for this job'; end if;
    if v_a.family_id in (select auth_family_ids()) then raise exception 'You cannot verify your own household''s volunteer time'; end if;
  end if;

  if v_a.status = 'verified' then return; end if;                       -- idempotent
  if v_a.status <> 'completed' then raise exception 'Cannot verify from status "%"', v_a.status; end if;
  if v_a.actual_minutes_worked is null then raise exception 'No minutes were recorded for this assignment'; end if;

  update assignment set status = 'verified', verified_at = now(), verified_by_role = v_role, updated_at = now()
    where id = v_a.id;
  perform _audit_assignment(v_a.id, v_a.status, 'verified',
    format('Verified by %s; %s minutes', v_role, v_a.actual_minutes_worked));
end;
$$;

-- ---------- $50 no-show ----------
create or replace function assignment_report_no_show(p_assignment_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_a assignment%rowtype; v_ji job_instance%rowtype; v_ge game_event%rowtype; v_cfg season_config; v_id uuid;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can record a no-show'; end if;
  select a.* into v_a from assignment a where a.id = p_assignment_id for update;
  if not found then raise exception 'Assignment not found'; end if;
  select * into v_ji from job_instance where id = v_a.job_instance_id;
  select * into v_ge from game_event where id = v_ji.game_event_id;

  select id into v_id from no_show_record where assignment_id = v_a.id;
  if v_id is not null then return v_id; end if;                          -- idempotent
  if v_a.status not in ('claimed', 'confirmed', 'scheduled') then
    raise exception 'A no-show can only be recorded for a scheduled job (status is "%")', v_a.status;
  end if;
  if v_ge.starts_at is null or v_ge.starts_at > now() then
    raise exception 'The event has not started yet';
  end if;

  v_cfg := _latest_config(v_ge.season_id);
  if v_cfg.id is null then raise exception 'Season has no configuration'; end if;

  update assignment set status = 'no_show', updated_at = now() where id = v_a.id;
  insert into no_show_record (assignment_id, family_id, fee_amount, pay_by_date)
  values (v_a.id, v_a.family_id, v_cfg.no_show_fee_amount, current_date + v_cfg.no_show_grace_period_days)
  returning id into v_id;
  perform _audit_assignment(v_a.id, v_a.status, 'no_show',
    format('No-show recorded; fee $%s (snapshot of season config)', v_cfg.no_show_fee_amount));
  return v_id;
end;
$$;

create or replace function resolve_no_show(p_no_show_id uuid, p_resolution text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r no_show_record%rowtype;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can resolve a no-show fee'; end if;
  if p_resolution not in ('paid', 'posted_to_org_process', 'waived') then
    raise exception 'Resolution must be paid, posted_to_org_process or waived';
  end if;
  select * into v_r from no_show_record where id = p_no_show_id for update;
  if not found then raise exception 'No-show record not found'; end if;
  if v_r.resolution_status = p_resolution then return; end if;           -- idempotent
  if v_r.resolution_status <> 'pending' then
    raise exception 'This no-show is already resolved as "%"', v_r.resolution_status;
  end if;
  update no_show_record set resolution_status = p_resolution, resolved_at = now() where id = v_r.id;
  perform _audit_assignment(v_r.assignment_id, 'no_show', 'no_show', format('No-show fee resolved: %s', p_resolution));
end;
$$;

-- ---------- $25 replacement pool ----------
create or replace function request_replacement(p_assignment_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_a assignment%rowtype; v_ji job_instance%rowtype; v_ge game_event%rowtype; v_jrc job_role_config%rowtype;
  v_cfg season_config; v_id uuid;
begin
  select a.* into v_a from assignment a where a.id = p_assignment_id for update;
  if not found then raise exception 'Assignment not found'; end if;
  if v_a.family_id not in (select auth_family_ids()) then raise exception 'This is not your household''s assignment'; end if;
  select * into v_ji from job_instance where id = v_a.job_instance_id;
  select * into v_ge from game_event where id = v_ji.game_event_id;
  select * into v_jrc from job_role_config where id = v_ji.job_role_config_id;

  select id into v_id from replacement_pool_entry where assignment_id = v_a.id and status not in ('cancelled');
  if v_id is not null then return v_id; end if;                          -- idempotent

  if v_a.status not in ('claimed', 'confirmed', 'scheduled') then
    raise exception 'A replacement can only be requested for a scheduled job (status is "%")', v_a.status;
  end if;
  if not v_jrc.replacement_allowed then raise exception 'This job does not allow replacements'; end if;
  if v_ge.starts_at is not null and v_ge.starts_at <= now() then raise exception 'This event has already started'; end if;

  v_cfg := _latest_config(v_ge.season_id);
  if v_cfg.id is null then raise exception 'Season has no configuration'; end if;

  update assignment set status = 'replacement_requested', updated_at = now() where id = v_a.id;
  insert into replacement_pool_entry (assignment_id, released_by_family_id, fee_amount)
  values (v_a.id, v_a.family_id, v_cfg.replacement_fee_amount) returning id into v_id;
  perform _audit_assignment(v_a.id, v_a.status, 'replacement_requested',
    format('Household requested a replacement; fee $%s snapshot', v_cfg.replacement_fee_amount));
  return v_id;
end;
$$;

create or replace function claim_replacement_shift(p_entry_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_family uuid; v_e replacement_pool_entry%rowtype; v_season uuid; v_start timestamptz;
begin
  v_family := _my_family_id();
  select * into v_e from replacement_pool_entry where id = p_entry_id for update;   -- first valid claim wins
  if not found then raise exception 'Replacement shift not found'; end if;
  if v_e.claimed_by_family_id = v_family then return; end if;            -- idempotent
  if v_e.status <> 'open' then raise exception 'This shift was already claimed'; end if;
  if v_e.released_by_family_id = v_family then raise exception 'You cannot claim the shift your own household released'; end if;

  select ge.season_id, ge.starts_at into v_season, v_start
    from assignment a join job_instance ji on ji.id = a.job_instance_id join game_event ge on ge.id = ji.game_event_id
    where a.id = v_e.assignment_id;
  if v_start is not null and v_start <= now() then raise exception 'This event has already started'; end if;
  if not _family_registered_in_season(v_family, v_season) then
    raise exception 'Submit a registration for at least one child before claiming shifts';
  end if;

  update replacement_pool_entry set status = 'claimed', claimed_by_family_id = v_family, claimed_at = now() where id = v_e.id;
  perform _audit_assignment(v_e.assignment_id, 'replacement_requested', 'replacement_requested', 'Replacement shift claimed by another household');
end;
$$;

create or replace function complete_replacement_shift(p_entry_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_e replacement_pool_entry%rowtype; v_ge game_event%rowtype;
begin
  select * into v_e from replacement_pool_entry where id = p_entry_id for update;
  if not found then raise exception 'Replacement shift not found'; end if;
  select ge.* into v_ge from assignment a join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id where a.id = v_e.assignment_id;
  if not _staff_can_manage_event(v_ge.id) then raise exception 'Not authorized for this event'; end if;
  if v_e.status = 'completed' then return; end if;                       -- idempotent
  if v_e.status <> 'claimed' then raise exception 'Only a claimed shift can be marked completed (status is "%")', v_e.status; end if;
  if v_ge.starts_at is null or v_ge.starts_at > now() then raise exception 'The event has not started yet'; end if;
  update replacement_pool_entry set status = 'completed' where id = v_e.id;
  perform _audit_assignment(v_e.assignment_id, 'replacement_requested', 'replacement_requested', 'Replacement shift worked; awaiting Commissioner verification');
end;
$$;

-- Credit posts ONLY here: Commissioner verifies a COMPLETED replacement shift -> $ credit to the
-- CLAIMING household (family-level row, not tied to one child). Idempotent; the unique index
-- uq_credit_one_per_source_reference is the backstop.
create or replace function verify_replacement_credit(p_entry_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_e replacement_pool_entry%rowtype; v_orig text;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can verify a replacement credit'; end if;
  select * into v_e from replacement_pool_entry where id = p_entry_id for update;
  if not found then raise exception 'Replacement shift not found'; end if;
  if v_e.status = 'credited' then return; end if;                        -- idempotent: never credit twice
  if v_e.status <> 'completed' then raise exception 'Cannot credit: shift status is "%", not "completed"', v_e.status; end if;
  if v_e.claimed_by_family_id is null then raise exception 'Shift has no claiming household'; end if;
  if v_e.fee_amount is null or v_e.fee_amount <= 0 then raise exception 'Invalid credit amount'; end if;

  insert into fundraising_credit_ledger (family_id, player_season_id, source, source_reference_id, amount, credited_by)
  values (v_e.claimed_by_family_id, null, 'replacement_pool', v_e.id, v_e.fee_amount, auth.uid());

  update replacement_pool_entry set status = 'credited', verified_at = now(), credit_issued = true where id = v_e.id;

  select status into v_orig from assignment where id = v_e.assignment_id;
  if v_orig = 'replacement_requested' then
    update assignment set status = 'cancelled', updated_at = now() where id = v_e.assignment_id;
    perform _audit_assignment(v_e.assignment_id, v_orig, 'cancelled', 'Replacement verified; original assignment closed');
  end if;
end;
$$;

-- ---------- grants: signed-in users only; internal helpers: nobody ----------
revoke execute on function _my_family_id(), _family_registered_in_season(uuid, uuid), _audit_assignment(uuid, text, text, text),
  _staff_can_manage_event(uuid), _latest_config(uuid) from public, anon, authenticated;

revoke execute on function open_jobs_for_season(uuid), open_replacement_shifts(uuid), claim_volunteer_job(uuid),
  apply_auto_assignments(uuid, jsonb), assignment_check_in(uuid), assignment_complete(uuid, integer), assignment_verify(uuid),
  assignment_report_no_show(uuid), resolve_no_show(uuid, text), request_replacement(uuid), claim_replacement_shift(uuid),
  complete_replacement_shift(uuid), verify_replacement_credit(uuid) from public, anon;
grant execute on function open_jobs_for_season(uuid), open_replacement_shifts(uuid), claim_volunteer_job(uuid),
  apply_auto_assignments(uuid, jsonb), assignment_check_in(uuid), assignment_complete(uuid, integer), assignment_verify(uuid),
  assignment_report_no_show(uuid), resolve_no_show(uuid, text), request_replacement(uuid), claim_replacement_shift(uuid),
  complete_replacement_shift(uuid), verify_replacement_credit(uuid) to authenticated;
