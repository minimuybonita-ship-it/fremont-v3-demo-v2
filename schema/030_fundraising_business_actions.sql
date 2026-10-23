-- ============================================================
-- 030_fundraising_business_actions.sql
-- Cash and credit stay SEPARATE ledgers (and separate from volunteer time).
--   * record_cash_entry   -> fundraising_cash_ledger   (actual money received; Commissioner only)
--   * review_social_share -> fundraising_credit_ledger (the $1 verified-share credit; Commissioner only,
--                            blocked until the season config records board approval)
-- No generic "insert a ledger row" function exists. Replacement credit lives in 029.
-- ============================================================

create or replace function record_cash_entry(
  p_player_season_id uuid,
  p_amount numeric,
  p_note text default null,
  p_campaign_id uuid default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_season uuid; v_status text; v_existing uuid; v_total numeric; v_id uuid; v_camp_season uuid;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can record cash received'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'Amount must be a non-zero dollar value'; end if;
  if p_amount <> round(p_amount, 2) then raise exception 'Amount cannot have more than 2 decimal places'; end if;
  if abs(p_amount) > 5000 then raise exception 'Amount is above the single-entry limit of $5,000'; end if;

  if p_idempotency_key is not null then
    select id into v_existing from fundraising_cash_ledger where idempotency_key = p_idempotency_key;
    if v_existing is not null then return v_existing; end if;          -- double-submit returns the same row
  end if;

  select ps.season_id into v_season from player_season ps where ps.id = p_player_season_id;
  if v_season is null then raise exception 'Player registration not found'; end if;
  select s.status into v_status from season s where s.id = v_season;
  if v_status not in ('registration_open', 'active') then raise exception 'This season is not open for cash entries'; end if;

  if p_campaign_id is not null then
    select season_id into v_camp_season from fundraising_campaign where id = p_campaign_id;
    if v_camp_season is distinct from v_season then raise exception 'That campaign belongs to a different season'; end if;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_player_season_id::text));    -- serialise per child
  if p_amount < 0 then
    -- corrections are append-only reversals: need a reason and can never take the child's cash below zero
    if p_note is null or length(btrim(p_note)) < 5 then raise exception 'A reversal needs a note explaining why'; end if;
    select coalesce(sum(amount), 0) into v_total from fundraising_cash_ledger where player_season_id = p_player_season_id;
    if v_total + p_amount < 0 then raise exception 'Reversal is larger than the cash recorded for this child'; end if;
  end if;

  insert into fundraising_cash_ledger (player_season_id, campaign_id, amount, recorded_by, note, idempotency_key)
  values (p_player_season_id, p_campaign_id, p_amount, auth.uid(), nullif(btrim(p_note), ''), p_idempotency_key)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function review_social_share(p_submission_id uuid, p_approve boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_s social_share_submission%rowtype; v_season uuid; v_cfg season_config; v_dup uuid;
begin
  if not auth_is_commissioner() then raise exception 'Only the Commissioner can review share submissions'; end if;
  select * into v_s from social_share_submission where id = p_submission_id for update;
  if not found then raise exception 'Submission not found'; end if;

  if v_s.status <> 'pending' then
    if (p_approve and v_s.status = 'approved') or (not p_approve and v_s.status = 'rejected') then return; end if;   -- idempotent
    raise exception 'This submission was already %', v_s.status;
  end if;

  if not p_approve then
    update social_share_submission set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = v_s.id;
    return;
  end if;

  select ps.season_id into v_season from player_season ps where ps.id = v_s.player_season_id;
  v_cfg := _latest_config(v_season);
  if v_cfg.id is null then raise exception 'Season has no configuration'; end if;
  -- FAIL CLOSED: the share credit is board-gated. No board approval recorded -> nothing can be approved.
  if not v_cfg.share_credit_board_approved then
    raise exception 'The share credit has not been approved by the board for this season; it cannot be awarded';
  end if;
  if v_cfg.share_credit_amount is null or v_cfg.share_credit_amount <= 0 then raise exception 'Invalid share credit amount'; end if;

  -- the same proof link cannot earn credit twice
  select id into v_dup from social_share_submission
    where status = 'approved' and id <> v_s.id and lower(btrim(proof_url)) = lower(btrim(v_s.proof_url)) limit 1;
  if v_dup is not null then raise exception 'This proof link was already approved for another submission'; end if;

  insert into fundraising_credit_ledger (player_season_id, source, source_reference_id, amount, credited_by)
  values (v_s.player_season_id, 'social_share', v_s.id, v_cfg.share_credit_amount, auth.uid());
  update social_share_submission
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), credit_amount = v_cfg.share_credit_amount
    where id = v_s.id;
end;
$$;

revoke execute on function record_cash_entry(uuid, numeric, text, uuid, text), review_social_share(uuid, boolean) from public, anon;
grant  execute on function record_cash_entry(uuid, numeric, text, uuid, text), review_social_share(uuid, boolean) to authenticated;
