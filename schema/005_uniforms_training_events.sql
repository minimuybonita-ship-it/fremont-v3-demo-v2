-- ============================================================
-- 005_uniforms_training_events.sql
-- Uniforms (history preserved, never erased on reorder),
-- training/SOP library, events/calendar.
-- ============================================================

create table if not exists uniform_order (
  id uuid primary key default gen_random_uuid(),
  player_season_id uuid not null references player_season(id) on delete cascade,
  jersey_size text,
  pant_size text,
  other_items jsonb default '{}'::jsonb,
  order_status text not null default 'pending'
    check (order_status in ('pending', 'ordered', 'confirmed', 'delivered')),
  payment_status text default 'n/a',
  prior_year_jersey_size text,          -- surfaced to returning players, per V3 §16
  created_at timestamptz not null default now()
);

-- Append-only. A reorder/replacement never deletes a prior row.
create table if not exists uniform_history (
  id uuid primary key default gen_random_uuid(),
  uniform_order_id uuid not null references uniform_order(id) on delete cascade,
  change_type text not null check (change_type in ('initial', 'reorder', 'replacement', 'size_correction')),
  changed_at timestamptz not null default now(),
  changed_by uuid references auth.users(id),
  note text
);

create table if not exists training_resource (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  title text not null,                  -- "Gate 101", "Snack Bar 101"
  applies_to_role text,                 -- matches job_role_config.role_name where applicable
  video_url text,
  one_page_guide_url text,
  checklist jsonb default '[]'::jsonb,
  contact_name text,
  contact_info text,
  status text not null default 'ffl_to_confirm' check (status in ('ready', 'ffl_to_confirm')),
  notes text
);

alter table job_role_config
  add constraint fk_job_role_training
  foreign key (training_resource_id) references training_resource(id);

create table if not exists org_event (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  team_id uuid references team(id),     -- null = league-wide
  event_type text not null
    check (event_type in ('season_kickoff_potluck', 'season_closing_celebration', 'league_event',
                           'homecoming', 'custom_team_event', 'custom_league_event')),
  title text not null,
  starts_at timestamptz,
  location text
);

create table if not exists event_signup_item (
  id uuid primary key default gen_random_uuid(),
  org_event_id uuid not null references org_event(id) on delete cascade,
  category text not null,               -- mains, sides, desserts, setup, cleanup, etc.
  description text,
  quantity_needed integer default 1,
  claimed_by_family_id uuid references family(id)
);

create index if not exists idx_uniform_order_player_season on uniform_order(player_season_id);
