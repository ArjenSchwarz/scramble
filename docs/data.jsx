// Shared data + theme for all three direction prototypes
// Using Midnight Atlas (dark) as default — most legible per my recommendation.

const theme = {
  bg: "linear-gradient(160deg, #0A0E1A 0%, #141B2D 40%, #1A1F35 100%)",
  bgSolid: "#0F1422",
  surface: "rgba(255,255,255,0.05)",
  surfaceHi: "rgba(255,255,255,0.08)",
  border: "rgba(255,255,255,0.08)",
  borderHi: "rgba(255,255,255,0.14)",
  accent: "#64D2FF",
  accentDim: "rgba(100,210,255,0.14)",
  accentSoft: "rgba(100,210,255,0.08)",
  text: "#E8ECF4",
  textSec: "#7A8299",
  textTer: "#535B6B",
  check: "#30D158",
  checkDim: "rgba(48,209,88,0.16)",
  warn: "#FF9F0A",
  warnDim: "rgba(255,159,10,0.16)",
  // Phase colors — stops on the journey
  phaseColors: ["#9B7EFF", "#64D2FF", "#30D158", "#FFD60A", "#FF9F0A", "#FF6961", "#7A8299"],
};

const phases = [
  { key: "weeksBefore",     short: "Weeks",     label: "Weeks before",      offsetDays: -14 },
  { key: "dayBefore",       short: "Day before",label: "Day before",        offsetDays: -1  },
  { key: "departure",       short: "Departure", label: "Departure day",     offsetDays:  0  },
  { key: "during",          short: "During",    label: "During trip",       offsetDays:  3  },
  { key: "dayBeforeReturn", short: "Pre-return",label: "Day before return", offsetDays:  9  },
  { key: "returnDay",       short: "Return",    label: "Return day",        offsetDays: 10  },
  { key: "after",           short: "After",     label: "After trip",        offsetDays: 12  },
];

const people = [
  { name: "Arjen",    short: "A", color: "#64D2FF" },
  { name: "Kelsey",   short: "K", color: "#FF6EB4" },
  { name: "Pacifica", short: "P", color: "#FFD60A" },
  { name: "Rigel",    short: "R", color: "#30D158" },
];

// Tasks — phase index, name, optional assignee idx, done state, conditions (for "why is this here?")
const tasksSeed = [
  { name: "Book pet sitter",          phase: 0, done: true,  by: null, why: ["Always"] },
  { name: "Check passport expiry",    phase: 0, done: true,  by: 0,    why: ["scope: international"] },
  { name: "Renew travel insurance",   phase: 0, done: false, by: 1,    why: ["scope: international"] },
  { name: "Download offline maps",    phase: 0, done: false, by: 0,    why: ["scope: international"] },
  { name: "Books on Kindle",          phase: 0, done: false, by: 0,    why: ["duration: long"] },
  { name: "Set out-of-office",        phase: 1, done: false, by: 0,    why: ["purpose: work"] },
  { name: "Charge Kindle",            phase: 1, done: false, by: 0,    why: ["Always"] },
  { name: "Charge iPad for kids",     phase: 1, done: true,  by: 1,    why: ["Always"] },
  { name: "Water plants",             phase: 1, done: false, by: null, why: ["duration: long"] },
  { name: "Take out bins",            phase: 2, done: false, by: null, why: ["Always"] },
  { name: "Lock all windows",         phase: 2, done: false, by: null, why: ["Always"] },
  { name: "Set alarm",                phase: 2, done: false, by: 0,    why: ["Always"] },
  { name: "Buy gifts for family",     phase: 3, done: false, by: null, why: ["scope: international"] },
  { name: "Check room for items",     phase: 4, done: false, by: null, why: ["Always"] },
  { name: "Repack suitcases",         phase: 4, done: false, by: null, why: ["Always"] },
  { name: "Wash clothes",             phase: 6, done: false, by: 1,    why: ["Always"] },
  { name: "File insurance claim",     phase: 6, done: false, by: 0,    why: ["scope: international"] },
];

// Packing — person idx, name, state, conditions
const packingSeed = [
  // Arjen
  { name: "Passport",         person: 0, state: "packed",   why: ["scope: international"] },
  { name: "Rain jacket",      person: 0, state: "packed",   why: ["weather: rain"] },
  { name: "Laptop + charger", person: 0, state: "unpacked", why: ["purpose: work"] },
  { name: "Kindle",           person: 0, state: "packed",   why: ["Always"] },
  { name: "Toiletries",       person: 0, state: "packed",   why: ["Always"] },
  { name: "Running shoes",    person: 0, state: "unpacked", why: [] },
  { name: "Swim shorts",      person: 0, state: "packed",   why: ["weather: sun"] },
  { name: "Sunglasses",       person: 0, state: "excluded", why: ["weather: sun"] },
  // Kelsey
  { name: "Passport",         person: 1, state: "packed",   why: ["scope: international"] },
  { name: "Hair straightener",person: 1, state: "unpacked", why: [] },
  { name: "Sunscreen",        person: 1, state: "packed",   why: ["weather: sun"] },
  { name: "Book",             person: 1, state: "packed",   why: ["Always"] },
  { name: "Makeup bag",       person: 1, state: "unpacked", why: ["Always"] },
  { name: "Sandals",          person: 1, state: "packed",   why: ["weather: sun"] },
  // Pacifica
  { name: "Stuffed bear",     person: 2, state: "packed",   why: ["Always"] },
  { name: "Colouring books",  person: 2, state: "unpacked", why: ["duration: long"] },
  { name: "Swimsuit",         person: 2, state: "packed",   why: ["weather: sun"] },
  { name: "Sandals",          person: 2, state: "unpacked", why: ["weather: sun"] },
  // Rigel
  { name: "Nappies (×30)",    person: 3, state: "packed",   why: ["Always"] },
  { name: "Formula",          person: 3, state: "unpacked", why: ["Always"] },
  { name: "Muslin cloths",    person: 3, state: "packed",   why: ["Always"] },
  { name: "Travel cot sheet", person: 3, state: "unpacked", why: ["Always"] },
];

const trip = {
  name: "Barcelona",
  flag: "🇪🇸",
  startLabel: "Jul 12",
  endLabel: "Jul 22",
  daysAway: 14,
  // attributes
  attrs: {
    duration: "long",
    transport: "plane",
    scope: "international",
    weather: ["sun"],
    purpose: "leisure",
  },
};

// Phone shell — minimal, theme-aware. Not a real iOS bezel — just enough to read.
function Phone({ label, children, accent }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
      <div style={{
        fontSize: 11, fontWeight: 700, letterSpacing: 0.8, textTransform: "uppercase",
        color: accent || theme.accent, fontFamily: "-apple-system, system-ui, sans-serif",
      }}>{label}</div>
      <div style={{
        width: 360, height: 740, borderRadius: 44,
        background: theme.bg,
        boxShadow: "0 40px 80px rgba(0,0,0,0.5), 0 0 0 8px #0a0a0e, 0 0 0 9px rgba(255,255,255,0.08)",
        overflow: "hidden", position: "relative",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif",
        color: theme.text,
        display: "flex", flexDirection: "column",
      }}>
        {/* dynamic island */}
        <div style={{
          position: "absolute", top: 9, left: "50%", transform: "translateX(-50%)",
          width: 110, height: 32, borderRadius: 20, background: "#000", zIndex: 50,
        }} />
        {/* status bar */}
        <div style={{
          padding: "16px 28px 0", display: "flex", justifyContent: "space-between",
          alignItems: "center", fontSize: 14, fontWeight: 600, color: theme.text,
          position: "relative", zIndex: 10,
        }}>
          <span>9:41</span>
          <span style={{ display: "flex", gap: 4, fontSize: 12 }}>
            <span>􀙇</span><span>􀛨</span><span>􀛨</span>
          </span>
        </div>
        <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column", paddingTop: 14 }}>
          {children}
        </div>
        {/* home indicator */}
        <div style={{
          position: "absolute", bottom: 8, left: "50%", transform: "translateX(-50%)",
          width: 130, height: 5, borderRadius: 100, background: "rgba(255,255,255,0.5)", zIndex: 60,
        }} />
      </div>
    </div>
  );
}

// shared check component
function Check({ checked, color, size = 22, onClick }) {
  return (
    <div onClick={(e) => { e?.stopPropagation?.(); onClick?.(); }} style={{
      width: size, height: size, borderRadius: 6, flexShrink: 0, cursor: "pointer",
      border: checked ? "none" : `1.5px solid ${color}AA`,
      background: checked ? color : "transparent",
      display: "flex", alignItems: "center", justifyContent: "center",
      transition: "all 0.15s ease",
    }}>
      {checked && <span style={{ color: "#0A0E1A", fontSize: size * 0.6, fontWeight: 800, lineHeight: 1 }}>✓</span>}
    </div>
  );
}

// person avatar — initial in colored circle (better than emoji per my notes)
function Avatar({ person, size = 28, active = false }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: "50%",
      background: `${person.color}28`,
      border: `1.5px solid ${active ? person.color : `${person.color}55`}`,
      display: "flex", alignItems: "center", justifyContent: "center",
      fontSize: size * 0.42, fontWeight: 800, color: person.color, flexShrink: 0,
      transition: "all 0.2s ease",
    }}>{person.short}</div>
  );
}

Object.assign(window, { theme, phases, people, tasksSeed, packingSeed, trip, Phone, Check, Avatar });
