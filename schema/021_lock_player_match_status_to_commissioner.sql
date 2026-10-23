-- 021_lock_player_match_status_to_commissioner.sql
-- GOVERNANCE gap: RLS is row-level, so player_family_update let a guardian write player.match_status.
-- Fix: BEFORE UPDATE trigger reverts match_status changes by non-Commissioners.

create or replace function enforce_player_match_status_commissioner_only()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.match_status is distinct from old.match_status and not auth_is_commissioner() then
    new.match_status := old.match_status;
  end if;
  return new;
end;
$$;

comment on function enforce_player_match_status_commissioner_only is
  'Closes a GOVERNANCE gap found in staging QA (schema/021): RLS is row-level, so player_family_update (schema/011) could not stop a family from writing match_status alongside their own permitted edits. This trigger reverts any match_status change made by a non-Commissioner writer, independent of RLS.';

create trigger trg_player_match_status_guard
before update on player
for each row execute function enforce_player_match_status_commissioner_only();
