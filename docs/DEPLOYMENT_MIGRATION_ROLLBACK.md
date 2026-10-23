# Deployment / Migration / Rollback Plan
**Sequence: BACKUP → DEPLOY → MIGRATE → VERIFY → CUTOVER → QA.** Nothing in this document has been executed against production. Every step below is written as what to do, not a record of what was done.

## Step 0 — Already done, do not repeat
- [x] Point-in-time backup of production `app_state` taken and delivered (`app_state_backup_2026-10-05T1526Z.json`) — **do not discard**
- [x] Gate 0 code fix written and delivered (`LeagueFundraiserCommandCenter_GATE0FIX.jsx`) — **not yet deployed**

## Step 1 — Gate 0 production verification (small, do this first, independent of everything else below)
1. Deploy `LeagueFundraiserCommandCenter_GATE0FIX.jsx` to Vercel in place of the current source
2. Reload the app on the original device — confirm the sync badge never reads "Synced ✓" on an empty key, and correctly shows "Synced ✓" once real data loads
3. Reload on a second device — confirm the same player data (Alex, Ben, John, Jenny, Miike) still appears
4. Report both back — only then is Gate 0 formally CLOSED in the Master Architecture record

## Step 2 — Stand up a staging Supabase project
1. Create a **new** Supabase project (not the production one, `qgbmeztjqxfhkhhojiyh`) — call it `fremont-v3-staging`
2. Run `schema/001` through `schema/006` against staging, in order
3. Confirm `get_advisors` (security) comes back clean on staging before proceeding

## Step 3 — Migrate a COPY of production data into staging
1. Export the current production `app_state` rows (same method used for the backup file)
2. Import that export into staging's `app_state` table (staging only — never write this into production again)
3. Run the reference logic in `schema/999_migration_from_app_state.sql`, filled in with a real `season_id`/`season_config_id`, against **staging**
4. Review every row where `duplicate_review_status = 'flagged'` — this is a human review step, not automatable
5. Spot-check that sold/moneyIn/creditEarned values migrated bit-for-bit against the original backup file

## Step 4 — Verify staging end-to-end
Run the full QA checklist (`QA_CHECKLIST.md`) against staging. Do not proceed to Step 5 until it passes.

## Step 5 — Cutover (production)
This is the only step that touches live production data, and it happens **once**, deliberately:
1. Freeze writes to production `app_state` (put the live app briefly in a read-only/maintenance state, or pick a low-traffic window)
2. Take a **second** fresh backup of production `app_state` immediately before migrating (data may have changed since the first backup)
3. Run the reviewed, founder-approved version of the Step 3 migration against production
4. Point the production app's `supabaseClient.js` at the new schema/tables
5. Verify Step 1-style cross-device checks again, now against the new schema
6. Keep the old `app_state` table **in place, untouched**, for at least one full review cycle — it is the rollback path (Step 6), not something to drop immediately

## Step 6 — Rollback plan (if Step 5 goes wrong)
1. Point `supabaseClient.js` back at the old `app_state`-based code path (the Gate-0-fixed version from Step 1)
2. Confirm the original `app_state` rows are untouched (they were never deleted in Step 5 — this is exactly why)
3. Communicate to families/Team Parents that the new system is paused, old one is active again
4. Diagnose the failure against staging, not production, before attempting cutover again

## Explicit non-negotiables throughout
- No step in this document deletes, truncates, or destructively overwrites the current production `app_state` rows
- Every migration is additive-first and reviewed by a human before touching production
- Backups are never themselves modified or treated as "done, can discard"
