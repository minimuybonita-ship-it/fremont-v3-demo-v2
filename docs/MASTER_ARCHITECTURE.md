# Master Architecture / Execution Record
**Fremont Football & Cheer — Custom Sport Command Center™ (Product 2 reference pilot)**
Last updated: this development pass. Supersedes all prior verbal/chat versions of this record.

## A. Current Fremont Technical State
- Production app: single-file React component, four role views, no router, PIN-based access (no real auth)
- Production persistence: Supabase `app_state` table, two JSON blob rows (`fremont-league-v1`, `fremont-campaign-v1`)
- **Gate 0 status: CODE FIX COMPLETE / PRODUCTION VERIFICATION PENDING.** The false "Synced ✓" bug is fixed in `LeagueFundraiserCommandCenter_GATE0FIX.jsx` (delivered separately). Not yet deployed to production. Cross-device verification of the *data* (not the fix) passed. The *fix itself* still needs a deploy + reload verification — see Gate 0 section of `DEPLOYMENT_MIGRATION_ROLLBACK.md`.
- Live production data (as of this pass): preserved untouched. Point-in-time backup delivered (`app_state_backup_2026-10-05T1526Z.json`). No destructive operation has been run against production at any point.

## B. Locked Fremont V3 Operational Rules
**LOCKED:**
- 3 volunteer hours per registered child, household-level, no parent multiplier, no sibling cap
- Hybrid assignment: Phase A family selection → Phase B auto-assign of unfilled required jobs → Phase C manage (confirm/swap/$25 replacement)
- Standard Home Game template with per-game/Homecoming overrides
- Org-job vs. team-duty credit flag, per-role configurable
- Full assignment lifecycle + audit log (implemented: `schema/003`, `lib/volunteerEngine.js`)
- $25 Replacement Pool — simplified, first-valid-claim-locks model (DB-enforced via unique partial index)
- Three ledgers, never merged: volunteer hours / cash / fundraising credit
- $1 social-share credit — built, configurable, board-approval gated, submissions collectible even while gate is off
- $50 Fremont no-show fee, 5-day pay window, posts to org process after — implemented as a `season_config`-sourced value, not hardcoded
- Existing fundraiser math, approval workflow, CSV export, Excel import, UI component library — reused, not rebuilt

**CONFIGURABLE (Core-level fields, Fremont sets today's value):**
- hours_per_child, fundraising_goal_per_child, replacement_fee_amount, no_show_fee_amount, no_show_grace_period_days, share_credit_amount

**FUTURE/PREMIUM (architecturally compatible, not built):**
- Backup Marketplace, ranked offer sequencing, offer timeouts
- "Above & Beyond" as a named/incentivized program (hours past zero are simply recorded — see note below)
- Health/Safety/Participation status module
- Expanded Documents & Policies module
- Expanded equipment issue/return system
- Season Memory Engine™, Game-Day Social/Memory Station, Awards QR → digital/POD book flow

**SUPERSEDED:**
- 2-hrs/parent, 4-hr-cap model and its capacity math
- Pure automatic full-rotation assignment with blanket team-duty crediting
- $5 social-share credit
- "No-show policy: FFL TO CONFIRM" — superseded by the $50 Fremont decision above; do not let this resurface as an open item

## C. Sports/League Operations Core
Reusable engine Fremont's build produces: Family & Athlete Hub, Volunteer Operations Engine, Fundraising Engine, Game-Day Operations, Events & Calendar, Communications, Training/SOPs, Commissioner/Admin Controls, Reporting, Season Configuration (versioned/snapshotted), Audit History. Implemented this pass: identity, season/config snapshotting, volunteer engine core, fundraising ledgers, auth/RLS. Not a customer-facing product on its own.

## D. Product 1 — Booster Club Command Center™
Standard/configurable, multi-sport. Not built. Will draw on the Core once Fremont's build stabilizes it.

## E. Product 2 — Custom Sport Command Center™ / Managed Season Implementation
Fremont is the reference/pilot implementation. Managed-implementation flow and its ten human-readable operational materials are part of this product's deliverable now (see `docs/product2/`), independent of how much of the flow is eventually automated. Governing rule, carried from the manual: **AI may enhance the procedure. AI may never be the procedure.**

## F. Product 3 — Sport-Specific Command Center™
Future. Not started. Explicitly distinct from Product 2 — a reusable sport blueprint is not the same artifact as one organization's customized instance.

## G. Product 2 Implementation Materials
Developed this pass as working templates in `docs/product2/` (ten documents per the approved list). Treated as Product 2 deliverables now, not deferred.

## H. Digital-Product/Fundraising Architecture
Existing box-sale fundraiser is the Fundraising Engine's first campaign type (`fundraising_campaign.campaign_type = 'product_sale'`), migrated not rebuilt. $25 and $1 credit types fit the same ledger model.

## I. Season Memory Engine™ — Future/Premium
Not built. Schema's `game_event`, `player`, `player_season` tables are deliberately generic enough not to block this later — no action needed now beyond that.

## J. Awards QR / Digital + POD Book — Future/Premium
Not built. No amounts, vendors, or QR destinations decided. Nothing in current schema blocks adding a stable player-season destination URL later.

## K. Current Build Priorities vs. Future
**This pass delivered:** schema (001–006, 999), auth/RLS, Family Dashboard, Commissioner Cockpit, volunteer engine core logic, Product 2 operational templates, this record, build status matrix, deployment/rollback plan, QA checklist.
**Still ahead before any production cutover:** see `BUILD_STATUS_MATRIX.md` for the itemized gap list — most importantly `families_owing_hours()`, the replacement-credit id-resolution bug flagged in `lib/volunteerEngine.js`, and the full UI for job-template/game-event management (Commissioner-side CRUD) which this pass did not reach.

## L. Decision Authority / Change Log
- 2-hrs/parent → superseded by 3-hrs/child
- $5 share credit → superseded by $1, board-gated
- Pure auto-rotation → superseded by hybrid selection-then-auto-assign
- Backup Marketplace → confirmed parked (reconfirmed after a brief ambiguity in an intermediate message)
- No-show policy → superseded from "FFL TO CONFIRM" to locked $50 Fremont policy on a configurable Core field
- Gate 0 → code fix complete, production verification explicitly pending; execution sequence changed (build continues in a controlled working version rather than blocking on per-step production deploys), architecture/requirements unchanged by that sequencing decision
