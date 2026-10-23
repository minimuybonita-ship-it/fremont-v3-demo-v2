// FREMONT V3 — Volunteer Operations Engine (client side).
// ALL writes go through strict server-side business-action functions (schema/029, 030).
// The browser holds no INSERT/UPDATE rights on assignments, audit rows, ledgers or no-show records,
// and the server re-validates every action (role, season open, capacity, registration, idempotency).
// Time (assignment minutes), cash (fundraising_cash_ledger) and credits (fundraising_credit_ledger)
// are three separate ledgers and nothing here mixes them.

import { supabase } from "./supabaseClient";

const ACTIVE = ["claimed", "confirmed", "scheduled", "checked_in", "completed", "verified", "credited"];

async function rpc(fn, args) {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data;
}

/* ---------- Phase A (families choose) ---------- */
export const listOpenJobs = (seasonId) => rpc("open_jobs_for_season", { p_season_id: seasonId });
export const claimJob = (jobInstanceId) => rpc("claim_volunteer_job", { p_job_instance_id: jobInstanceId });

/* ---------- Phase B (propose -> human approves -> apply) ---------- */
/** Dry run only. Never writes. Returns what a Commissioner may review, edit, then apply. */
export async function proposeAutoAssignments({ seasonId }) {
  const { data: jobs, error: jiErr } = await supabase
    .from("job_instance")
    .select("id, volunteers_needed, game_event!inner(season_id, starts_at, opponent), assignment(id, family_id, status)")
    .eq("game_event.season_id", seasonId)
    .gt("game_event.starts_at", new Date().toISOString());
  if (jiErr) throw jiErr;

  const needingCoverage = (jobs || []).filter((ji) => {
    const filled = (ji.assignment || []).filter((a) => ACTIVE.includes(a.status)).length;
    return filled < ji.volunteers_needed;
  });

  const { data: owing, error: owingErr } = await supabase.rpc("families_owing_hours", { p_season_id: seasonId });
  if (owingErr) throw owingErr;
  const sortedOwing = [...(owing || [])]
    .filter((f) => f.remaining_minutes > 0)
    .sort((a, b) => b.remaining_minutes - a.remaining_minutes);

  const proposedAssignments = [];
  let i = 0;
  for (const ji of needingCoverage) {
    const taken = new Set((ji.assignment || []).filter((a) => ACTIVE.includes(a.status)).map((a) => a.family_id));
    let open = ji.volunteers_needed - taken.size;
    let guard = 0;
    while (open > 0 && sortedOwing.length > 0 && guard < sortedOwing.length) {
      const f = sortedOwing[i % sortedOwing.length];
      i += 1; guard += 1;
      if (taken.has(f.family_id)) continue; // never propose the same household twice on one job
      taken.add(f.family_id);
      proposedAssignments.push({ job_instance_id: ji.id, family_id: f.family_id, remaining_minutes: f.remaining_minutes });
      open -= 1;
    }
  }
  return { needingCoverage, familiesOwing: sortedOwing, proposedAssignments };
}

/** Human-approval chokepoint. Commissioner only (enforced in the database). Atomic: all pairs or none. */
export async function applyApprovedAssignments({ seasonId, approvedPairs }) {
  if (!approvedPairs?.length) return { inserted: 0, skipped: 0 };
  const pairs = approvedPairs.map((p) => ({ job_instance_id: p.job_instance_id, family_id: p.family_id }));
  const rows = await rpc("apply_auto_assignments", { p_season_id: seasonId, p_pairs: pairs });
  const r = Array.isArray(rows) ? rows[0] : rows;
  return { inserted: r?.inserted ?? 0, skipped: r?.skipped ?? 0 };
}

/* ---------- Game Day ---------- */
export const checkIn = (assignmentId) => rpc("assignment_check_in", { p_assignment_id: assignmentId });
export const completeAssignment = (assignmentId, minutes) =>
  rpc("assignment_complete", { p_assignment_id: assignmentId, p_minutes: minutes });
export const verifyAssignment = (assignmentId) => rpc("assignment_verify", { p_assignment_id: assignmentId });
export const reportNoShow = (assignmentId) => rpc("assignment_report_no_show", { p_assignment_id: assignmentId });
export const resolveNoShow = (noShowId, resolution) =>
  rpc("resolve_no_show", { p_no_show_id: noShowId, p_resolution: resolution });

/* ---------- $25 replacement ---------- */
export const requestReplacement = (assignmentId) => rpc("request_replacement", { p_assignment_id: assignmentId });
export const listOpenReplacementShifts = (seasonId) => rpc("open_replacement_shifts", { p_season_id: seasonId });
export const claimReplacementShift = (entryId) => rpc("claim_replacement_shift", { p_entry_id: entryId });
export const completeReplacementShift = (entryId) => rpc("complete_replacement_shift", { p_entry_id: entryId });
/** Credit is issued ONLY here, after a Commissioner verifies completion. Household-level, idempotent. */
export const verifyReplacementCredit = (entryId) => rpc("verify_replacement_credit", { p_entry_id: entryId });

/* ---------- Fundraising ---------- */
export const reviewSocialShare = (submissionId, approve) =>
  rpc("review_social_share", { p_submission_id: submissionId, p_approve: approve });
export const recordCashEntry = ({ playerSeasonId, amount, note, campaignId, idempotencyKey }) =>
  rpc("record_cash_entry", {
    p_player_season_id: playerSeasonId, p_amount: amount, p_note: note || null,
    p_campaign_id: campaignId || null, p_idempotency_key: idempotencyKey || null,
  });
