alter table public.player_season add column if not exists participation_status text not null default 'active' check (participation_status in ('active','declined','flagged'));
create index if not exists idx_player_season_incoming_division on public.player_season(season_id, requested_program, requested_division, participation_status);
