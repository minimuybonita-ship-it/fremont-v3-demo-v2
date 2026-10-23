-- ============================================================
-- 003_volunteer_engine.sql
-- Volunteer Operations Engine — hybrid selection/auto-assign,
-- full lifecycle, audit log, simplified $25 replacement pool,
-- $50 no-show fee. Ranked offers/timeouts/Backup Marketplace
-- are explicitly NOT built here — see note at bottom.
-- ============================================================

-- Reusable role rules matrix. Each organization job gets one row.
create table if not exists job_role_config (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  role_name text not null,                    -- "Gate", "Snack Bar", "Chain Gang", "MPR"...
  category text not null default 'organization'
    check (category in ('organization', 'team_duty')),
  earns_organization_volunteer_credit boolean not null default true, -- the configurable flag V3 §7 requires
  credited_hours numeric not null default 2,
  volunteers_needed_default integer not null default 1,
  background_check_required boolean not null default false,
  training_required boolean not null default false,
  training_resource_id uuid,                  -- fk added in 005 once training_resource exists
  arrival_offset_minutes integer default 30,  -- "30 minutes before kickoff"
  replacement_allowed boolean not null default true,
  verifier_role text not null default 'team_parent'
    check (verifier_role in ('team_parent', 'coach', 'commissioner')),
  instructions text,
  created_at timestamptz not null default now()
);

-- Reusable Standard Home Game template: a named set of job_role_config rows + counts.
create table if not exists job_template (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  name text not null default 'Standard Home Game'
);

create table if not exists job_template_item (
  id uuid primary key default gen_random_uuid(),
  job_template_id uuid not null references job_template(id) on delete cascade,
  job_role_config_id uuid not null references job_role_config(id),
  volunteers_needed integer not null default 1
);

-- One real event/game that jobs get staffed for.
create table if not exists game_event (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  team_id uuid references team(id),           -- null = league-wide event
  event_type text not null default 'home_game'
    check (event_type in ('home_game', 'homecoming', 'practice', 'league_event', 'team_event')),
  opponent text,
  starts_at timestamptz,
  location text,
  job_template_id uuid references job_template(id), -- inherits from template; can still be overridden per job_instance
  notes text
);

-- A specific staffing slot for a specific event. Created from the
-- template, then independently editable per game (per V3 §8).
create table if not exists job_instance (
  id uuid primary key default gen_random_uuid(),
  game_event_id uuid not null references game_event(id) on delete cascade,
  job_role_config_id uuid not null references job_role_config(id),
  volunteers_needed integer not null default 1,
  starts_at timestamptz,
  ends_at timestamptz
);

-- The assignment lifecycle. One row per family-to-slot pairing.
create table if not exists assignment (
  id uuid primary key default gen_random_uuid(),
  job_instance_id uuid not null references job_instance(id) on delete cascade,
  family_id uuid not null references family(id),
  status text not null default 'open'
    check (status in (
      'open', 'claimed', 'confirmed', 'scheduled', 'checked_in', 'completed', 'verified', 'credited',
      'swap_requested', 'replacement_requested', 'cancelled', 'no_show', 'excused', 'exempt', 'needs_review'
    )),
  claimed_via text not null default 'family_selection'
    check (claimed_via in ('family_selection', 'auto_assigned')), -- Phase A vs Phase B, per V3 §2
  checked_in_at timestamptz,
  completed_at timestamptz,
  verified_at timestamptz,
  verified_by_guardian_id uuid references guardian(id), -- null if verified by coach/commissioner instead
  verified_by_role text check (verified_by_role in ('team_parent', 'coach', 'commissioner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists assignment_audit_log (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignment(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  note text
);

-- Swap: original assignment stays ACTIVE until the receiving family accepts.
create table if not exists swap_request (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignment(id) on delete cascade,
  requested_by_family_id uuid not null references family(id),
  offered_to_family_id uuid references family(id), -- null = open to any eligible family
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- SIMPLIFIED $25 replacement pool (V3-locked scope):
-- no ranked offers, no sequencing, no timeouts. First valid claim locks it.
-- The unique constraint on assignment_id where status='open' is what
-- prevents the double-claim race condition from the QA plan.
create table if not exists replacement_pool_entry (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignment(id) on delete cascade,
  released_by_family_id uuid not null references family(id),
  fee_amount numeric not null,              -- snapshot of season_config.replacement_fee_amount at release time
  payment_status text not null default 'pending'
    check (payment_status in ('pending', 'paid', 'refunded')),
  status text not null default 'open'
    check (status in ('open', 'claimed', 'completed', 'verified', 'credited', 'cancelled')),
  claimed_by_family_id uuid references family(id),
  claimed_at timestamptz,
  verified_at timestamptz,
  credit_issued boolean not null default false, -- fires ONLY on verified completion, never on claim
  created_at timestamptz not null default now()
);

-- Enforces "first valid claim locks it" at the database level, not just in the UI.
create unique index if not exists idx_one_open_claim_per_assignment
  on replacement_pool_entry(assignment_id)
  where status = 'open';

-- $50 no-show fee. Amount is a snapshot from season_config, not a hardcoded constant.
create table if not exists no_show_record (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignment(id) on delete cascade,
  family_id uuid not null references family(id),
  fee_amount numeric not null,              -- snapshot of season_config.no_show_fee_amount
  notice_issued_at timestamptz not null default now(),
  pay_by_date date not null,                -- notice_issued_at + season_config.no_show_grace_period_days
  resolution_status text not null default 'pending'
    check (resolution_status in ('pending', 'paid', 'posted_to_org_process', 'waived')),
  resolved_at timestamptz
);

create index if not exists idx_assignment_family on assignment(family_id);
create index if not exists idx_assignment_job_instance on assignment(job_instance_id);
create index if not exists idx_replacement_pool_status on replacement_pool_entry(status);

-- ------------------------------------------------------------
-- PARKED, NOT BUILT HERE (per approved scope lock):
--   - ranked offer sequencing / offer timeouts
--   - expanded "Backup Marketplace" opt-in/eligibility module
--   - named "Above & Beyond" program (completed-hours-past-zero
--     is simply queryable from `assignment` + `job_instance`
--     credited_hours — no separate table needed for that).
-- ------------------------------------------------------------
