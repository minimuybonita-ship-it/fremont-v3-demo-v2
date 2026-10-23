import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import {
  searchReturningPlayers,
  claimReturningPlayer,
  addNewChild,
  saveDraftField,
  submitRegistration,
  getHouseholdRegistrations,
} from "../lib/registration";
import { Card, StatusPill, styles } from "./shared";

/* ============================================================
   FREMONT SEASON SETUP (Registration.jsx)
   Flow: GUARDIAN -> ADD CHILD -> match/claim -> "Add another
   child?" -> repeat -> REVIEW -> SUBMIT.
   This is Command Center onboarding, not Fremont's official
   registration/payment system — no money moves here.
   ============================================================ */
export default function Registration({ session, familyId, activeSeason }) {
  // Households are created by the Commissioner / migration and linked to a
  // guardian login through an app_role row (the database has no client
  // INSERT policy on family/guardian by design — default-deny). So this
  // screen never creates a household; it registers children INTO the
  // household the signed-in guardian is already linked to.
  const [children, setChildren] = useState([]);
  const [error, setError] = useState("");
  const family = familyId ? { family_id: familyId } : null;

  async function refreshChildren(fid) {
    try {
      const rows = await getHouseholdRegistrations({ familyId: fid, seasonId: activeSeason.id });
      setChildren(rows);
    } catch (e) {
      setError(e.message);
    }
  }

  useEffect(() => {
    if (familyId && activeSeason) refreshChildren(familyId);
  }, [familyId, activeSeason]);

  if (!familyId) {
    return (
      <Card>
        <p style={{ color: "#8a8a8a" }}>
          Your login isn't linked to a household yet. Ask your Commissioner to link your account.
        </p>
      </Card>
    );
  }

  if (!activeSeason) {
    return (
      <Card>
        <p style={{ color: "#8a8a8a" }}>
          Registration isn't open yet. Check back once the Commissioner opens this season.
        </p>
      </Card>
    );
  }

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>Fremont Season Setup</p>
        <h1 style={styles.h1}>{activeSeason.name}</h1>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>
          This sets up your household in the Command Center for games, volunteering, and fundraising.
          It is not Fremont's official registration or payment — complete that with Fremont directly first.
        </p>
      </Card>

      {error && <Card accent><p style={{ color: "#ff6b6b" }}>{error}</p></Card>}

      {family && (
        <>
          <ChildrenList
            familyId={family.family_id}
            seasonId={activeSeason.id}
            seasonConfigId={activeSeason.season_config_id}
            children={children}
            onChanged={() => refreshChildren(family.family_id)}
            onError={setError}
          />
          {children.length > 0 && <ReviewAndSubmit children={children} onChanged={() => refreshChildren(family.family_id)} onError={setError} />}
        </>
      )}
    </div>
  );
}

function ChildrenList({ familyId, seasonId, seasonConfigId, children, onChanged, onError }) {
  const [adding, setAdding] = useState(children.length === 0);

  return (
    <Card>
      <h2 style={styles.h2}>My Children</h2>
      <div style={styles.stack}>
        {children.map((c) => (
          <ChildRow key={c.id} child={c} onChanged={onChanged} onError={onError} />
        ))}
      </div>

      {adding ? (
        <AddChildForm
          familyId={familyId}
          seasonId={seasonId}
          seasonConfigId={seasonConfigId}
          onDone={() => { setAdding(false); onChanged(); }}
          onError={onError}
        />
      ) : (
        <button style={styles.secondaryBtn} onClick={() => setAdding(true)}>+ Add Another Child</button>
      )}
    </Card>
  );
}

function AddChildForm({ familyId, seasonId, seasonConfigId, onDone, onError }) {
  const [name, setName] = useState("");
  const [dob, setDob] = useState("");
  const [matches, setMatches] = useState(null);
  const [busy, setBusy] = useState(false);

  async function search() {
    if (!name.trim()) return;
    try {
      setMatches(await searchReturningPlayers(name));
    } catch (e) {
      onError(e.message);
    }
  }

  async function claim(playerId) {
    setBusy(true);
    try {
      await claimReturningPlayer({ playerId, claimingFamilyId: familyId, seasonId, seasonConfigId });
      onDone();
    } catch (e) {
      onError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function addNew() {
    setBusy(true);
    try {
      await addNewChild({ familyId, fullName: name, dateOfBirth: dob, seasonId, seasonConfigId });
      onDone();
    } catch (e) {
      onError(e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{ marginTop: 14, borderTop: "1px solid #241010", paddingTop: 14 }}>
      <input style={styles.input} placeholder="Child's full name" value={name} onChange={(e) => setName(e.target.value)} onBlur={search} />
      <input style={styles.input} type="date" placeholder="Date of birth" value={dob} onChange={(e) => setDob(e.target.value)} />

      {matches && matches.length > 0 && (
        <div style={{ marginBottom: 10 }}>
          <p style={{ fontSize: 12, color: "#8a8a8a" }}>Is this your returning player?</p>
          {matches.map((m) => (
            <div key={m.id} style={styles.requestRow}>
              <div style={{ fontSize: 13 }}>{m.full_name} — {m.family?.display_name || "unknown household"}</div>
              <button style={styles.secondaryBtnSm} disabled={busy} onClick={() => claim(m.id)}>This is my child</button>
            </div>
          ))}
        </div>
      )}

      <button style={styles.primaryBtn} disabled={busy || !name.trim()} onClick={addNew}>
        {matches && matches.length > 0 ? "None of these — add as new" : "Add Child"}
      </button>
    </div>
  );
}

function ChildRow({ child, onChanged, onError }) {
  const ps = child.player_season?.[0];
  const [contact, setContact] = useState({ name: "", phone: "" });
  const [jersey, setJersey] = useState("");

  if (!ps) return null;

  const stageLabel = {
    draft: "Draft — not yet submitted",
    submitted: "Submitted — awaiting Commissioner review",
    review: "In Review",
    correction_needed: "Correction Needed",
    approved: "Approved",
    waitlisted: "Waitlisted",
    season_ready: "Season Ready ✓",
    withdrawn: "Withdrawn",
    refunded: "Refunded",
  }[ps.registration_stage] || ps.registration_stage;

  return (
    <div style={styles.requestRow}>
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 700 }}>{child.full_name}</div>
        <div style={{ fontSize: 12, color: "#8a8a8a" }}>{stageLabel}</div>
        {ps.registration_stage === "correction_needed" && ps.correction_note && (
          <div style={{ fontSize: 12, color: "#ffb454", marginTop: 4 }}>
            Commissioner note: {ps.correction_note}
            {ps.correction_due_at && ` (by ${new Date(ps.correction_due_at).toLocaleDateString()})`}
          </div>
        )}
        {(ps.registration_stage === "draft" || ps.registration_stage === "correction_needed") && (
          <div style={{ marginTop: 8 }}>
            <input style={styles.input} placeholder="Emergency contact name" value={contact.name} onChange={(e) => setContact({ ...contact, name: e.target.value })} />
            <input style={styles.input} placeholder="Emergency contact phone" value={contact.phone} onChange={(e) => setContact({ ...contact, phone: e.target.value })} />
            <input style={styles.input} placeholder="Jersey size (optional)" value={jersey} onChange={(e) => setJersey(e.target.value)} />
            <button
              style={styles.secondaryBtn}
              onClick={async () => {
                try {
                  await saveDraftField({
                    playerId: child.id,
                    playerSeasonId: ps.id,
                    patch: { player: { emergency_contact_name: contact.name, emergency_contact_phone: contact.phone } },
                  });
                  onChanged();
                } catch (e) {
                  onError(e.message);
                }
              }}
            >
              Save
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function ReviewAndSubmit({ children, onChanged, onError }) {
  const submittable = children.filter((c) => {
    const ps = c.player_season?.[0];
    return ps && (ps.registration_stage === "draft" || ps.registration_stage === "correction_needed");
  });

  if (submittable.length === 0) {
    return (
      <Card accent>
        <p style={{ color: "#3fb950", fontWeight: 700 }}>
          Everything is submitted. The Commissioner will review each child's registration next.
        </p>
      </Card>
    );
  }

  return (
    <Card accent>
      <h2 style={styles.h2}>Review & Submit</h2>
      <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 10 }}>
        Submitting sends each child to the Commissioner for review. You can still add children after submitting.
      </p>
      <div style={styles.stack}>
        {submittable.map((c) => (
          <div key={c.id} style={styles.requestRow}>
            <div>{c.full_name}</div>
            <button
              style={styles.primaryBtn}
              onClick={async () => {
                try {
                  await submitRegistration({ playerSeasonId: c.player_season[0].id });
                  onChanged();
                } catch (e) {
                  onError(e.message);
                }
              }}
            >
              Submit
            </button>
          </div>
        ))}
      </div>
    </Card>
  );
}
