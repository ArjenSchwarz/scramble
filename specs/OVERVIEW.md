# Specs Overview

| Name | Creation Date | Status | Summary |
|------|---------------|--------|---------|
| [Phase 1 Foundation](#phase-1-foundation) | 2026-05-11 | Done | SwiftData model, theme system, app shell, and Trip CRUD foundation for later phases. |
| [Phase 2 Rules Engine](#phase-2-rules-engine) | 2026-05-12 | Done | Deterministic rules engine and Master Lists tab that auto-populate and re-evaluate trip items. |
| [Phase 3 Timeline Tasks](#phase-3-timeline-tasks) | 2026-05-14 | Done | Trip Detail timeline accordion plus tasks list with explainability and short-trip compression. |
| [Phase 4 Packing Sheet](#phase-4-packing-sheet) | 2026-05-15 | Done | Per-person packing summary block and bottom sheet with pack and repack modes. |
| [Phase 5 CloudKit Sharing](#phase-5-cloudkit-sharing) | 2026-05-17 | Done | Per-trip CKShare via custom zones, SchemaV3 snapshots, and silent-push subscriptions. |
| [Phase 5.1 Wire Trip Crud Tripslocal](#phase-5.1-wire-trip-crud-tripslocal) | 2026-05-17 | Planned | Route Trip CRUD reads and writes through `tripsLocal` so the sync pipeline carries edits. |

---

## Phase 1 Foundation

SwiftData model, theme system, app shell, and Trip CRUD foundation for later phases.

- [decision_log.md](phase-1-foundation/decision_log.md)
- [design.md](phase-1-foundation/design.md)
- [implementation.md](phase-1-foundation/implementation.md)
- [requirements.md](phase-1-foundation/requirements.md)
- [tasks.md](phase-1-foundation/tasks.md)

## Phase 2 Rules Engine

Deterministic rules engine and Master Lists tab that auto-populate and re-evaluate trip items.

- [decision_log.md](phase-2-rules-engine/decision_log.md)
- [design.md](phase-2-rules-engine/design.md)
- [implementation.md](phase-2-rules-engine/implementation.md)
- [requirements.md](phase-2-rules-engine/requirements.md)
- [tasks.md](phase-2-rules-engine/tasks.md)

## Phase 3 Timeline Tasks

Trip Detail timeline accordion plus tasks list with explainability and short-trip compression.

- [decision_log.md](phase-3-timeline-tasks/decision_log.md)
- [design.md](phase-3-timeline-tasks/design.md)
- [requirements.md](phase-3-timeline-tasks/requirements.md)
- [tasks.md](phase-3-timeline-tasks/tasks.md)

## Phase 4 Packing Sheet

Per-person packing summary block and bottom sheet with pack and repack modes.

- [decision_log.md](phase-4-packing-sheet/decision_log.md)
- [design.md](phase-4-packing-sheet/design.md)
- [implementation.md](phase-4-packing-sheet/implementation.md)
- [requirements.md](phase-4-packing-sheet/requirements.md)
- [tasks.md](phase-4-packing-sheet/tasks.md)

## Phase 5 CloudKit Sharing

Per-trip CKShare via custom zones, SchemaV3 snapshots, and silent-push subscriptions.

- [decision_log.md](phase-5-cloudkit-sharing/decision_log.md)
- [design.md](phase-5-cloudkit-sharing/design.md)
- [implementation.md](phase-5-cloudkit-sharing/implementation.md)
- [prerequisites.md](phase-5-cloudkit-sharing/prerequisites.md)
- [requirements.md](phase-5-cloudkit-sharing/requirements.md)
- [tasks.md](phase-5-cloudkit-sharing/tasks.md)

## Phase 5.1 Wire Trip Crud Tripslocal

Route Trip CRUD reads and writes through `tripsLocal` so the sync pipeline carries edits.

- [decision_log.md](phase-5.1-wire-trip-crud-tripslocal/decision_log.md)
- [design.md](phase-5.1-wire-trip-crud-tripslocal/design.md)
- [requirements.md](phase-5.1-wire-trip-crud-tripslocal/requirements.md)
- [tasks.md](phase-5.1-wire-trip-crud-tripslocal/tasks.md)
