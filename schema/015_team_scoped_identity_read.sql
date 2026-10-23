create policy family_team_scoped_read on family
  for select using (
    id in (
      select p.family_id from player p
      join player_season ps on ps.player_id = p.id
      where ps.team_id in (select auth_team_ids())
    )
  );

create policy player_team_scoped_read on player
  for select using (
    id in (
      select ps.player_id from player_season ps
      where ps.team_id in (select auth_team_ids())
    )
  );

comment on policy family_team_scoped_read on family is
  'Limited field exposure is enforced at the query layer, not by RLS column masking — RLS here controls ROW visibility.';
