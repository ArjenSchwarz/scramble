// Direction A — Timeline-spine (refined)
// The trip IS the timeline. Phases are stops on a vertical journey.
// Packing lives at the Departure node and the Day-before-return node.
// Tap a person row → bottom sheet with their items in full detail.

const PHASE_DEPARTURE = 2;
const PHASE_RETURN = 4; // day before return

function DirectionA({ initialPhase = 1, initialSheet = null }) {
  const [taskDone, setTaskDone] = React.useState(tasksSeed.map(t => t.done));
  const [packState, setPackState] = React.useState(packingSeed.map(p => p.state));
  const [expandedPhase, setExpandedPhase] = React.useState(initialPhase);
  const [showWhy, setShowWhy] = React.useState(null);
  // sheet: { mode: 'pack' | 'repack', person: idx } | null
  const [sheet, setSheet] = React.useState(initialSheet);

  const currentPhase = 1;
  const phaseTasks = (i) => tasksSeed.map((t, idx) => ({ ...t, idx, done: taskDone[idx] })).filter(t => t.phase === i);
  const isPackingPhase = (i) => i === PHASE_DEPARTURE || i === PHASE_RETURN;

  const personItems = (pi) => packingSeed
    .map((p, idx) => ({ ...p, idx, state: packState[idx] }))
    .filter(p => p.person === pi);

  const updateState = (itemIdx, newState) => {
    const c = [...packState]; c[itemIdx] = newState; setPackState(c);
  };

  return (
    <Phone label="Timeline as spine">
      {/* Header */}
      <div style={{ padding: "0 20px 14px" }}>
        <div style={{ fontSize: 12, color: theme.textSec, fontWeight: 600 }}>← Trips</div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginTop: 8 }}>
          <div style={{ fontSize: 26, fontWeight: 800, letterSpacing: -0.5 }}>{trip.name}</div>
          <div style={{ fontSize: 20 }}>{trip.flag}</div>
        </div>
        <div style={{ fontSize: 12, color: theme.textSec, marginTop: 2 }}>
          {trip.startLabel} – {trip.endLabel} · in {trip.daysAway} days
        </div>
        <div style={{ display: "flex", gap: 5, marginTop: 10, flexWrap: "wrap" }}>
          {["international", "plane", "long", "sun", "leisure"].map(a => (
            <span key={a} style={{
              fontSize: 9, padding: "3px 7px", borderRadius: 6,
              background: theme.surface, border: `1px solid ${theme.border}`,
              color: theme.textSec, fontWeight: 600, letterSpacing: 0.2,
            }}>{a}</span>
          ))}
        </div>
      </div>

      {/* Timeline */}
      <div style={{ flex: 1, overflow: "auto", padding: "0 0 32px", position: "relative" }}>
        {phases.map((p, i) => {
          const tasks = phaseTasks(i);
          const phaseColor = theme.phaseColors[i];
          const isCurrent = i === currentPhase;
          const isPast = i < currentPhase;
          const isExpanded = expandedPhase === i;
          const totalDone = tasks.filter(t => t.done).length;
          const showPacking = isPackingPhase(i);
          const repackMode = i === PHASE_RETURN;

          // packing summary
          const allItems = packingSeed.map((it, idx) => ({ ...it, idx, state: packState[idx] }));
          const totalUnpacked = repackMode
            ? allItems.filter(it => it.state === "packed").length
            : allItems.filter(it => it.state === "unpacked").length;

          return (
            <div key={i} style={{ position: "relative", paddingLeft: 56 }}>
              {/* Spine line */}
              {i < phases.length - 1 && (
                <div style={{
                  position: "absolute", left: 31, top: 28, bottom: -8, width: 2,
                  background: isPast ? `${phaseColor}66` : theme.border,
                }} />
              )}
              {/* Node */}
              <div onClick={() => setExpandedPhase(isExpanded ? -1 : i)} style={{
                position: "absolute", left: 20, top: 6,
                width: 22, height: 22, borderRadius: "50%",
                background: isPast ? phaseColor : isCurrent ? phaseColor : theme.bgSolid,
                border: `2px solid ${phaseColor}`,
                display: "flex", alignItems: "center", justifyContent: "center",
                boxShadow: isCurrent ? `0 0 0 6px ${phaseColor}22, 0 0 16px ${phaseColor}55` : "none",
                cursor: "pointer", zIndex: 2,
              }}>
                {isPast && <span style={{ fontSize: 10, color: "#0A0E1A", fontWeight: 800 }}>✓</span>}
                {showPacking && !isPast && <span style={{ fontSize: 10 }}>{repackMode ? "📦" : "🧳"}</span>}
              </div>

              {/* Phase header */}
              <div onClick={() => setExpandedPhase(isExpanded ? -1 : i)} style={{
                cursor: "pointer", padding: "4px 20px 0 0",
              }}>
                <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
                  <div style={{
                    fontSize: 16, fontWeight: 700, color: isCurrent ? phaseColor : theme.text,
                    letterSpacing: -0.2,
                  }}>{p.label}</div>
                  {isCurrent && <span style={{
                    fontSize: 8, fontWeight: 800, padding: "2px 6px", borderRadius: 5,
                    background: `${phaseColor}28`, color: phaseColor, letterSpacing: 0.4,
                  }}>NOW</span>}
                </div>
                <div style={{ fontSize: 10, color: theme.textSec, marginTop: 2, display: "flex", gap: 8 }}>
                  {tasks.length > 0 && <span>{totalDone}/{tasks.length} tasks</span>}
                  {showPacking && <span>{totalUnpacked} {repackMode ? "to repack" : "to pack"}</span>}
                  {tasks.length === 0 && !showPacking && <span style={{ color: theme.textTer }}>Nothing here yet</span>}
                </div>
              </div>

              {/* Expanded content */}
              {isExpanded && (
                <div style={{ marginTop: 10, marginRight: 20, marginBottom: 18 }}>
                  {/* Tasks */}
                  {tasks.map(t => (
                    <React.Fragment key={t.idx}>
                      <div style={{
                        display: "flex", alignItems: "center", gap: 10,
                        padding: "10px 12px", marginBottom: 4,
                        background: theme.surface, borderRadius: 10,
                        border: `1px solid ${theme.border}`,
                        opacity: t.done ? 0.5 : 1,
                      }}>
                        <Check checked={t.done} color={phaseColor} size={20}
                          onClick={() => { const c = [...taskDone]; c[t.idx] = !c[t.idx]; setTaskDone(c); }} />
                        <div style={{ flex: 1 }}>
                          <div style={{ fontSize: 13, fontWeight: 500,
                            textDecoration: t.done ? "line-through" : "none" }}>{t.name}</div>
                          {t.by !== null && (
                            <div style={{ fontSize: 10, color: theme.textSec, marginTop: 2,
                              display: "flex", alignItems: "center", gap: 4 }}>
                              <Avatar person={people[t.by]} size={14} />
                              <span>{people[t.by].name}</span>
                            </div>
                          )}
                        </div>
                        <div onClick={() => setShowWhy(showWhy === `t-${t.idx}` ? null : `t-${t.idx}`)} style={{
                          width: 18, height: 18, borderRadius: "50%",
                          border: `1px solid ${theme.borderHi}`,
                          display: "flex", alignItems: "center", justifyContent: "center",
                          fontSize: 10, color: theme.textSec, cursor: "pointer", fontWeight: 700,
                        }}>?</div>
                      </div>
                      {showWhy === `t-${t.idx}` && (
                        <div style={{
                          padding: "8px 12px", marginBottom: 6,
                          background: `${phaseColor}14`, border: `1px solid ${phaseColor}33`,
                          borderRadius: 8, fontSize: 11, color: theme.text,
                        }}>
                          <div style={{ fontSize: 9, color: phaseColor, fontWeight: 700, letterSpacing: 0.4,
                            textTransform: "uppercase", marginBottom: 3 }}>Why is this here?</div>
                          Added by rule: <strong>{t.why.join(", ")}</strong>
                        </div>
                      )}
                    </React.Fragment>
                  ))}

                  {/* Packing block — at Departure or Day-before-return */}
                  {showPacking && (
                    <>
                      <div style={{ display: "flex", alignItems: "center", gap: 6,
                        margin: tasks.length > 0 ? "12px 4px 6px" : "2px 4px 6px" }}>
                        <span style={{ fontSize: 10, fontWeight: 700, color: theme.textSec,
                          letterSpacing: 0.5, textTransform: "uppercase" }}>
                          {repackMode ? "Repack" : "Packing"}
                        </span>
                        <span style={{ fontSize: 9, color: theme.textTer }}>· tap a person</span>
                      </div>
                      {people.map((person, pi) => {
                        const items = personItems(pi);
                        const considered = items.filter(it => it.state !== "excluded");
                        let done, total, label;
                        if (repackMode) {
                          const packed = considered.filter(it => it.state === "packed" || it.state === "repacked");
                          done = considered.filter(it => it.state === "repacked").length;
                          total = packed.length;
                          label = total === 0 ? "—" : done === total ? "✓ all back in" : `${total - done} to repack`;
                        } else {
                          done = considered.filter(it => it.state === "packed").length;
                          total = considered.length;
                          label = done === total ? "✓ ready" : `${total - done} to pack`;
                        }
                        const pct = total === 0 ? 0 : (done / total) * 100;
                        return (
                          <div key={pi} onClick={() => setSheet({ mode: repackMode ? "repack" : "pack", person: pi })} style={{
                            display: "flex", alignItems: "center", gap: 10,
                            padding: "10px 12px", marginBottom: 4,
                            background: theme.surface, borderRadius: 10,
                            border: `1px solid ${theme.border}`,
                            cursor: "pointer",
                          }}>
                            <Avatar person={person} size={26} />
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontSize: 13, fontWeight: 600 }}>{person.name}</div>
                              <div style={{ marginTop: 4, height: 3, borderRadius: 2, background: theme.border }}>
                                <div style={{ width: `${pct}%`, height: "100%", borderRadius: 2,
                                  background: pct === 100 ? theme.check : person.color,
                                  transition: "width 0.3s ease" }} />
                              </div>
                            </div>
                            <div style={{ fontSize: 10, color: pct === 100 ? theme.check : theme.textSec,
                              fontWeight: 700, whiteSpace: "nowrap" }}>{label}</div>
                            <span style={{ fontSize: 14, color: theme.textTer, marginLeft: 2 }}>›</span>
                          </div>
                        );
                      })}
                    </>
                  )}
                </div>
              )}
              {!isExpanded && <div style={{ height: 14 }} />}
            </div>
          );
        })}
      </div>

      {/* Bottom sheet — packing/repacking detail per person */}
      {sheet !== null && (
        <PackingSheet
          mode={sheet.mode}
          person={sheet.person}
          items={personItems(sheet.person)}
          onClose={() => setSheet(null)}
          onUpdate={updateState}
        />
      )}
    </Phone>
  );
}

function PackingSheet({ mode, person, items, onClose, onUpdate }) {
  const p = people[person];
  const repack = mode === "repack";
  const [whyFor, setWhyFor] = React.useState(null);

  // groups depend on mode
  const groups = repack ? [
    { key: "topack", title: "Still in suitcase", color: theme.warn,
      filter: it => it.state === "packed" },
    { key: "repacked", title: "Back in suitcase", color: theme.check,
      filter: it => it.state === "repacked" },
    { key: "left", title: "Left behind", color: theme.textTer,
      filter: it => it.state === "unpacked" || it.state === "excluded" },
  ] : [
    { key: "todo", title: "Still need to pack", color: theme.warn,
      filter: it => it.state === "unpacked" },
    { key: "done", title: "Packed", color: theme.check,
      filter: it => it.state === "packed" },
    { key: "no", title: "Not bringing", color: theme.textTer,
      filter: it => it.state === "excluded" },
  ];

  const total = items.filter(it => it.state !== "excluded").length;
  const done = repack
    ? items.filter(it => it.state === "repacked").length
    : items.filter(it => it.state === "packed").length;

  return (
    <>
      {/* backdrop */}
      <div onClick={onClose} style={{
        position: "absolute", inset: 0, background: "rgba(0,0,0,0.55)",
        backdropFilter: "blur(2px)", zIndex: 100,
      }} />
      {/* sheet */}
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0,
        height: "82%", background: theme.bg,
        borderTopLeftRadius: 26, borderTopRightRadius: 26,
        zIndex: 101, display: "flex", flexDirection: "column",
        boxShadow: "0 -20px 60px rgba(0,0,0,0.6)",
        border: `1px solid ${theme.borderHi}`, borderBottom: "none",
      }}>
        {/* grabber */}
        <div style={{ display: "flex", justifyContent: "center", padding: "10px 0 4px" }}>
          <div style={{ width: 38, height: 5, borderRadius: 3, background: "rgba(255,255,255,0.25)" }} />
        </div>
        {/* sheet header */}
        <div style={{ padding: "8px 20px 14px", display: "flex", alignItems: "center", gap: 12,
          borderBottom: `1px solid ${theme.border}` }}>
          <Avatar person={p} size={36} active />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 17, fontWeight: 800 }}>{p.name}</div>
            <div style={{ fontSize: 11, color: theme.textSec }}>
              {repack ? `${done}/${total} repacked` : `${done}/${total} packed`}
            </div>
          </div>
          <div onClick={onClose} style={{
            width: 30, height: 30, borderRadius: "50%", background: theme.surface,
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 14, color: theme.textSec, cursor: "pointer", fontWeight: 700,
          }}>✕</div>
        </div>

        {/* item groups */}
        <div style={{ flex: 1, overflow: "auto", padding: "12px 20px 20px" }}>
          {groups.map(g => {
            const list = items.filter(g.filter);
            if (list.length === 0) return null;
            return (
              <div key={g.key} style={{ marginBottom: 18 }}>
                <div style={{ fontSize: 9, fontWeight: 800, letterSpacing: 0.8,
                  textTransform: "uppercase", color: g.color, marginBottom: 6 }}>
                  {g.title} · {list.length}
                </div>
                <div style={{ background: theme.surface, borderRadius: 12,
                  border: `1px solid ${theme.border}`, overflow: "hidden" }}>
                  {list.map((it, idx) => {
                    // determine "checked" state and toggle target per mode
                    let checked, color, nextState, prevState;
                    if (repack) {
                      checked = it.state === "repacked";
                      color = theme.check;
                      nextState = "repacked"; prevState = "packed";
                    } else {
                      checked = it.state === "packed";
                      color = checked ? theme.check : p.color;
                      nextState = "packed"; prevState = "unpacked";
                    }
                    const isExcluded = it.state === "excluded";
                    const isLeftBehind = repack && (it.state === "unpacked" || it.state === "excluded");
                    return (
                      <React.Fragment key={it.idx}>
                        <div style={{
                          display: "flex", alignItems: "center", gap: 12,
                          padding: "11px 14px",
                          borderBottom: idx < list.length - 1 ? `1px solid ${theme.border}` : "none",
                          opacity: isExcluded || isLeftBehind ? 0.5 : 1,
                        }}>
                          {!isExcluded && !isLeftBehind ? (
                            <Check checked={checked} color={color} size={20}
                              onClick={() => onUpdate(it.idx, checked ? prevState : nextState)} />
                          ) : (
                            <div style={{ width: 20, height: 20, borderRadius: 5,
                              border: `1.5px dashed ${theme.textTer}`, flexShrink: 0 }} />
                          )}
                          <div style={{ flex: 1 }}>
                            <div style={{ fontSize: 14, fontWeight: 500,
                              textDecoration: checked ? "line-through" : "none",
                              color: theme.text }}>{it.name}</div>
                            {it.why.length > 0 && (
                              <div style={{ fontSize: 10, color: theme.textSec, marginTop: 2,
                                fontStyle: "italic" }}>{it.why.join(", ")}</div>
                            )}
                          </div>
                          {!isExcluded && !repack && (
                            <div onClick={() => onUpdate(it.idx, "excluded")} style={{
                              fontSize: 10, color: theme.textTer, cursor: "pointer",
                              padding: "4px 6px",
                            }}>skip</div>
                          )}
                          {isExcluded && !repack && (
                            <div onClick={() => onUpdate(it.idx, "unpacked")} style={{
                              fontSize: 10, color: theme.accent, cursor: "pointer",
                              padding: "4px 6px", fontWeight: 600,
                            }}>restore</div>
                          )}
                          <div onClick={() => setWhyFor(whyFor === it.idx ? null : it.idx)} style={{
                            width: 20, height: 20, borderRadius: "50%",
                            border: `1px solid ${theme.borderHi}`,
                            display: "flex", alignItems: "center", justifyContent: "center",
                            fontSize: 11, color: theme.textSec, cursor: "pointer", fontWeight: 700,
                          }}>?</div>
                        </div>
                        {whyFor === it.idx && (
                          <div style={{ padding: "8px 14px", background: `${p.color}10`,
                            borderBottom: `1px solid ${theme.border}`,
                            fontSize: 11, color: theme.text }}>
                            <div style={{ fontSize: 9, color: p.color, fontWeight: 700,
                              letterSpacing: 0.5, textTransform: "uppercase", marginBottom: 3 }}>
                              Why is this here?
                            </div>
                            {it.why.length > 0
                              ? <span>From rule: <strong>{it.why.join(" + ")}</strong></span>
                              : <span style={{ color: theme.textSec }}>You added this manually for this trip.</span>}
                          </div>
                        )}
                      </React.Fragment>
                    );
                  })}
                </div>
              </div>
            );
          })}

          {/* add item */}
          {!repack && (
            <div style={{
              padding: "11px 14px", borderRadius: 12,
              border: `1.5px dashed ${theme.borderHi}`,
              fontSize: 12, color: theme.textSec, textAlign: "center", fontWeight: 600,
              cursor: "pointer",
            }}>+ Add item for {p.name}</div>
          )}
        </div>
      </div>
    </>
  );
}

window.DirectionA = DirectionA;
