import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { listOpenJobs, claimJob, requestReplacement, listOpenReplacementShifts, claimReplacementShift } from "../lib/volunteerEngine";
import { Card, StatCard, ProgressBar, StatusPill, styles } from "./shared";

/* ============================================================
   FAMILY DASHBOARD
   Answers one question, per V3 §17: "What do I need to do next?"
   Household-level, actual-minute accounting: required/scheduled/
   completed/verified all come from the server-side
   families_owing_hours() RPC (3h x registered children, no parent
   multiplier, no sibling cap, minutes not whole-hour rounding), so
   this screen can never drift from what Phase B and closeout use.
   Fundraising comes from family_fundraising_summary() — cash and
   credit stay separate, never merged.
   ============================================================ */
const fmtMinutes = (m) => {
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `${h}h ${r}m` : `${h}h`;
};

export default function FamilyDashboard({ familyId, season }) {
  const [children, setChildren] = useState([]);
  const [assignments, setAssignments] = useState([]);
  const [hours, setHours] = useState(null);
  const [fund, setFund] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [openJobs, setOpenJobs] = useState([]);
  const [shifts, setShifts] = useState([]);
  const [shares, setShares] = useState([]);
  const [shareChild, setShareChild] = useState("");
  const [shareUrl, setShareUrl] = useState("");
  const [notice, setNotice] = useState("");
  const [tick, setTick] = useState(0);
  const reload = () => setTick((t) => t + 1);

  async function act(fn, okMsg) {
    setError(""); setNotice("");
    try { await fn(); if (okMsg) setNotice(okMsg); reload(); } catch (e) { setError(e.message); }
  }

  useEffect(() => {
    if (!familyId || !season) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const { data: players, error: pErr } = await supabase
          .from("player")
          .select("id, full_name, player_season!inner(id, registration_stage, season_id)")
          .eq("family_id", familyId)
          .eq("player_season.season_id", season.id);
        if (pErr) throw pErr;

        const { data: asg, error: aErr } = await supabase
          .from("assignment")
          .select("id, status, job_instance_id, job_instance:job_instance_id(game_event:game_event_id(opponent, starts_at, season_id), job_role_config:job_role_config_id(role_name)), replacement_pool_entry(id, status)")
          .eq("family_id", familyId)
          .neq("status", "cancelled");
        if (aErr) throw aErr;

        // Phase A choices + replacement shifts: read through narrow server functions (they never expose other households).
        const [jobs, rshifts, shr] = await Promise.all([
          listOpenJobs(season.id),
          listOpenReplacementShifts(season.id),
          supabase.from("social_share_submission")
            .select("id, status, proof_url, credit_amount, player_season:player_season_id(id, player:player_id(full_name))")
            .order("submitted_at", { ascending: false }),
        ]);

        const { data: owing, error: oErr } = await supabase.rpc("families_owing_hours", { p_season_id: season.id });
        if (oErr) throw oErr;

        const { data: fs, error: fErr } = await supabase.rpc("family_fundraising_summary", { p_family_id: familyId, p_season_id: season.id });
        if (fErr) throw fErr;

        if (!cancelled) {
          setChildren(players || []);
          setOpenJobs(jobs || []);
          setShifts(rshifts || []);
          setShares(shr.data || []);
          setAssignments(asg || []);
          setHours((owing || []).find((r) => r.family_id === familyId) || null);
          setFund(fs?.[0] || null);
        }
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [familyId, season, tick]);

  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>No active season.</p></Card>;
  if (loading) return <Card><p style={{ color: "#8a8a8a" }}>Loading your family's dashboard…</p></Card>;

  const required = hours?.required_minutes ?? 0;
  const verified = hours?.verified_minutes ?? 0;
  const percent = required ? Math.min(100, Math.round((verified / required) * 100)) : 0;

  return (
    <div style={styles.stack}>
      {error && <Card accent><p style={{ color: "#ff6b6b" }}>{error}</p></Card>}

      <Card>
        <p style={styles.eyebrow}>Family Dashboard</p>
        <h1 style={styles.h1}>My Children</h1>
        <div style={styles.stack}>
          {children.map((p) => (
            <div key={p.id} style={styles.requestRow}>
              <div>
                <div style={{ fontWeight: 700 }}>{p.full_name}</div>
                <div style={{ fontSize: 12, color: "#8a8a8a" }}>
                  {p.player_season?.[0]?.registration_stage === "season_ready" ? "Season Ready ✓" : "Registration in progress"}
                </div>
              </div>
            </div>
          ))}
          {children.length === 0 && <p style={{ color: "#8a8a8a" }}>No registered children found for this family yet.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>My Volunteer Commitment</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 12 }}>
          {hours?.registered_children ?? 0} registered {hours?.registered_children === 1 ? "child" : "children"} × 3 hours = {fmtMinutes(required)} family
          hours this season. This is a household total — it does not change based on how many parents you have.
        </p>
        <ProgressBar percent={percent} />
        <div style={styles.grid3}>
          <StatCard icon="🎯" label="Required" value={fmtMinutes(required)} />
          <StatCard icon="📅" label="Scheduled" value={fmtMinutes(hours?.scheduled_minutes ?? 0)} />
          <StatCard icon="✅" label="Verified" value={fmtMinutes(verified)} />
        </div>
        {required > 0 && (hours?.remaining_minutes ?? required) === 0 && (
          <p style={{ color: "#3fb950", fontWeight: 800, marginTop: 10 }}>FAMILY VOLUNTEER COMMITMENT COMPLETE ✓</p>
        )}
      </Card>

      <Card>
        <h2 style={styles.h2}>My Fundraising</h2>
        <div style={styles.grid3}>
          <StatCard icon="🎯" label="Goal" value={`$${Number(fund?.required_total ?? 0).toLocaleString()}`} />
          <StatCard icon="💵" label="Cash" value={`$${Number(fund?.cash_total ?? 0).toLocaleString()}`} />
          <StatCard icon="🎟️" label="Credit" value={`$${Number(fund?.credit_total ?? 0).toLocaleString()}`} />
        </div>
        <p style={{ color: "#8a8a8a", fontSize: 12, marginTop: 8 }}>
          Remaining: ${Number(fund?.remaining_total ?? 0).toLocaleString()}. Cash and credit are tracked separately.
        </p>
      </Card>

      <Card>
        <h2 style={styles.h2}>My Assignments</h2>
        {assignments.length === 0 && <p style={{ color: "#8a8a8a" }}>No assignments yet — pick a job below while selection is open.</p>}
        <div style={styles.stack}>
          {assignments.map((a) => {
            const ge = a.job_instance?.game_event;
            const asked = (a.replacement_pool_entry || []).length > 0;
            return (
              <div key={a.id} style={{ ...styles.requestRow, flexWrap: "wrap", gap: 8 }}>
                <div style={{ fontSize: 13 }}>
                  {a.job_instance?.job_role_config?.role_name || "Job"}
                  {ge && <span style={{ color: "#8a8a8a" }}> · {ge.opponent ? `vs ${ge.opponent}` : "Game"} · {ge.starts_at ? new Date(ge.starts_at).toLocaleString() : "time TBD"}</span>}
                </div>
                <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                  <StatusPill status={a.status} />
                  {a.status === "scheduled" && !asked && ge?.starts_at && new Date(ge.starts_at) > new Date() && (
                    <button
                      style={styles.secondaryBtnSm}
                      onClick={() => { if (window.confirm("Release this shift to the replacement pool? A $25 household fee applies unless another household covers it and completes it.")) act(() => requestReplacement(a.id), "Shift released to the replacement pool."); }}
                    >Need a replacement</button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Open Jobs — Pick Yours</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
          Choose a job for an upcoming game. Anything left unfilled after the selection deadline is assigned by the Commissioner.
        </p>
        {notice && <p style={{ color: "#3fb950" }}>{notice}</p>}
        <div style={styles.stack}>
          {openJobs.filter((j) => Number(j.filled) < j.volunteers_needed || j.i_have_it).map((j) => (
            <div key={j.job_instance_id} style={{ ...styles.requestRow, flexWrap: "wrap", gap: 8 }}>
              <div style={{ fontSize: 13 }}>
                <b>{j.role_name}</b> · {j.credited_minutes} min
                <div style={{ color: "#8a8a8a" }}>
                  {j.opponent ? `vs ${j.opponent}` : "Game"} · {j.starts_at ? new Date(j.starts_at).toLocaleString() : "time TBD"} · {j.team_name || "All teams"} · {Number(j.filled)}/{j.volunteers_needed} filled
                </div>
              </div>
              {j.i_have_it
                ? <span style={{ color: "#3fb950", fontSize: 12 }}>You have this ✓</span>
                : <button style={styles.secondaryBtnSm} onClick={() => act(() => claimJob(j.job_instance_id), "Job claimed.")}>Claim</button>}
            </div>
          ))}
          {openJobs.length === 0 && <p style={{ color: "#8a8a8a" }}>No open jobs right now.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Replacement Shifts — Earn a $25 Credit</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
          Cover a shift another household released. The $25 household credit is issued only after the Commissioner verifies you worked it. Replacement shifts do not count toward your volunteer hours.
        </p>
        <div style={styles.stack}>
          {shifts.map((r) => (
            <div key={r.entry_id} style={styles.requestRow}>
              <div style={{ fontSize: 13 }}>
                <b>{r.role_name}</b> · {r.opponent ? `vs ${r.opponent}` : "Game"} · {r.starts_at ? new Date(r.starts_at).toLocaleString() : "time TBD"}
              </div>
              <button style={styles.secondaryBtnSm} onClick={() => act(() => claimReplacementShift(r.entry_id), "Shift claimed. Credit comes after it is worked and verified.")}>Take it</button>
            </div>
          ))}
          {shifts.length === 0 && <p style={{ color: "#8a8a8a" }}>No replacement shifts open.</p>}
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Share Credit</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
          Paste a link to your public share post. The Commissioner reviews it; credit is only awarded after approval.
        </p>
        {children.length > 0 && (
          <>
            <select style={styles.input} value={shareChild} onChange={(e) => setShareChild(e.target.value)}>
              <option value="">Which child?</option>
              {children.map((p) => (p.player_season || []).map((ps) => (
                <option key={ps.id} value={ps.id}>{p.full_name}</option>
              )))}
            </select>
            <input style={styles.input} placeholder="https://…" value={shareUrl} onChange={(e) => setShareUrl(e.target.value)} />
            <button
              style={styles.secondaryBtn}
              disabled={!shareChild || !shareUrl}
              onClick={() => act(async () => {
                const { error: e } = await supabase.from("social_share_submission").insert({ player_season_id: shareChild, proof_url: shareUrl });
                if (e) throw new Error(e.message);
                setShareUrl("");
              }, "Submitted for review.")}
            >Submit link</button>
          </>
        )}
        <div style={{ ...styles.stack, marginTop: 10 }}>
          {shares.map((x) => (
            <div key={x.id} style={styles.requestRow}>
              <div style={{ fontSize: 13 }}>{x.player_season?.player?.full_name} · <span style={{ color: "#8a8a8a" }}>{x.proof_url.slice(0, 40)}</span></div>
              <StatusPill status={x.status} />
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}
