// FREMONT V3 — Registration / Season Setup helpers.
// GOVERNING RULE: official Fremont registration + payment happens BEFORE
// Command Center onboarding. Nothing here collects money or acts as a
// merchant of record — this is roster/household data entry only, for a
// family who has already registered/paid with Fremont directly.
//
// Household flow: GUARDIAN -> ADD CHILD -> match/claim -> "add another
// child?" -> repeat -> review -> submit. One `family` row per household,
// many `player` rows (one per child), one `player_season` row per child
// per season (registration_stage drives the Commissioner review workflow).

import { supabase } from "./supabaseClient";

// NOTE: household/guardian creation is intentionally NOT here. The schema
// has no client INSERT policy on family/guardian (default-deny); households
// are created by the Commissioner or the migration, then linked to a login
// via app_role.family_id.

/**
 * Returning-player search, scoped to names only (no DOB/contact exposed
 * in results — this is a match candidate list for the registering family
 * to recognize their own child, not a general player directory).
 */
export async function searchReturningPlayers(fullName) {
  const { data, error } = await supabase
    .from("player")
    .select("id, full_name, family_id, family:family_id(display_name)")
    .ilike("full_name", `%${fullName.trim()}%`)
    .limit(10);
  if (error) throw error;
  return data || [];
}

/**
 * Claims an existing player record as belonging to this household (the
 * "returning player" path) and opens a draft player_season for the given
 * season. If the found player belongs to a DIFFERENT family already,
 * this does not reassign it silently — it marks the player match_status
 * as 'needs_review' so a Commissioner resolves the conflict in
 * IdentityReview.jsx. This is the fail-closed identity rule.
 */
export async function claimReturningPlayer({ playerId, claimingFamilyId, seasonId, seasonConfigId }) {
  const { data: player, error: pErr } = await supabase
    .from("player")
    .select("id, family_id, match_status")
    .eq("id", playerId)
    .single();
  if (pErr) throw pErr;

  if (player.family_id !== claimingFamilyId) {
    // Different household claiming this player identity — never silently
    // reassign. Flag for Commissioner review and stop here.
    await supabase.from("player").update({ match_status: "needs_review" }).eq("id", playerId);
    throw new Error(
      "This player is already linked to a different household. A Commissioner needs to review this match before registration can continue."
    );
  }

  return openDraftPlayerSeason({ playerId, seasonId, seasonConfigId });
}

/** New (never-registered-before) child: creates the player row, then a draft player_season. */
export async function addNewChild({ familyId, fullName, dateOfBirth, seasonId, seasonConfigId }) {
  const { data: player, error } = await supabase
    .from("player")
    .insert({ family_id: familyId, full_name: fullName, date_of_birth: dateOfBirth || null })
    .select()
    .single();
  if (error) throw error;
  return openDraftPlayerSeason({ playerId: player.id, seasonId, seasonConfigId });
}

async function openDraftPlayerSeason({ playerId, seasonId, seasonConfigId }) {
  const { data, error } = await supabase
    .from("player_season")
    .insert({
      player_id: playerId,
      season_id: seasonId,
      season_config_id: seasonConfigId,
      registration_stage: "draft",
      registration_status: "pending",
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Autosave a field on a draft registration (jersey #, emergency contact, etc.). Stays in 'draft' until submitted. */
export async function saveDraftField({ playerId, playerSeasonId, patch }) {
  if (patch.player) {
    const { error } = await supabase.from("player").update(patch.player).eq("id", playerId);
    if (error) throw error;
  }
  if (patch.playerSeason) {
    const { error } = await supabase.from("player_season").update(patch.playerSeason).eq("id", playerSeasonId);
    if (error) throw error;
  }
}

/**
 * Submits a child's registration for Commissioner review. Fails closed:
 * refuses to submit if required fields are missing rather than letting
 * an incomplete registration through as "submitted".
 */
export async function submitRegistration({ playerSeasonId }) {
  const { data: ps, error: fetchErr } = await supabase
    .from("player_season")
    .select("id, registration_stage, player:player_id(full_name, emergency_contact_name, emergency_contact_phone)")
    .eq("id", playerSeasonId)
    .single();
  if (fetchErr) throw fetchErr;

  const missing = [];
  if (!ps.player?.emergency_contact_name) missing.push("emergency contact name");
  if (!ps.player?.emergency_contact_phone) missing.push("emergency contact phone");
  if (missing.length) {
    throw new Error(`Cannot submit yet — missing: ${missing.join(", ")}.`);
  }

  const { error } = await supabase
    .from("player_season")
    .update({ registration_stage: "submitted", submitted_at: new Date().toISOString() })
    .eq("id", playerSeasonId);
  if (error) throw error;
}

/** All of one household's children for a season, with readiness, for the Review step and Family Dashboard. */
export async function getHouseholdRegistrations({ familyId, seasonId }) {
  const { data, error } = await supabase
    .from("player")
    .select("id, full_name, player_season!inner(id, registration_stage, correction_note, correction_due_at, season_ready_at)")
    .eq("family_id", familyId)
    .eq("player_season.season_id", seasonId);
  if (error) throw error;
  return data || [];
}
