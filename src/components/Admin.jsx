import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";
import { Card, styles } from "./shared";

const NEXT_STATUS = { planning: "registration_open", registration_open: "active", active: "closed" };
const NEXT_LABEL = { planning: "Open Registration", registration_open: "Make Active", active: "Close Season" };

/* ============================================================
   ADMIN — CURRENT V3 configuration only. This is a settings
   screen for the schema that already exists, not a generic
   product builder: season status, season_config values
   (versioned/snapshotted — never edited in place), divisions/
   teams, job role matrix, and app_role assignment.
   ============================================================ */
export default function Admin({ season }) {
  const [tab, setTab] = useState("season");

  return (
    <div style={styles.stack}>
      <Card>
        <p style={styles.eyebrow}>Admin</p>
        <h1 style={styles.h1}>Configuration</h1>
      </Card>
      <div style={{ display: "flex", gap: 8 }}>
        {["season", "config", "teams", "households"].map((t) => (
          <button key={t} style={tab === t ? styles.primaryBtn : styles.secondaryBtn} onClick={() => setTab(t)}>
            {{ season: "Seasons", config: "Season Config", teams: "Divisions & Teams", households: "Households" }[t]}
          </button>
        ))}
      </div>
      {tab === "season" && <SeasonAdmin />}
      {tab === "config" && <ConfigAdmin season={season} />}
      {tab === "teams" && <TeamsAdmin season={season} />}
      {tab === "households" && <HouseholdAdmin />}
    </div>
  );
}

function SeasonAdmin() {
  const [seasons, setSeasons] = useState([]);
  const [name, setName] = useState("");
  const [starts, setStarts] = useState("");
  const [ends, setEnds] = useState("");
  const [error, setError] = useState("");

  async function load() {
    const { data } = await supabase.from("season").select("*").order("created_at", { ascending: false });
    setSeasons(data || []);
  }
  useEffect(() => { load(); }, []);

  async function createSeason() {
    const { error } = await supabase.from("season").insert({ name, starts_on: starts || null, ends_on: ends || null, status: "planning" });
    if (error) setError(error.message); else { setName(""); load(); }
  }

  // Status moves forward only, through a server function that enforces: one open season at a time,
  // settings present before registration opens, and closeout only when nothing is unresolved.
  async function advance(id, status) {
    setError("");
    const { error } = await supabase.rpc("set_season_status", { p_season_id: id, p_new_status: status });
    if (error) setError(error.message); else load();
  }

  return (
    <Card>
      <h2 style={styles.h2}>Seasons</h2>
      {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
      <div style={styles.stack}>
        {seasons.map((s) => (
          <div key={s.id} style={styles.requestRow}>
            <div>{s.name} <span style={{ color: "#8a8a8a", fontSize: 12 }}>({s.status})</span></div>
            {NEXT_STATUS[s.status] && (
              <button style={styles.secondaryBtnSm} onClick={() => {
                if (NEXT_STATUS[s.status] !== "closed" || window.confirm("Close this season? This cannot be undone.")) advance(s.id, NEXT_STATUS[s.status]);
              }}>{NEXT_LABEL[s.status]}</button>
            )}
          </div>
        ))}
      </div>
      <div style={{ marginTop: 12, borderTop: "1px solid #241010", paddingTop: 12 }}>
        <input style={styles.input} placeholder="New season name (e.g. 2027 Fall Season)" value={name} onChange={(e) => setName(e.target.value)} />
        <div style={styles.grid2}>
          <input style={styles.input} type="date" value={starts} onChange={(e) => setStarts(e.target.value)} />
          <input style={styles.input} type="date" value={ends} onChange={(e) => setEnds(e.target.value)} />
        </div>
        <button style={styles.primaryBtn} disabled={!name} onClick={createSeason}>Create Season</button>
      </div>
    </Card>
  );
}

function ConfigAdmin({ season }) {
  const [configs, setConfigs] = useState([]);
  const [draft, setDraft] = useState({ hours_per_child: 3, fundraising_goal_per_child: 200, replacement_fee_amount: 25, no_show_fee_amount: 50, no_show_grace_period_days: 5, share_credit_amount: 1 });
  const [error, setError] = useState("");

  async function load() {
    if (!season) return;
    const { data } = await supabase.from("season_config").select("*").eq("season_id", season.id).order("effective_at", { ascending: false });
    setConfigs(data || []);
  }
  useEffect(() => { load(); }, [season]);

  // Append-only per schema comment: a change creates a NEW row, never an UPDATE of a live config.
  async function saveNewConfig() {
    if (!season) return;
    const { error } = await supabase.from("season_config").insert({ season_id: season.id, ...draft, minutes_per_child: Math.round(draft.hours_per_child * 60) });
    if (error) setError(error.message); else load();
  }

  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>Create/open a season first.</p></Card>;

  return (
    <Card>
      <h2 style={styles.h2}>Season Config — {season.name}</h2>
      <p style={{ color: "#8a8a8a", fontSize: 13 }}>
        Append-only. Saving creates a new effective config row — it never rewrites an already-registered family's snapshot.
      </p>
      {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
      {configs.map((c) => (
        <div key={c.id} style={styles.requestRow}>
          <div style={{ fontSize: 12 }}>
            {new Date(c.effective_at).toLocaleString()} · {c.hours_per_child}h/child · ${c.fundraising_goal_per_child}/child
          </div>
        </div>
      ))}
      <div style={{ marginTop: 12, borderTop: "1px solid #241010", paddingTop: 12 }}>
        {Object.entries(draft).map(([k, v]) => (
          <input
            key={k}
            style={styles.input}
            type="number"
            placeholder={k}
            value={v}
            onChange={(e) => setDraft({ ...draft, [k]: Number(e.target.value) })}
          />
        ))}
        <button style={styles.primaryBtn} onClick={saveNewConfig}>Save New Config Version</button>
      </div>
    </Card>
  );
}

function TeamsAdmin({ season }) {
  const [divisions, setDivisions] = useState([]);
  const [newDivision, setNewDivision] = useState("");
  const [newTeam, setNewTeam] = useState({});

  async function load() {
    if (!season) return;
    const { data } = await supabase.from("division").select("id, name, team(id, name)").eq("season_id", season.id);
    setDivisions(data || []);
  }
  useEffect(() => { load(); }, [season]);

  if (!season) return <Card><p style={{ color: "#8a8a8a" }}>Create/open a season first.</p></Card>;

  return (
    <Card>
      <h2 style={styles.h2}>Divisions & Teams — {season.name}</h2>
      <div style={styles.stack}>
        {divisions.map((d) => (
          <div key={d.id} style={{ borderBottom: "1px solid #241010", paddingBottom: 8 }}>
            <div style={{ fontWeight: 700 }}>{d.name}</div>
            <div style={{ fontSize: 12, color: "#8a8a8a" }}>{(d.team || []).map((t) => t.name).join(", ") || "no teams yet"}</div>
            <div style={{ display: "flex", gap: 6, marginTop: 6 }}>
              <input
                style={{ ...styles.input, marginBottom: 0 }}
                placeholder="New team name"
                value={newTeam[d.id] || ""}
                onChange={(e) => setNewTeam({ ...newTeam, [d.id]: e.target.value })}
              />
              <button
                style={styles.secondaryBtnSm}
                onClick={async () => {
                  await supabase.from("team").insert({ division_id: d.id, name: newTeam[d.id] });
                  setNewTeam({ ...newTeam, [d.id]: "" });
                  load();
                }}
              >
                Add Team
              </button>
            </div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 12, display: "flex", gap: 6 }}>
        <input style={{ ...styles.input, marginBottom: 0 }} placeholder="New division (e.g. 10U Football)" value={newDivision} onChange={(e) => setNewDivision(e.target.value)} />
        <button
          style={styles.primaryBtn}
          disabled={!newDivision}
          onClick={async () => {
            await supabase.from("division").insert({ season_id: season.id, name: newDivision });
            setNewDivision("");
            load();
          }}
        >
          Add Division
        </button>
      </div>
    </Card>
  );
}

function HouseholdAdmin() {
  const empty = { display_name: "", guardian_name: "", email: "", phone: "", guardian2_name: "", guardian2_email: "" };
  const [f, setF] = useState(empty);
  const [households, setHouseholds] = useState([]);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function load() {
    const { data } = await supabase
      .from("family")
      .select("id, display_name, guardian(full_name, email, auth_user_id)")
      .order("display_name");
    setHouseholds(data || []);
  }
  useEffect(() => { load(); }, []);

  async function create() {
    setBusy(true); setError(""); setMsg("");
    const { error } = await supabase.rpc("commissioner_create_household", {
      p_display_name: f.display_name, p_guardian_name: f.guardian_name, p_guardian_email: f.email,
      p_guardian_phone: f.phone || null, p_guardian2_name: f.guardian2_name || null, p_guardian2_email: f.guardian2_email || null,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    setMsg(`Household created. Ask ${f.guardian_name} to sign in with ${f.email} — the account links automatically.`);
    setF(empty); load();
  }

  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  return (
    <Card>
      <h2 style={styles.h2}>Households</h2>
      <p style={{ color: "#8a8a8a", fontSize: 13, marginBottom: 8 }}>
        Add a household with its guardian's email. When that person signs in with the same email, their account links to this household automatically. Team Parent / Coach access is assigned by the platform administrator.
      </p>
      {error && <p style={{ color: "#ff6b6b" }}>{error}</p>}
      {msg && <p style={{ color: "#3fb950" }}>{msg}</p>}
      <input style={styles.input} placeholder="Household name (e.g. The Garcia Family)" value={f.display_name} onChange={set("display_name")} />
      <input style={styles.input} placeholder="Guardian full name" value={f.guardian_name} onChange={set("guardian_name")} />
      <input style={styles.input} type="email" placeholder="Guardian email (they will sign in with this)" value={f.email} onChange={set("email")} />
      <input style={styles.input} placeholder="Phone (optional)" value={f.phone} onChange={set("phone")} />
      <input style={styles.input} placeholder="Second guardian name (optional)" value={f.guardian2_name} onChange={set("guardian2_name")} />
      <input style={styles.input} type="email" placeholder="Second guardian email (optional)" value={f.guardian2_email} onChange={set("guardian2_email")} />
      <button style={styles.primaryBtn} disabled={busy || !f.display_name || !f.guardian_name || !f.email} onClick={create}>Create Household</button>

      <div style={{ marginTop: 14, borderTop: "1px solid #241010", paddingTop: 10 }}>
        <p style={styles.eyebrow}>{households.length} households</p>
        <div style={styles.stack}>
          {households.map((h) => (
            <div key={h.id} style={styles.requestRow}>
              <div style={{ fontSize: 13 }}>{h.display_name}</div>
              <div style={{ fontSize: 12, color: "#8a8a8a" }}>
                {(h.guardian || []).map((g) => `${g.email || g.full_name}${g.auth_user_id ? " ✓" : ""}`).join(", ")}
              </div>
            </div>
          ))}
        </div>
      </div>
    </Card>
  );
}
