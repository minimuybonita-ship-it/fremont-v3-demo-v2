-- 025: can_close_season registration check inverted to an allow-list of RESOLVED stages
-- (season_ready, withdrawn, refunded). An all-'draft' season previously returned ready=true. Original long header abbreviated.

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
  v_not_resolved integer;
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

  -- FIX (025): allow-list of resolved stages, not a block-list of in-progress ones.
  -- 'draft' (never started Season Setup) now correctly blocks closeout.
  select count(*) into v_not_resolved from player_season
    where season_id = p_season_id and registration_stage not in ('season_ready', 'withdrawn', 'refunded');
  if v_not_resolved > 0 then v_reasons := v_reasons || format('%s registration(s) not yet Season Ready or Withdrawn/Refunded', v_not_resolved); end if;

  return query select
    (array_length(v_reasons, 1) is null),
    coalesce(v_needs_review, 0) + coalesce(v_open_pool, 0) + coalesce(v_pending_shares, 0) + coalesce(v_pending_no_shows, 0) + coalesce(v_not_resolved, 0),
    v_reasons;
end;
$$;

comment on function can_close_season is
  'Fails closed: ready is true ONLY when every exception category is explicitly zero, including any player_season not yet in a resolved stage (season_ready/withdrawn/refunded). Commissioner-only (schema/022). Registration check corrected in schema/025 after the migration rehearsal caught an all-draft season reporting ready=true.';
