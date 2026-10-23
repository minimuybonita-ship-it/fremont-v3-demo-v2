-- ============================================================
-- 028_write_guards_and_indexes.sql
-- Closes row-level-only RLS gaps found while auditing the write paths, and
-- adds the uniqueness constraints the business-action functions rely on.
--
-- Gaps found (all verified from pg_policies on staging):
--  * assignment_family_claim / assignment_staff_manage let a family or team
--    staff UPDATE ANY column of an assignment (incl. actual_minutes_worked,
--    status, job_instance_id) -> self-awarded volunteer minutes.
--  * assignment_audit_log_insert was WITH CHECK (true): anyone could forge audit rows.
--  * no_show_record_insert let team staff choose the fee amount.
--  * social_share_submission family INSERT let a family insert status='approved'
--    with any credit_amount.
--  * player_season family INSERT/UPDATE (no column limits) let a family set
--    registration_stage='season_ready', pick any season_config_id (lower hours),
--    or assign itself a team.
--  * event_signup_item_write: any signed-in user could insert/delete unclaimed rows.
-- ============================================================

-- 1. Broad client write policies on consequential tables ------------------
-- The policies assignment_family_claim, assignment_staff_manage, assignment_audit_log_insert,
-- no_show_record_insert, no_show_record_commissioner_update and
-- social_share_submission_commissioner_update are made INERT by 027 (INSERT/UPDATE privilege
-- revoked from `authenticated` on those tables; a policy cannot grant what the table privilege
-- withholds). Dropping them is optional tidy-up: see 028b_OPTIONAL_drop_inert_policies.sql (NOT applied).

-- Tighten (ALTER, not drop) the two policies that still matter:
alter policy event_signup_item_write on event_signup_item
  using (auth_is_commissioner()) with check (auth_is_commissioner());

-- pool entries stay readable to signed-in users (families browse open shifts), never to anon
alter policy replacement_pool_read on replacement_pool_entry to authenticated;

-- 2. Uniqueness the business actions depend on ---------------------------
create unique index if not exists uq_assignment_active_family_job
  on assignment (job_instance_id, family_id) where status <> 'cancelled';

create unique index if not exists uq_no_show_one_per_assignment
  on no_show_record (assignment_id);

create unique index if not exists uq_credit_one_per_source_reference
  on fundraising_credit_ledger (source, source_reference_id)
  where source in ('replacement_pool', 'social_share') and source_reference_id is not null;

alter table fundraising_cash_ledger add column if not exists idempotency_key text;
create unique index if not exists uq_cash_idempotency_key
  on fundraising_cash_ledger (idempotency_key) where idempotency_key is not null;

-- 3. Guard: player_season (family-writable row; only registration fields are theirs) ----
create or replace function _player_season_write_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg uuid;
begin
  -- SQL editor / service role (no JWT user) and the Commissioner are not restricted.
  if auth.uid() is null or auth_is_commissioner() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select id into v_cfg from season_config
      where season_id = new.season_id order by effective_at desc limit 1;
    if v_cfg is null then
      raise exception 'This season has no configuration yet; registration cannot start';
    end if;
    new.season_config_id := v_cfg;          -- always the season's current config
    new.registration_stage := 'draft';      -- families can only START a draft
    new.team_id := null;
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.correction_note := null;
    new.correction_due_at := null;
    new.submitted_at := null;
    new.season_ready_at := null;
  else
    new.season_id := old.season_id;
    new.player_id := old.player_id;
    new.season_config_id := old.season_config_id;
    new.team_id := old.team_id;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.correction_note := old.correction_note;
    new.correction_due_at := old.correction_due_at;
    new.season_ready_at := old.season_ready_at;
  end if;
  return new;
end;
$$;

create trigger trg_player_season_write_guard
  before insert or update on player_season
  for each row execute function _player_season_write_guard();

-- 4. Guard: social_share_submission INSERT (a family can only ever file a PENDING proof) ----
create or replace function _social_share_insert_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.proof_url is null or new.proof_url !~* '^https?://\S+$' then
    raise exception 'Proof must be a link starting with http:// or https://';
  end if;
  new.proof_url := btrim(new.proof_url);
  new.status := 'pending';
  new.reviewed_by := null;
  new.reviewed_at := null;
  -- display-only snapshot; the credit actually posted is decided by review_social_share()
  select c.share_credit_amount into new.credit_amount
    from player_season ps
    join season_config c on c.season_id = ps.season_id
    where ps.id = new.player_season_id
    order by c.effective_at desc limit 1;
  return new;
end;
$$;

create trigger trg_social_share_insert_guard
  before insert on social_share_submission
  for each row execute function _social_share_insert_guard();

revoke execute on function _player_season_write_guard()   from public, anon, authenticated;
revoke execute on function _social_share_insert_guard()   from public, anon, authenticated;
