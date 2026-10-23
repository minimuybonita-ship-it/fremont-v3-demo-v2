alter table uniform_order enable row level security;
alter table uniform_history enable row level security;
alter table acknowledgment enable row level security;

create policy player_family_write on player
  for insert with check (family_id in (select auth_family_ids()));
create policy player_family_update on player
  for update using (family_id in (select auth_family_ids()) or auth_is_commissioner());

create policy player_season_family_write on player_season
  for insert with check (
    player_id in (select id from player where family_id in (select auth_family_ids()))
  );
create policy player_season_family_update on player_season
  for update using (
    player_id in (select id from player where family_id in (select auth_family_ids()))
    and registration_stage in ('draft', 'submitted', 'correction_needed')
  );
create policy player_season_staff_update on player_season
  for update using (auth_is_commissioner());

create policy uniform_order_family_write on uniform_order
  for insert with check (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
  );
create policy uniform_order_family_update on uniform_order
  for update using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or auth_is_commissioner()
  );
create policy uniform_history_insert on uniform_history
  for insert with check (
    uniform_order_id in (
      select uo.id from uniform_order uo
      join player_season ps on ps.id = uo.player_season_id
      join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or auth_is_commissioner()
  );
create policy uniform_history_read on uniform_history
  for select using (
    uniform_order_id in (
      select uo.id from uniform_order uo
      join player_season ps on ps.id = uo.player_season_id
      join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or auth_is_commissioner()
  );

create policy acknowledgment_family_read on acknowledgment
  for select using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or auth_is_commissioner()
  );
create policy acknowledgment_family_update on acknowledgment
  for update using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
  );
create policy acknowledgment_insert on acknowledgment
  for insert with check (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or auth_is_commissioner()
  );
