# Event / Memory Workflow — Current Scope

For V3, this covers **organization events** (potlucks, Homecoming, league events) via `org_event` / `event_signup_item` — sign-up categories, reminders, team vs. league distinction.

**Explicitly out of scope for this pass** (Season Memory Engine, future/premium): game video capture, approved-photo collection, Player Season Vault, Individual Season Book. Nothing here should be built to simulate those yet — see Master Architecture Record section I.

## Current-scope checklist
- [ ] Event created with correct type (season_kickoff_potluck / season_closing_celebration / league_event / homecoming / custom_team_event / custom_league_event)
- [ ] Sign-up categories defined (mains, sides, desserts, setup, cleanup, etc.)
- [ ] Reminders scheduled
- [ ] Team-level vs. league-level visibility confirmed correct
