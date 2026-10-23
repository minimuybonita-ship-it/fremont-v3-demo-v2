# Build Status Matrix
Status values used throughout: **EXISTS · IMPLEMENTED · PARTIAL · NOT BUILT · PARKED · NEEDS FOUNDER DECISION · NEEDS DEPLOYMENT VERIFICATION**

| Area | Status | Detail / exact next action |
|---|---|---|
| Gate 0 — false sync fix | NEEDS DEPLOYMENT VERIFICATION | Code fixed (`LeagueFundraiserCommandCenter_GATE0FIX.jsx`), not yet deployed/reloaded-and-observed in production |
| Core identity (family/guardian/player) | IMPLEMENTED | `schema/001`. Not yet populated from production — migration script is reference-only (`schema/999`), not run |
| Season + versioned config snapshot | IMPLEMENTED | `schema/002`. No live season row created yet — that's a data step, not a schema step |
| Volunteer engine schema | IMPLEMENTED | `schema/003`: job_role_config, templates, assignment lifecycle, audit log, replacement pool, no-show |
| Assignment state machine (code) | IMPLEMENTED | `lib/volunteerEngine.js` — `transitionAssignment()` enforces the full lifecycle graph with a paired audit write |
| Phase A→B auto-assignment | PARTIAL | `proposeAutoAssignments()` written as a dry-run proposer; blocked on `families_owing_hours()` RPC — **NEEDS FOUNDER DECISION**: exact hour-rounding/partial-credit rule before that RPC can be written correctly |
| $25 replacement claim | IMPLEMENTED | `claimReplacementShift()` — DB-enforced via unique partial index, race condition covered |
| $25 replacement verify/credit | PARTIAL | `verifyReplacementCompletion()` — logic present but credits against the wrong id (family vs. player_season). **NEEDS FOUNDER DECISION:** in a multi-child family, which child's fundraising balance receives a replacement credit — the family's youngest-remaining-balance child? An admin pick? Not specified anywhere in the manual or your decisions so far. |
| No-show fee | IMPLEMENTED (schema) | `no_show_record` table + `season_config.no_show_fee_amount` ($50 Fremont default). No UI built yet to issue the notice or track the 5-day clock — NOT BUILT |
| Fundraising ledgers (3-way split) | IMPLEMENTED (schema) | `schema/004`. No UI reads/writes it yet — existing fundraiser UI still points at `app_state` |
| $1 share credit workflow | IMPLEMENTED (schema), PARTIAL (UI) | Submission table + dedupe constraint done. Approval UI stub only in Commissioner Cockpit; the actual approve/reject action buttons are NOT BUILT |
| Real auth (magic link) | IMPLEMENTED | `lib/auth.js`, `AuthGate.jsx` |
| Family-level privacy (RLS) | IMPLEMENTED | `schema/006` — this is the direct fix for the audit's open privacy gap. Not yet applied to any live project |
| Family Dashboard | PARTIAL | Shows children, aggregated hours, assignments. Uniform status, events, training links, fundraising progress sections are NOT BUILT |
| Commissioner Cockpit | PARTIAL | Exceptions feed + key counts implemented. Team/job/template CRUD, staffing-by-game breakdown are NOT BUILT |
| Team Parent dashboard | NOT BUILT | Existing fundraiser app's Team Parent view still works standalone; not yet re-pointed at new schema |
| Standard Home Game template UI | NOT BUILT | Schema supports it (`job_template`, `job_template_item`); no admin screen to create/apply one |
| Uniforms | IMPLEMENTED (schema only) | `schema/005`. No UI |
| Training/SOP library | IMPLEMENTED (schema only) | `schema/005`. No UI; content itself is mostly "FFL TO CONFIRM" per the manual's own instruction not to invent it |
| Events/calendar | IMPLEMENTED (schema only) | `schema/005`. No UI |
| Data migration (app_state → relational) | NOT BUILT (reference only) | `schema/999` is commented reference logic, intentionally not executable, pending a human-reviewed target season + family-duplicate pass |
| Product 2 operational materials | IMPLEMENTED | `docs/product2/` — all 10 as working templates |
| Backup Marketplace, ranked offers, timeouts | PARKED | Per approved scope lock |
| Above & Beyond named program | PARKED | Hours past zero are simply queryable, no feature wrapper |
| Health/Safety, expanded Documents/Policies, expanded equipment | PARKED | Per approved scope lock |
| Season Memory Engine, Awards QR, POD book | PARKED | Per approved scope lock; schema doesn't block adding later |

## Items requiring a founder decision before further build
1. Replacement-credit targeting in a multi-child family (see row above)
2. Hour-rounding/partial-credit rule for `families_owing_hours()`
3. No-show fee: who actually issues the "notice" (automated email, or a Commissioner action) — not specified yet
4. Content for training resources marked `ffl_to_confirm` (admission prices, parking map, etc. — per the manual, Claude should not invent these)
