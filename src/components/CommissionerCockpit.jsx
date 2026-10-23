import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { proposeAutoAssignments, applyApprovedAssignments, verifyReplacementCredit, completeReplacementShift, reviewSocialShare, resolveNoShow, recordCashEntry } from "../lib/volunteerEngine";
import { Card, StatCard, styles } from "./shared";

/* ============================================================
   COMMISSIONER CONTROL CENTER
   "Kelly shouldn't have to remember who owes what. The system should."
   Extends the Oct 6 checkpoint (exceptions feed + key counts) with the
   later work that didn't survive: registration review, identity review
   access, Phase B propose/review/apply, replacement verification, and
   social-share approval — all surfaced as actions here, not buried in
   separate unlinked screens.
   ============================================================ */
export default function CommissionerCockpit({ seasonId }) {
  const [stats, setStats] = useState(null);
  const [exceptions, setExceptions] = useState([]);
  const [registrationQueue, setRegistrationQueue] = useState([]);
  const [identityCount, setIdentityCount] = useState(0);
  const [replacementsToVerify, setReplacementsToVerify] = useState([]);
  const [pendingShares, setPendingSharesList] = useState([]);
  const [noShows, setNoShows] = useState([]);
  const [claimedShifts, setClaimedShifts] = useState([]);
  const [kids, setKids] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function load() {
    setLoading(true);
    try {
      const { count: openPool } = await supabase
        .from("replacement_pool_entry").select("id", { count: "exact", head: true }).eq("status", "open");
      const { count: awaitingVerification } = await supabase
        .from("assignment").select("id", { count: "exact", head: true }).eq("status", "completed");
      const { count: needsReview } = await supabase
        .from("assignment").select("id", { count: "exact", head: true }).eq("status", "needs_review");
      const { count: pendingSharesCount } = await supabase
        .from("social_share_submission").select("id", { count: "exact", head: true }).eq("status", "pending");
      const { data: creditTotals } = await supabase.from("fundraising_credit_ledger").select("amount");
      const totalCredited = (creditTotals || []).reduce((s, r) => s + Number(r.amount || 0), 0);

      const { data: regQueue } = await supabase
        .from("player_season")
        .select("id, registration_stage, player:player_id(full_name)")
        .eq("season_id", seasonId)
        .in("registration_stage", ["submitted", "review"]);

      const { count: idCount } = await supabase
        .from("player").select("id", { count: "exact", head: true }).in("match_status", ["possible_match", "needs_review"]);

      const { data: replsToVerify } = await supabase
        .from("replacement_pool_entry")
        .select("id, fee_amount, claimed_by_family:claimed_by_family_id(display_name)")
        .eq("status", "completed");

      const { data: shares } = await supabase
        .from("social_share_submission")
        .select("id, proof_url, credit_amount, player_season:player_season_id(player:player_id(full_name))")
        .eq("status", "pending");

      const { data: ns } = await supabase
        .from("no_show_record")
        .select("id, fee_amount, pay_by_date, resolution_status, family:family_id(display_name)")
        .eq("resolution_status", "pending");
      const { data: cl } = await supabase
        .from("replacement_pool_entry")
        .select("id, claimed_by_family:claimed_by_family_id(display_name)")
        .eq("status", "claimed");
      const { data: ks } = await supabase
        .from("player_season")
        .select("id, player:player_id(full_name)")
        .eq("season_id", seasonId);
      setNoShows(ns || []);
      setClaimedShifts(cl || []);
      setKids((ks || []).sort((a, b) => (a.player?.full_name || "").localeCompare(b.player?.full_name || "")));

      setStats({ openPool, awaitingVerification, needsReview, pendingShares: pendingSharesCount, totalCredited });
      setExceptions(
        [
          needsReview > 0 && { icon: "🔴", text: `${needsReview} assignment(s) need review` },
          openPool > 0 && { icon: "🟡", text: `${openPool} replacement shift(s) open and unclaimed` },
          (ns || []).length > 0 && { icon: "🔴", text: `${ns.length} no-show fee(s) unresolved — blocks season closeout` },
          awaitingVerification > 0 && { icon: "🟡", text: `${awaitingVerification} completed job(s) awaiting verification` },
          pendingSharesCount > 0 && { icon: "🟡", text: `${pendingSharesCount} social-share submission(s) pending review` },
          idCount > 0 && { icon: "🔴", text: `${idCount} identity match(es) need review` },
          (regQueue || []).length > 0 && { icon: "🟡", text: `${regQueue.length} registration(s) awaiting review` },
        ].filter(Boolean)
      );
      setRegistrationQueue(regQueue || []);
      setIdentityCount(idCount || 0);
      setReplacementsToVerify(replsToVerify || []);
      setPendingSharesList(shares || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { if (seasonId) load(); }, [seasonId]);

  async function setRegistrationStage(id, stage, extra = {}) {
    const { error } = await supabase
      .from("player_season")
      .update({ registration_stage: stage, reviewed_at: new Date().toISOString(), ...extra })
      .eq("id", id);
    if (error) setError(error.message); else load();
  }

  async function run(fn) {
    setError("");
    try { await fn(); load(); } catch (e) { setError(e.message); }
  }
  const verifyReplacement = (entryId) => run(() => verifyReplacementCredit(entryId));
  const reviewShare = (id, approve) => run(() => reviewSocialShare(id, approve));

  if (loading || !seasonId) return <Card><p style={{ color: "#8a8a8a" }}>Loading operational view…</p></Card>;

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>Commissioner Control Center</p>
        <h1 style={styles.h1}>Today</h1>
        {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
        {exceptions.length === 0 ? (
          <p style={{ color: "#3fb950" }}>No exceptions right now — everything's on track.</p>
        ) : (
          <div style={styles.stack}>{exceptions.map((e, i) => <div key={i} style={{ fontSize: 14 }}>{e.icon} {e.text}</div>)}</div>
        )}
      </Card>

      <div style={styles.grid3}>
        <StatCard icon="🪑" label="Open Pool Shifts" value={stats.openPool ?? 0} />
        <StatCard icon="✅" label="Awaiting Verification" value={stats.awaitingVerification ?? 0} />
        <StatCard icon="💰" label="Credited" value={`$${stats.totalCredited.toLocaleString()}`} />
      </div>

      <Card>
        <h2 style={styles.h2}>Registration Review ({registrationQueue.length})</h2>
        <div style={styles.stack}>
          {registrationQueue.map((r) => (
            <div key={r.id} style={styles.requestRow}>
              <div>{r.player?.full_name} <span style={{ color: "#8a8a8a", fontSize: 12 }}>({r.registration_stage})</span></div>
              <div style={{ display: "flex", gap: 6 }}>
                <button style={styles.secondaryBtnSm} onClick={() => setRegistrationStage(r.id, "approved")}>Approve</button>
                <button style={styles.secondaryBtnSm} onClick={() => {
                  const note = window.prompt("Correction needed — what should the family fix?");
                  if (note) setRegistrationStage(r.id, "correction_needed", { correction_note: note, correction_due_at: new Date(Date.now() + 7 * 86400000).toISOString() });
                }}>Needs Correction</button>
                <button style={styles.secondaryBtnSm} onClick={() => setRegistrationStage(r.id, "waitlisted")}>Waitlist</button>
              </div>
            </div>
          ))}
          {registrationQueue.length === 0 && <p style={{ color: "#8a8a8a" }}>Nothing pending.</p>}
        </div>
      </Card>

      <CashEntry kids={kids} onDone={load} setError={setError} />

      <Card>
        <h2 style={styles.h2}>No-Show Fees ({noShows.length})</h2>
        <div style={styles.stack}>
          {noShows.map((n) => (
            <div key={n.id} style={{ ...styles.requestRow, flexWrap: "wrap", gap: 8 }}>
              <div style={{ fontSize: 13 }}>{n.family?.display_name} — ${n.fee_amount} <span style={{ color: "#8a8a8a" }}>pay by {n.pay_by_date}</span></div>
              <div style={{ display: "flex", gap: 6 }}>
                <button style={styles.secondaryBtnSm} onClick={() => run(() => resolveNoShow(n.id, "paid"))}>Paid</button>
                <button style={styles.secondaryBtnSm} onClick={() => run(() => resolveNoShow(n.id, "waived"))}>Waive</button>
                <button style={styles.secondaryBtnSm} onClick={() => run(() => resolveNoShow(n.id, "posted_to_org_process"))}>Sent to League</button>
              </div>
            </div>
          ))}
          {noShows.length === 0 && <p style={{ color: "#8a8a8a" }}>None unresolved.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Replacement Shifts Claimed ({claimedShifts.length})</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>Mark worked once the replacing household did the shift (event must have started). Then verify below to issue the $25 household credit.</p>
        <div style={styles.stack}>
          {claimedShifts.map((c) => (
            <div key={c.id} style={styles.requestRow}>
              <div>{c.claimed_by_family?.display_name}</div>
              <button style={styles.secondaryBtnSm} onClick={() => run(() => completeReplacementShift(c.id))}>Mark Worked</button>
            </div>
          ))}
          {claimedShifts.length === 0 && <p style={{ color: "#8a8a8a" }}>Nothing waiting.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Identity Review</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>{identityCount} possible match(es) pending — open the Identity Review tab to resolve.</p>
      </Card>

      <PhaseB seasonId={seasonId} onApplied={load} />

      <Card>
        <h2 style={styles.h2}>Replacement Verification ({replacementsToVerify.length})</h2>
        <div style={styles.stack}>
          {replacementsToVerify.map((r) => (
            <div key={r.id} style={styles.requestRow}>
              <div>{r.claimed_by_family?.display_name} — ${r.fee_amount}</div>
              <button style={styles.secondaryBtnSm} onClick={() => verifyReplacement(r.id)}>Verify & Credit Household</button>
            </div>
          ))}
          {replacementsToVerify.length === 0 && <p style={{ color: "#8a8a8a" }}>Nothing pending.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Share Credit Approvals ({pendingShares.length})</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 10 }}>
          Approval is blocked until the board has approved the share credit for this season (a season setting). Each proof link can earn credit only once.
        </p>
        <div style={styles.stack}>
          {pendingShares.map((s) => (
            <div key={s.id} style={styles.requestRow}>
              <div>{s.player_season?.player?.full_name} — ${s.credit_amount}</div>
              <div style={{ display: "flex", gap: 6 }}>
                <button style={styles.secondaryBtnSm} onClick={() => reviewShare(s.id, true)}>Approve</button>
                <button style={styles.secondaryBtnSm} onClick={() => reviewShare(s.id, false)}>Reject</button>
              </div>
            </div>
          ))}
          {pendingShares.length === 0 && <p style={{ color: "#8a8a8a" }}>Nothing pending.</p>}
        </div>
      </Card>
    </div>
  );
}

function PhaseB({ seasonId, onApplied }) {
  const [proposal, setProposal] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function propose() {
    setBusy(true);
    try {
      setProposal(await proposeAutoAssignments({ seasonId }));
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }

  async function apply() {
    setBusy(true);
    try {
      await applyApprovedAssignments({ seasonId, approvedPairs: proposal.proposedAssignments });
      setProposal(null);
      onApplied();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }

  return (
    <Card accent>
      <h2 style={styles.h2}>Phase B — Auto-Assign Unfilled Jobs</h2>
      <p style={{ color: "#8a8a8a", fontSize: 13 }}>
        Proposes pairings only. Nothing is written until you review and click Apply.
      </p>
      {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
      {!proposal && <button style={styles.secondaryBtn} disabled={busy} onClick={propose}>Propose Assignments</button>}
      {proposal && (
        <>
          <div style={styles.stack}>
            {proposal.proposedAssignments.map((p, i) => (
              <div key={i} style={{ fontSize: 13, color: "#b5b5b5" }}>
                Job {p.job_instance_id.slice(0, 8)} → family {p.family_id.slice(0, 8)} ({p.remaining_minutes} min owed)
              </div>
            ))}
            {proposal.proposedAssignments.length === 0 && <p style={{ color: "#8a8a8a" }}>No open slots or no families owing hours.</p>}
          </div>
          <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
            <button style={styles.primaryBtn} disabled={busy || !proposal.proposedAssignments.length} onClick={apply}>Apply ({proposal.proposedAssignments.length})</button>
            <button style={styles.secondaryBtn} onClick={() => setProposal(null)}>Discard</button>
          </div>
        </>
      )}
    </Card>
  );
}

function CashEntry({ kids, onDone, setError }) {
  const [ps, setPs] = useState("");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  // One key per form fill: a double-tap or retry can never record the same entry twice.
  const [key, setKey] = useState(() => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())));

  async function save() {
    setBusy(true); setError(""); setMsg("");
    try {
      await recordCashEntry({ playerSeasonId: ps, amount: Number(amount), note, idempotencyKey: key });
      setMsg(`Recorded $${Number(amount).toFixed(2)}.`);
      setAmount(""); setNote("");
      setKey(crypto.randomUUID ? crypto.randomUUID() : String(Date.now()));
      onDone();
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }

  return (
    <Card>
      <h2 style={styles.h2}>Record Cash Received</h2>
      <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
        Actual money only (separate from credits and volunteer time). Entries are never edited — to fix a mistake, enter a negative amount with a note.
      </p>
      <select style={styles.input} value={ps} onChange={(e) => setPs(e.target.value)}>
        <option value="">Which child?</option>
        {kids.map((k) => <option key={k.id} value={k.id}>{k.player?.full_name}</option>)}
      </select>
      <input style={styles.input} type="number" step="0.01" placeholder="Amount (e.g. 20.00, or -5.00 to reverse)" value={amount} onChange={(e) => setAmount(e.target.value)} />
      <input style={styles.input} placeholder="Note (required for a reversal)" value={note} onChange={(e) => setNote(e.target.value)} />
      <button style={styles.secondaryBtn} disabled={busy || !ps || !amount} onClick={save}>Record</button>
      {msg && <p style={{ color: "#3fb950", marginTop: 8 }}>{msg}</p>}
    </Card>
  );
}
