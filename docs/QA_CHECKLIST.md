# QA Test Plan — Fremont V3

Run against **staging only** until Step 4 of the deployment plan passes, then re-run the full list once more against production during cutover verification.

## Volunteer hour formula
- [ ] One child → 3 required family hours
- [ ] Two siblings → 6 required family hours
- [ ] Three siblings → 9 required family hours
- [ ] Guardian 2 blank → calculation unchanged
- [ ] Two guardians + one child → still 3 hours (no parent multiplier)
- [ ] Children across different divisions → hours aggregate correctly at the family level, not per-division

## Assignment lifecycle
- [ ] Normal assignment: open → claimed → confirmed → scheduled → checked_in → completed → verified → credited
- [ ] Normal swap: original assignment stays active until receiving family accepts
- [ ] Receiving family never accepts swap → original family still owns the assignment
- [ ] `transitionAssignment()` rejects an invalid transition (e.g. open → credited directly) with `InvalidTransitionError`

## $25 Replacement Pool
- [ ] Replacement requested → payment recorded → shift enters pool as `open`
- [ ] First eligible family claims → locks (status → `claimed`)
- [ ] Second family attempts to claim the same shift at nearly the same time → second claim fails cleanly (tests the unique partial index, not just application logic)
- [ ] Replacement completes, not yet verified → no credit issued (`credit_issued` stays false)
- [ ] Replacement verified → credit issued, exactly once
- [ ] Replacement claimed but person never shows → resolves via `needs_review`, not silently

## Fundraising ledgers
- [ ] Volunteer hours, cash, and fundraising credit never share a column/table
- [ ] $1 share: submission → pending → approved → credit recorded, but payout respects `share_credit_board_approved`
- [ ] $1 share: rejected submission never creates credit
- [ ] Duplicate proof (same `proof_hash` for the same player_season) is rejected by the unique index

## Standard Home Game / staffing
- [ ] Template creates the same job set across multiple games when applied
- [ ] Homecoming = Standard Home Game + extras, not a full rebuild
- [ ] Staffing shortage (volunteers_needed > filled) is visible in the Commissioner Cockpit
- [ ] Staffing surplus doesn't break any count

## Uniforms
- [ ] Size confirmed and stored
- [ ] Returning player's prior-year size is visible
- [ ] Reorder creates a new `uniform_history` row without deleting the prior one

## Season config / snapshotting
- [ ] Changing `season_config.hours_per_child` mid-season does not alter already-registered families' `player_season.season_config_id` snapshot
- [ ] A new season's config starts independently of the prior season's

## Privacy / RLS
- [ ] A guardian account can see only their own family's data
- [ ] A team_parent account can see their team's data, not another team's
- [ ] A commissioner account can see everything
- [ ] An authenticated user with no `app_role` row sees nothing (handled by `AuthGate`'s "Account Pending" state)

## Data integrity during migration (once Step 3 of deployment plan runs)
- [ ] Every `sold`/`moneyIn`/`creditEarned` value from the backup file matches the migrated relational rows exactly
- [ ] Ambiguous family-name matches are flagged (`duplicate_review_status = 'flagged'`), never auto-merged
- [ ] Original `app_state` rows still exist, byte-for-byte, after migration

## Gate 0 (production, see DEPLOYMENT_MIGRATION_ROLLBACK.md Step 1)
- [ ] Sync badge never shows "Synced ✓" when no row exists for a key
- [ ] Sync badge correctly shows "Synced ✓" once a real row is confirmed
- [ ] Second-device check still shows the same data after the fix deploys
