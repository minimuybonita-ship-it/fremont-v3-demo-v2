create or replace function scan_for_possible_duplicate_players(p_season_id uuid)
returns integer
language plpgsql
as $$
declare
  v_flagged integer := 0;
begin
  with candidates as (
    select p.id
    from player p
    join player_season ps on ps.player_id = p.id and ps.season_id = p_season_id
    where p.match_status = 'unmatched'
      and exists (
        select 1 from player p2
        join player_season ps2 on ps2.player_id = p2.id and ps2.season_id = p_season_id
        where p2.id <> p.id
          and p2.family_id <> p.family_id
          and lower(trim(p2.full_name)) = lower(trim(p.full_name))
      )
  )
  update player set match_status = 'possible_match'
  where id in (select id from candidates);
  get diagnostics v_flagged = row_count;
  return v_flagged;
end;
$$;

comment on function scan_for_possible_duplicate_players is
  'Explicit, human-triggered scan only. Writes ONLY the possible_match state; every other state transition is a human decision, never automatic.';

create policy family_commissioner_identity_update on family
  for update using (auth_is_commissioner());
