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
    reg.total::integer, reg.ready::integer,
    case when reg.total > 0 then round(100.0 * reg.ready / reg.total, 1) else 0 end,
    vol.required, vol.verified,
    case when vol.required > 0 then round(100.0 * vol.verified / vol.required, 1) else 0 end,
    fund.required, fund.raised,
    case when fund.required > 0 then round(100.0 * fund.raised / fund.required, 1) else 0 end,
    equip.total::integer, equip.delivered::integer,
    case when equip.total > 0 then round(100.0 * equip.delivered / equip.total, 1) else 0 end
  from reg, vol, fund, equip;
end;
$$;

comment on function season_closeout_summary is
  'Aggregate-only rollup for the Reports/Closeout screen. Commissioner-only (schema/022) — raises for any other caller rather than returning an RLS-scoped partial result.';
