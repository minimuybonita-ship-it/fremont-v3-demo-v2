-- ============================================================
-- 002_season_and_teams.sql
-- Seasons, teams, and the season-scoped player record.
-- season_config is VERSIONED and SNAPSHOTTED onto each player_season
-- record at registration time, so a later admin rate change never
-- silently rewrites a family's historical obligation.
-- ============================================================

create table if not exists season (
  id uuid primary key default gen_random_uuid(),
  org_name text not null default 'Fremont Football & Cheer',
  name text not null,                -- e.g. "2026 Fall Season"
  starts_on date,
  ends_on date,
  status text not null default 'planning'
    check (status in ('planning', 'registration_open', 'active', 'closed')),
  created_at timestamptz not null default now()
);

-- Admin-configurable policy values for a season. New row per change —
-- never UPDATE this table's values in place once a season is active.
create table if not exists season_config (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  hours_per_child numeric not null default 3,          -- LOCKED default per founder decision
  fundraising_goal_per_child numeric not null default 200,
  replacement_fee_amount numeric not null default 25,
  no_show_fee_amount numeric not null default 50,       -- Fremont current policy; CONFIGURABLE at Core level
  no_show_grace_period_days integer not null default 5,
  share_credit_amount numeric not null default 1,
  share_credit_board_approved boolean not null default false, -- gate stays OFF until board adopts it
  effective_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  note text
);

create table if not exists division (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  name text not null,                -- e.g. "10U Football", "Cheer"
  sport text not null default 'football'
);

create table if not exists team (
  id uuid primary key default gen_random_uuid(),
  division_id uuid not null references division(id) on delete cascade,
  name text not null
);

-- The season-scoped player record. One `player` can have many of these
-- across years; this is what "do not recreate the person every season" means.
create table if not exists player_season (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references player(id) on delete cascade,
  season_id uuid not null references season(id) on delete cascade,
  team_id uuid references team(id),
  season_config_id uuid not null references season_config(id), -- snapshot pin, not a live FK to "current" config
  registration_status text not null default 'pending'
    check (registration_status in ('pending', 'season_ready', 'withdrawn')),
  season_ready_at timestamptz,
  jersey_number text,
  created_at timestamptz not null default now(),
  unique (player_id, season_id)
);

-- Acknowledgments/training completion gating Season Ready status.
create table if not exists acknowledgment (
  id uuid primary key default gen_random_uuid(),
  player_season_id uuid not null references player_season(id) on delete cascade,
  acknowledgment_type text not null, -- e.g. 'code_of_conduct', 'volunteer_agreement', 'concussion_info'
  completed_at timestamptz,
  completed_by_guardian_id uuid references guardian(id)
);

create index if not exists idx_player_season_season on player_season(season_id);
create index if not exists idx_player_season_player on player_season(player_id);

comment on table season_config is 'Append-only. A new row = a new effective config; player_season snapshots the row id that applied at registration.';
comment on column player_season.season_config_id is 'Pinned at registration. Changing season_config later does NOT change this value — this is what prevents retroactive obligation rewrites.';
