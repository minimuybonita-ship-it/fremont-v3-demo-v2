-- ============================================================
-- 026 — DRAFT ONLY. NOT APPLIED to xyhtaufdyyokjvzctums or anywhere else.
-- Needs Minerva's approval before it is run (financial-integrity items).
--
-- WHY: the staging database is default-deny. The V3 screens built on top
-- of it need these writes, and no client policy exists for them today:
--   * Phase B "Apply"            -> INSERT assignment
--   * Verify replacement ($25)   -> UPDATE replacement_pool_entry + INSERT fundraising_credit_ledger
--   * Approve $1 share credit    -> INSERT fundraising_credit_ledger
--   * Record cash (Team Parent)  -> INSERT fundraising_cash_ledger
--   * Commissioner creates/links households -> INSERT family, guardian
-- Smallest correction = Commissioner-only policies below. For the two
-- ledgers, the stricter alternative is SECURITY DEFINER RPCs that also
-- enforce "credit only after verified completion / approved share and
-- board gate on" server-side. That choice is Minerva's.
-- ============================================================

create policy assignment_commissioner_insert on assignment
  for insert with check (auth_is_commissioner());

create policy replacement_pool_commissioner_write on replacement_pool_entry
  for all using (auth_is_commissioner()) with check (auth_is_commissioner());

create policy fundraising_credit_commissioner_insert on fundraising_credit_ledger
  for insert with check (auth_is_commissioner());

create policy fundraising_cash_staff_insert on fundraising_cash_ledger
  for insert with check (
    auth_is_commissioner()
    or player_season_id in (select id from player_season where team_id in (select auth_team_ids()))
  );

create policy family_commissioner_insert on family
  for insert with check (auth_is_commissioner());
create policy guardian_commissioner_insert on guardian
  for insert with check (auth_is_commissioner());
