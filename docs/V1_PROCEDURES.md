# V1 manual procedures (Minerva-run, staging first)

## 1. Add a household (Commissioner — in the app)
Admin → Households → fill in name, guardian name, **guardian email** → Create. When the guardian signs in with that
email (magic link) the account links itself. Unknown / duplicate / unverified / shared-by-two-households emails never link.

## 2. Give someone Team Parent / Coach / Commissioner access (Minerva — SQL, after the person has signed in once)
```sql
insert into app_role (auth_user_id, role, team_id)
select id, 'team_parent', '<TEAM_UUID>' from auth.users where lower(email) = lower('person@example.com');
-- roles: team_parent | coach (need team_id) · commissioner (team_id null)
```
Parked for V2: in-app role-assignment admin.

## 3. Build the schedule (Minerva — SQL; V1 has no template/job-role editor)
```sql
-- a game
insert into game_event (season_id, team_id, event_type, opponent, location, starts_at)
values ('<SEASON>', '<TEAM>', 'home_game', 'Hawks', 'Fremont HS Field', '2026-11-07 17:00-08');
-- jobs for that game (job_role_config rows already exist for the season: Gate, Snack Bar, Chain Gang…)
insert into job_instance (game_event_id, job_role_config_id, volunteers_needed)
select '<GAME>', id, 2 from job_role_config where season_id = '<SEASON>' and role_name = 'Gate';
```
Parked for V2: Admin job-role editor, Standard Home Game template editor.

## 4. Season settings
Admin → Season Config saves a NEW config version (append-only). `share_credit_board_approved` is deliberately NOT in the
UI: set it by SQL only after the board approves the $1 share credit.
```sql
insert into season_config (season_id, hours_per_child, minutes_per_child, fundraising_goal_per_child, replacement_fee_amount,
  no_show_fee_amount, no_show_grace_period_days, share_credit_amount, share_credit_board_approved)
values ('<SEASON>', 3, 180, 200, 25, 50, 5, 1, false);   -- true only with written board approval
```

## 5. Season lifecycle
Admin → Seasons buttons: Open Registration → Make Active → Close Season. Only one season can be open/active; closing is
refused while any registration is not Season Ready/Withdrawn/Refunded, any no-show fee is unresolved, or any job is unresolved.

## 6. Legacy money import (production = separate approved step)
`schema/999b_legacy_money_import.sql` — all-or-nothing, idempotent, owner-only. Tested with non-zero amounts (see QA).
