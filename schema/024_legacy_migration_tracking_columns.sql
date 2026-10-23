alter table family add column if not exists legacy_family_label text;
alter table player add column if not exists legacy_player_id text unique;
alter table team add column if not exists legacy_team_id text unique;
