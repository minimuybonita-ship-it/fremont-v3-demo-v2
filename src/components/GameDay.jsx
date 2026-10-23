import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { checkIn, completeAssignment, verifyAssignment, reportNoShow, completeReplacementShift } from "../lib/volunteerEngine";
import { Card, StatCard, StatusPill, styles } from "./shared";

/* ============================================================
   GAME DAY — mobile-first operational view.
   Every action is a server-side business function that re-checks who you are:
   check-in / complete / verify = event staff (team parent, coach) or Commissioner;
   no-show + closeout decisions = Commissioner only. Time is recorded in exact minutes.
   The screen only decides which buttons to SHOW; the database decides what is ALLOWED.
   ============================================================ */
export default function GameDay({ teamId, isCommissioner, season }) {
  const [game, setGame] = useState(null);
  const [coverage, setCoverage] = useState([]);
  const [assignments, setAssignments] = useState([]);
  const [shifts, setShifts] = useState([]);
  const [minutes, setMinutes] = useState({});
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    setError("");
    try {
      let q = supabase
        .from("game_event")
        .select("id, opponent, starts_at, location, team_id")
        .eq("season_id", season.id)
        .order("starts_at", { ascending: true });
      if (!isCommissioner && teamId) q = q.eq("team_id", teamId);

      const { data: games, error: gErr } = await q
        .gte("starts_at", new Date(Date.now() - 1000 * 60 * 60 * 6).toISOString())
        .limit(1);
      if (gErr) throw gErr;
      const g = games?.[0] || null;
      setGame(g);
      if (!g) { setCoverage([]); setAssignments([]); setShifts([]); return; }

      const { data: cov, error: cErr } = await supabase.rpc("job_instance_coverage", { p_game_event_id: g.id });
      if (cErr) throw cErr;
      setCoverage(cov || []);

      const jiIds = (cov || []).map((c) => c.job_instance_id);
      const { data: asg, error: aErr } = await supabase
        .from("assignment")
        .select("id, status, actual_minutes_worked, family:family_id(display_name), job_instance:job_instance_id(credited_minutes_override, job_role_config:job_role_config_id(role_name, credited_minutes))")
        .in("job_instance_id", jiIds.length ? jiIds : ["00000000-0000-0000-0000-000000000000"]);
      if (aErr) throw aErr;
      setAssignments(asg || []);

      // Replacement shifts claimed by a household for THIS game, waiting for the staff to confirm they were worked.
      const asgIds = (asg || []).map((a) => a.id);
      const { data: sh } = await supabase
        .from("replacement_pool_entry")
        .select("id, status, claimed_by_family:claimed_by_family_id(display_name)")
        .in("assignment_id", asgIds.length ? asgIds : ["00000000-0000-0000-0000-000000000000"])
        .eq("status", "claimed");
      setShifts(sh || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { if (season) load(); }, [season, teamId, isCommissioner]);

  async function act(fn) {
    setError("");
    try { await fn(); await load(); } catch (e) { setError(e.message); }
  }

  const defaultMinutes = (a) =>
    a.job_instance?.credited_minutes_override ?? a.job_instance?.job_role_config?.credited_minutes ?? 60;

  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>No active season.</p></Card>;
  if (loading) return <Card><p style={{ color: "#8a8a8a" }}>Loading today's game…</p></Card>;
  if (!game) return <Card><p style={{ color: "#8a8a8a" }}>No game in the current window.</p></Card>;

  const unresolved = coverage.reduce((s, c) => s + Number(c.unresolved_count), 0);
  const started = game.starts_at ? new Date(game.starts_at) <= new Date() : true;

  return (
    <div style={styles.stack}>
      <Card accent>
        <p style={styles.eyebrow}>Game Day</p>
        <h1 style={styles.h1}>{game.opponent ? `vs ${game.opponent}` : "Game"}</h1>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>{game.location} · {game.starts_at ? new Date(game.starts_at).toLocaleString() : "time TBD"}</p>
        {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
        <StatCard icon={unresolved > 0 ? "🟡" : "✅"} label="Unresolved Coverage" value={unresolved} />
      </Card>

      <Card>
        <h2 style={styles.h2}>Staffing</h2>
        <div style={styles.stack}>
          {assignments.map((a) => (
            <div key={a.id} style={{ ...styles.requestRow, flexWrap: "wrap", gap: 8 }}>
              <div style={{ fontSize: 13 }}>
                {a.job_instance?.job_role_config?.role_name} · {a.family?.display_name}
                {a.actual_minutes_worked != null && <span style={{ color: "#8a8a8a" }}> · {a.actual_minutes_worked} min</span>}
              </div>
              <div style={{ display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" }}>
                <StatusPill status={a.status} />
                {a.status === "scheduled" && started && (
                  <button style={styles.secondaryBtnSm} onClick={() => act(() => checkIn(a.id))}>Check In</button>
                )}
                {a.status === "checked_in" && (
                  <>
                    <input
                      style={{ ...styles.input, width: 70, margin: 0 }}
                      type="number" min="1" max="720"
                      aria-label="Minutes worked"
                      value={minutes[a.id] ?? defaultMinutes(a)}
                      onChange={(e) => setMinutes({ ...minutes, [a.id]: e.target.value })}
                    />
                    <button
                      style={styles.secondaryBtnSm}
                      onClick={() => act(() => completeAssignment(a.id, parseInt(minutes[a.id] ?? defaultMinutes(a), 10)))}
                    >Complete</button>
                  </>
                )}
                {a.status === "completed" && (
                  <button style={styles.secondaryBtnSm} onClick={() => act(() => verifyAssignment(a.id))}>Verify</button>
                )}
                {["scheduled", "confirmed"].includes(a.status) && started && isCommissioner && (
                  <button
                    style={styles.secondaryBtnSm}
                    onClick={() => { if (window.confirm("Record a no-show? This starts the fee notice.")) act(() => reportNoShow(a.id)); }}
                  >No-Show</button>
                )}
              </div>
            </div>
          ))}
          {assignments.length === 0 && <p style={{ color: "#8a8a8a" }}>No assignments for this game.</p>}
        </div>
      </Card>

      {shifts.length > 0 && (
        <Card>
          <h2 style={styles.h2}>Replacement Shifts to Confirm ({shifts.length})</h2>
          <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
            Confirm the replacing household actually worked the shift. The $25 household credit is only issued afterward, when the Commissioner verifies it.
          </p>
          <div style={styles.stack}>
            {shifts.map((s) => (
              <div key={s.id} style={styles.requestRow}>
                <div>{s.claimed_by_family?.display_name}</div>
                <button style={styles.secondaryBtnSm} onClick={() => act(() => completeReplacementShift(s.id))}>Mark Worked</button>
              </div>
            ))}
          </div>
        </Card>
      )}

      <Card>
        <h2 style={styles.h2}>Game Closeout</h2>
        <p style={{ color: "#8a8a8a", fontSize: 13 }}>
          {unresolved > 0
            ? `Closeout blocked — ${unresolved} job(s) still open/claimed/confirmed/scheduled or with an unresolved no-show.`
            : "All jobs resolved. This game can be closed out once hours are verified."}
        </p>
      </Card>
    </div>
  );
}
