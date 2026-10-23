-- 019_fix_rls_recursion_team_scoped.sql
-- BLOCKER found during staging QA: team-scoped read policies (015) cross-reference player_season,
-- whose own policy cross-references player -> circular RLS evaluation ("infinite recursion detected
-- in policy for relation player"). Fix: compute team-scoped player/family ids via SECURITY DEFINER
-- helpers. No change to WHO can see WHAT; only the evaluation path changes.

create or replace function auth_team_scoped_player_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select ps.player_id from player_season ps where ps.team_id in (select auth_team_ids())
$$;

create or replace function auth_team_scoped_family_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select p.family_id from player p
  join player_season ps on ps.player_id = p.id
  where ps.team_id in (select auth_team_ids())
$$;

comment on function auth_team_scoped_player_ids is
  'SECURITY DEFINER to break the RLS recursion cycle found in staging QA between family/player/player_season (schema/019). Computes the same result a correlated subquery would, but bypasses RLS internally so the lookup is non-recursive.';
comment on function auth_team_scoped_family_ids is
  'See auth_team_scoped_player_ids. Used by family_team_scoped_read.';

alter policy family_team_scoped_read on family
  using (id in (select auth_team_scoped_family_ids()));

alter policy player_team_scoped_read on player
  using (id in (select auth_team_scoped_player_ids()));
-- NOTE: the applied migration's long explanatory header comment is abbreviated here; the SQL statements are identical.
