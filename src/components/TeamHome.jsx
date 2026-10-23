import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { Card, StatCard, StatusPill, styles } from "./shared";

/* ============================================================
   TEAM HOME — Team Parent / Coach non-game-day view.
   Least privilege: scoped to this team_id only (RLS backs this
   up server-side too — see schema/006, 014-016). No cash/credit
   ledger detail here, only aggregated fundraising visibility,
   per V3's role-appropriate-visibility rule.
   ============================================================ */
export default function TeamHome({ teamId, season }) {
  const [roster, setRoster] = useState([]);
  const [coverage, setCoverage] = useState({ needed: 0, filled: 0 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!teamId || !season) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const { data: players, error: rErr } = await supabase
          .from("player_season")
          .select("id, registration_stage, jersey_number, player:player_id(full_name)")
          .eq("team_id", teamId)
          .eq("season_id", season.id);
        if (rErr) throw rErr;

        const { data: games } = await supabase
          .from("game_event")
          .select("id")
          .eq("team_id", teamId)
          .eq("season_id", season.id)
          .gte("starts_at", new Date().toISOString())
          .order("starts_at", { ascending: true })
          .limit(1);

        let needed = 0, filled = 0;
        if (games?.[0]) {
          const { data: coverageRows } = await supabase.rpc("job_instance_coverage", { p_game_event_id: games[0].id });
          (coverageRows || []).forEach((r) => {
            needed += r.volunteers_needed;
            filled += Number(r.assignment_count) - Number(r.unresolved_count);
          });
        }

        if (!cancelled) {
          setRoster(players || []);
          setCoverage({ needed, filled });
        }
      } catch (e) {
        if (!cancelled) setError(e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [teamId, season]);

  if (!teamId) return <Card><p style={{ color: "#8a8a8a" }}>Your account isn't linked to a team yet.</p></Card>;
  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>No active season.</p></Card>;
  if (loading) return <Card><p style={{ color: "#8a8a8a" }}>Loading your team…</p></Card>;

  const ready = roster.filter((r) => r.registration_stage === "season_ready").length;

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>My Team</p>
        <h1 style={styles.h1}>Roster & Readiness</h1>
        {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
        <div style={styles.grid3}>
          <StatCard icon="👥" label="Roster" value={roster.length} />
          <StatCard icon="✅" label="Season Ready" value={ready} />
          <StatCard icon="🪑" label="Next Game Coverage" value={coverage.needed ? `${coverage.filled}/${coverage.needed}` : "—"} />
        </div>
      </Card>

      <Card>
        <h2 style={styles.h2}>Players</h2>
        <div style={styles.stack}>
          {roster.map((p) => (
            <div key={p.id} style={styles.requestRow}>
              <div>{p.player?.full_name}{p.jersey_number ? ` · #${p.jersey_number}` : ""}</div>
              <StatusPill status={p.registration_stage} />
            </div>
          ))}
          {roster.length === 0 && <p style={{ color: "#8a8a8a" }}>No players on this team yet.</p>}
        </div>
      </Card>
    </div>
  );
}
