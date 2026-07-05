---
references:
    - smolspec.md
    - decision_log.md
---
# Task Row Text Alignment

- [x] 1. Task name centres with its checkbox in TaskRow <!-- id:iczxcb3 -->
  - In Scramble/Scramble/Components/TaskRow.swift, the task name Text gains a 44pt minimum height so a single-line name sits vertically centred with the checkbox (mirroring PackingItemRow.nameColumn).
  - Verify: the Text(task.name) frame includes minHeight: 44 and a single-line name renders level with the checkbox circle.
  - See smolspec.md Implementation Approach.
  - References: smolspec.md

- [x] 2. Project builds and lint/format pass with the change <!-- id:iczxcb4 -->
  - make build succeeds and swiftlint + swift-format report no new issues on the change.
  - Verify: make build is green; make lint and make format are clean (or no-op if tools absent).
  - Blocked-by: iczxcb3 (Task name centres with its checkbox in TaskRow)
  - References: smolspec.md

- [-] 3. Alignment visually confirmed in simulator <!-- id:iczxcb5 -->
  - Run in the simulator and confirm a single-line task name is vertically centred with its checkbox and matches the packing row.
  - Confirm a multi-line task name still wraps top-aligned, the WhyDisclosure (long-press) still sits beneath the name, and the assignee avatar and tap targets are unchanged.
  - See smolspec.md Requirements.
  - Blocked-by: iczxcb4 (Project builds and lint/format pass with the change)
  - References: smolspec.md
