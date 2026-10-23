-- ============================================================
-- 001_core_identity.sql
-- FREMONT V3 — CORE IDENTITY LAYER
-- Sports/League Operations Core — reusable across Products 1–3
--
-- STATUS: NOT YET APPLIED TO ANY PROJECT. Review before running.
-- Safe to run against a NEW/empty schema (a branch or staging project).
-- Do NOT run against the live Fremont production project without a
-- separate, explicit go-ahead — see docs/DEPLOYMENT_MIGRATION_ROLLBACK.md.
-- ============================================================

create extension if not exists "pgcrypto";

-- One family identity persists across seasons.
create table if not exists family (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,            -- e.g. "Llamas Family" — never used for access control
  created_at timestamptz not null default now(),
  -- Duplicate-detection support. Never auto-merged — see 999_data_migration note.
  duplicate_of uuid references family(id),
  duplicate_review_status text not null default 'none'
    check (duplicate_review_status in ('none', 'flagged', 'reviewed_distinct', 'merged'))
);

-- Guardian 2 is explicitly optional (no NOT NULL constraint forces a second guardian).
create table if not exists guardian (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references family(id) on delete cascade,
  auth_user_id uuid references auth.users(id), -- links to Supabase Auth identity once real auth exists
  full_name text not null,
  email text,
  phone text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);

-- One player identity persists across seasons (not recreated each year).
create table if not exists player (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references family(id) on delete cascade,
  full_name text not null,
  date_of_birth date,
  emergency_contact_name text,
  emergency_contact_phone text,
  created_at timestamptz not null default now(),
  duplicate_of uuid references player(id),
  duplicate_review_status text not null default 'none'
    check (duplicate_review_status in ('none', 'flagged', 'reviewed_distinct', 'merged'))
);

create index if not exists idx_guardian_family on guardian(family_id);
create index if not exists idx_player_family on player(family_id);

comment on table family is 'Household identity. Volunteer/fundraising obligations attach here, not to individual guardians.';
comment on column guardian.is_primary is 'UI convenience only — Guardian 2 presence/absence never changes any calculation.';
comment on column family.duplicate_review_status is 'Per V3 §25: duplicates are flagged for human review, never auto-merged.';
