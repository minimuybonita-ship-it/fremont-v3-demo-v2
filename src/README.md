# Fremont V3 — Controlled Working Version

**This code is not wired to production.** `lib/supabaseClient.js` requires
real staging credentials before anything here can read or write data —
until those are set, it logs a loud console warning rather than silently
doing nothing.

## What's implemented in this pass

- `lib/supabaseClient.js`, `lib/auth.js` — magic-link auth, no passwords
- `components/AuthGate.jsx` — replaces the old shared-PIN model entirely
- `components/shared.jsx` — the original app's UI primitives, reused verbatim (not rebuilt)
- `components/FamilyDashboard.jsx` — "what do I need to do next," aggregated correctly across siblings
- `components/CommissionerCockpit.jsx` — exceptions-first operational view
- `lib/volunteerEngine.js` — the assignment state machine + $25 replacement claim/verify logic, isolated from UI per the agreed "build and test in isolation" order

## What's intentionally NOT finished in this pass

See `../docs/BUILD_STATUS_MATRIX.md` for the full list. The two most
load-bearing gaps, flagged directly in code comments where they occur:

1. `families_owing_hours()` — a Postgres RPC that `volunteerEngine.js`
   calls but which does not exist yet. Phase B auto-assignment cannot
   run correctly without it. **NEEDS FOUNDER/DEV DECISION:** the exact
   join between `player_season`, `season_config.hours_per_child`, and
   completed `assignment` rows, including how partial-hour jobs round.
2. `verifyReplacementCompletion()` resolves the wrong id when crediting
   (`claimed_by_family_id` used where a `player_season_id` is required) —
   left visible rather than quietly patched with a guess, since which
   child in a multi-child family receives the credit is a real policy
   question, not a technical one.

## Not built at all (parked, per approved scope)

Backup Marketplace, ranked offer sequencing, offer timeouts, Above & Beyond
as a named program, Health/Safety module, Season Memory Engine, POD/Awards
QR flow. Schema does not preclude adding these later.

## Integration with the existing app

`App.jsx` for the existing fundraiser (box-sale tracking, Team Parent/
Commissioner CSV export, Excel roster upload) is **not replaced** in this
pass — those pieces work and were explicitly preserved per the audit.
The next integration step is wiring the existing fundraiser UI to read
from `fundraising_campaign` / `fundraising_cash_ledger` /
`fundraising_credit_ledger` instead of the `app_state` blob, once the
migration in `schema/999_migration_from_app_state.sql` has been run
against staging and reviewed.
