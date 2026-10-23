alter policy fundraising_credit_scoped on fundraising_credit_ledger
  using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or player_season_id in (select id from player_season where team_id in (select auth_team_ids()))
    or family_id in (select auth_family_ids())
    or auth_is_commissioner()
  );
