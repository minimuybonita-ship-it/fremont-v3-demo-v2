-- ============================================================
-- 999b_legacy_money_import.sql — ONE-OFF, ADDITIVE import of legacy box-sale money into the V3 ledgers.
-- Completes the "box-sale money -> fundraising_cash_ledger / fundraising_credit_ledger" step that 999 left as a comment.
--
-- Input (jsonb array, built by a human from the legacy export): [{"legacy_player_id":"p123","money_in":120.50,"credit_earned":10}]
--   money_in      -> fundraising_cash_ledger   (actual money; kept bit-for-bit, never recomputed)
--   credit_earned -> fundraising_credit_ledger (source 'product_sale', child-level)
-- Guarantees: ALL-OR-NOTHING (any unknown/invalid row aborts the whole batch) · IDEMPOTENT (re-running adds nothing) ·
--   additive only (never updates/deletes) · amounts must be >= 0 with at most 2 decimals.
-- NOT callable from the app: execute is revoked from everyone but the database owner.
-- PRODUCTION USE is its own approved step (see docs); never bundled with a deploy.
-- ============================================================
create or replace function import_legacy_money(p_season_id uuid, p_rows jsonb)
returns table (cash_rows_added integer, credit_rows_added integer, cash_total numeric, credit_total numeric)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  r jsonb; v_lp text; v_ps uuid; v_money numeric; v_credit numeric; v_ref uuid;
  v_cash_added integer := 0; v_credit_added integer := 0; v_cash_sum numeric := 0; v_credit_sum numeric := 0; v_n integer;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'p_rows must be a JSON array'; end if;
  perform pg_advisory_xact_lock(hashtext('import_legacy_money'));
  for r in select * from jsonb_array_elements(p_rows) loop
    v_lp := r->>'legacy_player_id';
    v_money := coalesce((r->>'money_in')::numeric, 0);
    v_credit := coalesce((r->>'credit_earned')::numeric, 0);
    if v_lp is null then raise exception 'Row without legacy_player_id'; end if;
    if v_money < 0 or v_credit < 0 then raise exception 'Negative amount for legacy player %', v_lp; end if;
    if v_money <> round(v_money, 2) or v_credit <> round(v_credit, 2) then raise exception 'More than 2 decimals for legacy player %', v_lp; end if;

    select ps.id into v_ps from player_season ps join player p on p.id = ps.player_id
      where p.legacy_player_id = v_lp and ps.season_id = p_season_id;
    if v_ps is null then raise exception 'No registration in this season for legacy player % (nothing was imported)', v_lp; end if;

    if v_money > 0 then
      insert into fundraising_cash_ledger (player_season_id, amount, note, idempotency_key)
        values (v_ps, v_money, 'Imported from legacy fundraiser system', 'legacy:' || v_lp || ':cash')
        on conflict (idempotency_key) where idempotency_key is not null do nothing;
      get diagnostics v_n = row_count; v_cash_added := v_cash_added + v_n;
    end if;
    if v_credit > 0 then
      v_ref := md5('legacy-credit:' || v_lp)::uuid;
      if not exists (select 1 from fundraising_credit_ledger where source = 'product_sale' and source_reference_id = v_ref) then
        insert into fundraising_credit_ledger (player_season_id, source, source_reference_id, amount)
          values (v_ps, 'product_sale', v_ref, v_credit);
        v_credit_added := v_credit_added + 1;
      end if;
    end if;
  end loop;
  select coalesce(sum(amount),0) into v_cash_sum from fundraising_cash_ledger where idempotency_key like 'legacy:%';
  select coalesce(sum(amount),0) into v_credit_sum from fundraising_credit_ledger where source = 'product_sale' and source_reference_id is not null;
  return query select v_cash_added, v_credit_added, v_cash_sum, v_credit_sum;
end $$;

revoke execute on function import_legacy_money(uuid, jsonb) from public, anon, authenticated;
