-- ============================================================
-- 006_auth_and_rls.sql
-- Real auth + family-level privacy, replacing shared/hardcoded PINs.
--
-- MODEL: Supabase Auth (email magic link — no passwords to manage,
-- works for parents who will never remember a league-specific password).
-- Role claims live in app_role, resolved per request via RLS, not
-- trusted from client-sent values.
-- ============================================================

create table if not exists app_role (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('guardian', 'team_parent', 'coach', 'commissioner')),
  family_id uuid references family(id),   -- set when role = 'guardian'
  team_id uuid references team(id),       -- set when role = 'team_parent' or 'coach'
  season_id uuid references season(id),
  unique (auth_user_id, role, family_id, team_id, season_id)
);

create or replace function auth_family_ids()
returns setof uuid
language sql stable
as $$
  select family_id from app_role
  where auth_user_id = auth.uid() and role = 'guardian' and family_id is not null
$$;

create or replace function auth_team_ids()
returns setof uuid
language sql stable
as $$
  select team_id from app_role
  where auth_user_id = auth.uid() and role in ('team_parent', 'coach') and team_id is not null
$$;

create or replace function auth_is_commissioner()
returns boolean
language sql stable
as $$
  select exists (
    select 1 from app_role where auth_user_id = auth.uid() and role = 'commissioner'
  )
$$;

alter table family enable row level security;
alter table guardian enable row level security;
alter table player enable row level security;
alter table player_season enable row level security;
alter table assignment enable row level security;
alter table replacement_pool_entry enable row level security;
alter table fundraising_cash_ledger enable row level security;
alter table fundraising_credit_ledger enable row level security;
alter table uniform_order enable row level security;

-- A family sees only its own family/guardian/player records.
create policy family_self_access on family
  for select using (id in (select auth_family_ids()) or auth_is_commissioner());

create policy guardian_self_access on guardian
  for select using (family_id in (select auth_family_ids()) or auth_is_commissioner());

create policy player_self_access on player
  for select using (family_id in (select auth_family_ids()) or auth_is_commissioner());

-- Team parents/coaches see player_season rows for their team; families see their own.
create policy player_season_scoped_access on player_season
  for select using (
    player_id in (select id from player where family_id in (select auth_family_ids()))
    or team_id in (select auth_team_ids())
    or auth_is_commissioner()
  );

create policy assignment_scoped_access on assignment
  for select using (
    family_id in (select auth_family_ids())
    or job_instance_id in (
      select ji.id from job_instance ji
      join game_event ge on ge.id = ji.game_event_id
      where ge.team_id in (select auth_team_ids())
    )
    or auth_is_commissioner()
  );

create policy replacement_pool_read on replacement_pool_entry
  for select using (true); -- open pool must be visible to all eligible families to claim

create policy fundraising_cash_scoped on fundraising_cash_ledger
  for select using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or player_season_id in (select id from player_season where team_id in (select auth_team_ids()))
    or auth_is_commissioner()
  );

create policy fundraising_credit_scoped on fundraising_credit_ledger
  for select using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or player_season_id in (select id from player_season where team_id in (select auth_team_ids()))
    or auth_is_commissioner()
  );

create policy uniform_order_scoped on uniform_order
  for select using (
    player_season_id in (
      select ps.id from player_season ps join player p on p.id = ps.player_id
      where p.family_id in (select auth_family_ids())
    )
    or player_season_id in (select id from player_season where team_id in (select auth_team_ids()))
    or auth_is_commissioner()
  );

-- Write policies: a family may only write its OWN requests/acknowledgments.
-- Approvals/verifications (job_role_config, assignment status transitions
-- past "claimed", credit issuance) require team_parent/coach/commissioner —
-- enforced at the application layer AND mirrored here as a second gate.
create policy assignment_family_claim on assignment
  for update using (
    family_id in (select auth_family_ids()) and status in ('open', 'claimed')
  );

create policy assignment_staff_manage on assignment
  for update using (
    auth_is_commissioner()
    or job_instance_id in (
      select ji.id from job_instance ji join game_event ge on ge.id = ji.game_event_id
      where ge.team_id in (select auth_team_ids())
    )
  );

comment on function auth_is_commissioner is 'Role check is server-side via RLS, never trusted from a client-sent flag — this directly closes the open Family-view privacy gap found in the source audit.';
