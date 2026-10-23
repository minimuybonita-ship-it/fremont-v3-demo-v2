-- 022: season_closeout_summary and can_close_season now raise for any non-Commissioner caller
-- (a guardian previously got a silently partial, RLS-scoped aggregate). Original long header abbreviated.
-- Note: 022b below supersedes the season_closeout_summary body (integer type casts).

create or replace function season_closeout_summary(p_season_id uuid)
returns table (
  registration_total integer,
  registration_season_ready integer,
  registration_percent numeric,
  volunteer_required_minutes bigint,
  volunteer_verified_minutes bigint,
  volunteer_percent numeric,
  fundraising_required numeric,
  fundraising_raised numeric,
  fundraising_percent numeric,
  equipment_total integer,
  equipment_delivered integer,
  equipment_percent numeric
)
language plpgsql stable
set search_path = public, pg_temp
as $$
begin
  if not auth_is_commissioner() then
    raise exception 'season_closeout_summary is Commissioner-only';
  end if;
  return query
  with reg as (
    select count(*) as total, count(*) filter (where registration_stage = 'season_ready') as ready
    from player_season where season_id = p_season_id
  ),
  vol as (
    select
      coalesce(sum(required_minutes), 0) as required,
      coalesce(sum(verified_minutes), 0) as verified
    from families_owing_hours(p_season_id)
  ),
  fund as (
    select
      coalesce(sum(sc.fundraising_goal_per_child), 0) as required,
      coalesce((select sum(fcl.amount) from fundraising_cash_ledger fcl
                where fcl.player_season_id in (select id from player_season where season_id = p_season_id)), 0)
      + coalesce((select sum(fcrl.amount) from fundraising_credit_ledger fcrl
                  where fcrl.player_season_id in (select id from player_season where season_id = p_season_id)
                     or fcrl.family_id in (select p.family_id from player p
                                            join player_season ps on ps.player_id = p.id
                                            where ps.season_id = p_season_id)), 0) as raised
    from player_season ps join season_config sc on sc.id = ps.season_config_id
    where ps.season_id = p_season_id
  ),
  equip as (
    select count(*) as total, count(*) filter (where uo.order_status = 'delivered') as delivered
    from uniform_order uo
    join player_season ps on ps.id = uo.player_season_id
    where ps.season_id = p_season_id
  )
  select
    reg.total, reg.ready,
    case when reg.total > 0 then round(100.0 * reg.ready / reg.total, 1) else 0 end,
    vol.required, vol.verified,
    case when vol.required > 0 then round(100.0 * vol.verified / vol.required, 1) else 0 end,
    fund.required, fund.raised,
    case when fund.required > 0 then round(100.0 * fund.raised / fund.required, 1) else 0 end,
    equip.total, equip.delivered,
    case when equip.total > 0 then round(100.0 * equip.delivered / equip.total, 1) else 0 end
  from reg, vol, fund, equip;
end;
$$;

comment on function season_closeout_summary is
  'Aggregate-only rollup for the Reports/Closeout screen. Commissioner-only (schema/022) — raises for any other caller rather than returning an RLS-scoped partial result.';

create or replace function can_close_season(p_season_id uuid)
returns table (ready boolean, open_exceptions integer, reasons text[])
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  v_needs_review integer;
  v_open_pool integer;
  v_pending_shares integer;
  v_pending_no_shows integer;
  v_correction_needed integer;
  v_reasons text[] := '{}';
begin
  if not auth_is_commissioner() then
    raise exception 'can_close_season is Commissioner-only';
  end if;

  select count(*) into v_needs_review from assignment a
    join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.season_id = p_season_id and a.status = 'needs_review';
  if v_needs_review > 0 then v_reasons := v_reasons || format('%s assignment(s) need review', v_needs_review); end if;

  select count(*) into v_open_pool from replacement_pool_entry rpe
    join assignment a on a.id = rpe.assignment_id
    join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.season_id = p_season_id and rpe.status in ('open', 'claimed', 'completed');
  if v_open_pool > 0 then v_reasons := v_reasons || format('%s replacement pool entr(y/ies) unresolved', v_open_pool); end if;

  select count(*) into v_pending_shares from social_share_submission sss
    join player_season ps on ps.id = sss.player_season_id
    where ps.season_id = p_season_id and sss.status = 'pending';
  if v_pending_shares > 0 then v_reasons := v_reasons || format('%s share submission(s) pending review', v_pending_shares); end if;

  select count(*) into v_pending_no_shows from no_show_record nsr
    join assignment a on a.id = nsr.assignment_id
    join job_instance ji on ji.id = a.job_instance_id
    join game_event ge on ge.id = ji.game_event_id
    where ge.season_id = p_season_id and nsr.resolution_status = 'pending';
  if v_pending_no_shows > 0 then v_reasons := v_reasons || format('%s no-show fee(s) unresolved', v_pending_no_shows); end if;

  select count(*) into v_correction_needed from player_season
    where season_id = p_season_id and registration_stage in ('submitted', 'review', 'correction_needed');
  if v_correction_needed > 0 then v_reasons := v_reasons || format('%s registration(s) not yet Season Ready or Withdrawn', v_correction_needed); end if;

  return query select
    (array_length(v_reasons, 1) is null),
    coalesce(v_needs_review, 0) + coalesce(v_open_pool, 0) + coalesce(v_pending_shares, 0) + coalesce(v_pending_no_shows, 0) + coalesce(v_correction_needed, 0),
    v_reasons;
end;
$$;

comment on function can_close_season is
  'Fails closed: ready is true ONLY when every exception category is explicitly zero. Commissioner-only (schema/022) — raises for any other caller.';
