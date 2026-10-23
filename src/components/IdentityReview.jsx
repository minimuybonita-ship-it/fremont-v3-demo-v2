import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { Card, StatusPill, styles } from "./shared";

/* ============================================================
   IDENTITY REVIEW — Commissioner-only.
   Two distinct situations, never auto-resolved:
     A) Two PLAYER rows might be the same kid (same name, two
        families) -> player.match_status = 'possible_match'/'needs_review'.
        Resolution here NEVER merges player rows; it only confirms
        'verified' (same person, fix the family link manually elsewhere)
        or 'confirmed_different_person' / 'rejected'.
     B) Two FAMILY rows might actually be ONE household (e.g. two
        siblings whose legacy data landed in separate family rows).
        Resolution here reassigns the children's player.family_id to
        the surviving family, and marks the other family row
        duplicate_review_status='merged' with duplicate_of set — this
        IS the audit trail (who/when comes from this action, not a
        separate log table that doesn't exist in this schema).
     Per V3 §25 / BUILD_STATUS_MATRIX: never infer a match from names
     alone. A human looks at both sides before every decision here.
   ============================================================ */
export default function IdentityReview() {
  const [playerMatches, setPlayerMatches] = useState([]);
  const [flaggedFamilies, setFlaggedFamilies] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function load() {
    setLoading(true);
    try {
      const { data: players, error: pErr } = await supabase
        .from("player")
        .select("id, full_name, family_id, match_status, family:family_id(display_name)")
        .in("match_status", ["possible_match", "needs_review"]);
      if (pErr) throw pErr;

      const { data: families, error: fErr } = await supabase
        .from("family")
        .select("id, display_name, duplicate_review_status, player(id, full_name)")
        .eq("duplicate_review_status", "flagged");
      if (fErr) throw fErr;

      setPlayerMatches(players || []);
      setFlaggedFamilies(families || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(); }, []);

  async function resolvePlayerMatch(playerId, status) {
    const { error } = await supabase.from("player").update({ match_status: status }).eq("id", playerId);
    if (error) setError(error.message); else load();
  }

  async function markFamiliesDistinct(familyIds) {
    const { error } = await supabase
      .from("family")
      .update({ duplicate_review_status: "reviewed_distinct" })
      .in("id", familyIds);
    if (error) setError(error.message); else load();
  }

  /**
   * SAME-HOUSEHOLD MERGE (e.g. the Alex/Ben case): both children keep
   * their own player + player_season rows. Only the family they point
   * at changes. The losing family row is never deleted — it's marked
   * merged/duplicate_of so the history of the decision survives.
   */
  async function mergeFamilies({ survivingFamilyId, losingFamilyId }) {
    const { error: reassignErr } = await supabase
      .from("player")
      .update({ family_id: survivingFamilyId })
      .eq("family_id", losingFamilyId);
    if (reassignErr) { setError(reassignErr.message); return; }

    const { error: markErr } = await supabase
      .from("family")
      .update({ duplicate_review_status: "merged", duplicate_of: survivingFamilyId })
      .eq("id", losingFamilyId);
    if (markErr) { setError(markErr.message); return; }

    const { error: survErr } = await supabase
      .from("family")
      .update({ duplicate_review_status: "reviewed_distinct" })
      .eq("id", survivingFamilyId);
    if (survErr) { setError(survErr.message); return; }

    load();
  }

  if (loading) return <Card><p style={{ color: "#8a8a8a" }}>Loading identity review queue…</p></Card>;

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>Identity Review</p>
        <h1 style={styles.h1}>Possible Matches</h1>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>
          Nothing here is ever merged automatically. Review each case and choose what's actually true.
        </p>
      </Card>

      {error && <Card accent><p style={{ color: "#ff6b6b" }}>{error}</p></Card>}

      <Card>
        <h2 style={styles.h2}>Same-Player Candidates ({playerMatches.length})</h2>
        {playerMatches.length === 0 && <p style={{ color: "#8a8a8a" }}>None pending.</p>}
        <div style={styles.stack}>
          {playerMatches.map((p) => (
            <div key={p.id} style={styles.requestRow}>
              <div>
                <div style={{ fontWeight: 700 }}>{p.full_name}</div>
                <div style={{ fontSize: 12, color: "#8a8a8a" }}>{p.family?.display_name} · <StatusPill status={p.match_status} /></div>
              </div>
              <div style={{ display: "flex", gap: 6 }}>
                <button style={styles.secondaryBtnSm} onClick={() => resolvePlayerMatch(p.id, "verified")}>Same person</button>
                <button style={styles.secondaryBtnSm} onClick={() => resolvePlayerMatch(p.id, "confirmed_different_person")}>Different person</button>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Flagged Households ({flaggedFamilies.length})</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>
          These were flagged during migration because more than one child mapped to the same
          free-text family label. Confirm whether they're genuinely one household (e.g. siblings)
          or just a name coincidence.
        </p>
        <div style={styles.stack}>
          {flaggedFamilies.map((f) => (
            <div key={f.id} style={styles.requestRow}>
              <div>
                <div style={{ fontWeight: 700 }}>{f.display_name}</div>
                <div style={{ fontSize: 12, color: "#8a8a8a" }}>
                  {(f.player || []).map((p) => p.full_name).join(", ") || "no players"}
                </div>
              </div>
            </div>
          ))}
        </div>
        {flaggedFamilies.length >= 2 && (
          <FamilyMergePicker families={flaggedFamilies} onMerge={mergeFamilies} onDistinct={markFamiliesDistinct} />
        )}
      </Card>
    </div>
  );
}

function FamilyMergePicker({ families, onMerge, onDistinct }) {
  const [a, setA] = useState(families[0]?.id || "");
  const [b, setB] = useState(families[1]?.id || "");

  return (
    <div style={{ marginTop: 14, borderTop: "1px solid #241010", paddingTop: 14 }}>
      <p style={{ fontSize: 12, color: "#8a8a8a", marginBottom: 8 }}>
        Compare two flagged households and decide:
      </p>
      <div style={styles.grid2}>
        <select style={styles.input} value={a} onChange={(e) => setA(e.target.value)}>
          {families.map((f) => <option key={f.id} value={f.id}>{f.display_name}</option>)}
        </select>
        <select style={styles.input} value={b} onChange={(e) => setB(e.target.value)}>
          {families.map((f) => <option key={f.id} value={f.id}>{f.display_name}</option>)}
        </select>
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
        <button
          style={styles.primaryBtn}
          disabled={a === b}
          onClick={() => onMerge({ survivingFamilyId: a, losingFamilyId: b })}
        >
          Same household — merge into "{families.find((f) => f.id === a)?.display_name}"
        </button>
        <button style={styles.secondaryBtn} disabled={a === b} onClick={() => onDistinct([a, b])}>
          Different households — not a match
        </button>
      </div>
    </div>
  );
}
