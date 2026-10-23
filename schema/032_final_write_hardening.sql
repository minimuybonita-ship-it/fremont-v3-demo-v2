-- ============================================================
-- 032_final_write_hardening.sql  (found while auditing every remaining non-Commissioner write policy)
--  1. game_event: team staff could INSERT/UPDATE game events for their team, including starts_at / closed_at.
--     The business functions (check-in, no-show, replacement completion, claim) trust starts_at, so schedule
--     changes are Commissioner-only. Team staff still run Game Day through the 029 functions and incident log.
--  2. uniform_order: a family may create/edit sizes, but not set order_status / payment_status
--     (official payment happens with the league; these are Commissioner-maintained).
--  3. season: a new season always starts as 'planning' when created by a signed-in user; opening goes through
--     set_season_status() so the "only one open/active season" rule cannot be bypassed by a direct INSERT.
-- ============================================================
alter policy game_event_staff_write on game_event using (auth_is_commissioner()) with check (auth_is_commissioner());

create or replace function _uniform_order_write_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or auth_is_commissioner() then return new; end if;
  if tg_op = 'INSERT' then
    new.order_status := 'pending';
    new.payment_status := 'n/a';
  else
    new.player_season_id := old.player_season_id;
    new.order_status := old.order_status;
    new.payment_status := old.payment_status;
  end if;
  return new;
end $$;
create trigger trg_uniform_order_write_guard before insert or update on uniform_order
  for each row execute function _uniform_order_write_guard();

create or replace function _season_insert_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is not null then new.status := 'planning'; end if;
  return new;
end $$;
create trigger trg_season_insert_guard before insert on season for each row execute function _season_insert_guard();

revoke execute on function _uniform_order_write_guard(), _season_insert_guard() from public, anon, authenticated;
