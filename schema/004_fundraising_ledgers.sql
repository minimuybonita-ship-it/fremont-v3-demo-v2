-- ============================================================
-- 004_fundraising_ledgers.sql
-- Three ledgers, kept structurally separate per founder rule:
-- volunteer hours (see 003) / actual cash / fundraising credit.
-- Preserves the existing fundraiser math (box sales) as the
-- Fundraising Engine's first campaign type, migrated not rebuilt.
-- ============================================================

create table if not exists fundraising_campaign (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references season(id) on delete cascade,
  name text not null,                  -- "World's Finest Chocolate"
  emoji text,
  campaign_type text not null default 'product_sale'
    check (campaign_type in ('product_sale', 'direct_donation', 'social_share', 'book_purchase')),
  unit_cost numeric,                   -- boxCost equivalent
  credit_per_unit numeric,             -- creditPerBox equivalent
  starting_units integer default 0,    -- startingBoxes equivalent
  ends_on date,
  active boolean not null default true
);

-- Actual cash received. Never merged with credit.
create table if not exists fundraising_cash_ledger (
  id uuid primary key default gen_random_uuid(),
  player_season_id uuid not null references player_season(id) on delete cascade,
  campaign_id uuid references fundraising_campaign(id),
  amount numeric not null,
  recorded_by uuid references auth.users(id), -- Team Parent/Commissioner who entered it
  recorded_at timestamptz not null default now(),
  note text
);

-- Fundraising credit — never cash, never volunteer hours. Sources:
-- product sale credit, $25 replacement credit (post-verification only),
-- $1 share credit (post-approval only, board-gated), future POD credit.
create table if not exists fundraising_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  player_season_id uuid not null references player_season(id) on delete cascade,
  source text not null
    check (source in ('product_sale', 'replacement_pool', 'social_share', 'admin_adjustment', 'book_purchase')),
  source_reference_id uuid,            -- points at replacement_pool_entry.id / social_share_submission.id / etc.
  amount numeric not null,
  credited_at timestamptz not null default now(),
  credited_by uuid references auth.users(id)
);

-- $1 verified social-share workflow. Board-approval gated via
-- season_config.share_credit_board_approved — this table can exist
-- and collect submissions even while the gate is off; nothing pays
-- out until both (a) approved per-submission and (b) the board gate is on.
create table if not exists social_share_submission (
  id uuid primary key default gen_random_uuid(),
  player_season_id uuid not null references player_season(id) on delete cascade,
  campaign_id uuid references fundraising_campaign(id),
  proof_url text not null,             -- screenshot/link, required — pressing Share alone never creates credit
  proof_hash text,                     -- for duplicate-proof detection
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  credit_amount numeric                -- snapshot of season_config.share_credit_amount at submission time
);

create unique index if not exists idx_share_submission_dedupe
  on social_share_submission(player_season_id, proof_hash)
  where proof_hash is not null;

create index if not exists idx_cash_ledger_player_season on fundraising_cash_ledger(player_season_id);
create index if not exists idx_credit_ledger_player_season on fundraising_credit_ledger(player_season_id);

comment on table fundraising_credit_ledger is 'Fundraising credit only. Never write volunteer hours or raw cash here — those stay in 003/above.';
comment on column social_share_submission.credit_amount is 'Snapshotted at submission so a later season_config change does not retroactively alter a pending or approved submission.';
