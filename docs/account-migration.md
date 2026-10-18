# Developer account migration branch

This branch prepares the namespace change from `me.nore.ig` to
`me.nore.ig.apps`. It does not transfer an App Store app, copy existing data,
provision a developer account, or migrate CloudKit records.

## Identifier inventory

| Resource | Previous | Prepared identifier |
| --- | --- | --- |
| App (Debug and Release) | `me.nore.ig.Scramble` | `me.nore.ig.apps.packing` |
| Unit tests (Debug and Release) | `me.nore.ig.ScrambleTests` | `me.nore.ig.apps.packing.tests` |
| UI tests (Debug and Release) | `me.nore.ig.ScrambleUITests` | `me.nore.ig.apps.packing.uitests` |
| CloudKit entitlement and runtime selector | `iCloud.me.nore.ig.scramble` | `iCloud.me.nore.ig.apps.packing` |
| URL type name and logging subsystem | `me.nore.ig.Scramble` | `me.nore.ig.apps.packing` |

The `scramble://` URL scheme is unchanged. There are no extension targets,
App Groups, keychain access groups, or ubiquity key-value store identifiers
configured in this project. The Makefile launch bundle ID and container test
expectations use the prepared namespace. Historical changelog entries retain
the identifiers that shipped at the time.

## Migration workflow and Xcode setup

For future account migrations, change the developer account/team in project and
all target configurations **immediately after creating the worktree, before
changing identifiers or opening the project in Xcode**. Make that first change
in the project file while Xcode is closed. Then change identifiers and open the
project to verify the intended team. This avoids automatic provisioning against
the old account while preparing a new namespace.

In this migration, cached profiles created after the simulator validation linked
`iCloud.me.nore.ig.apps.scramble` to the old team. The user considers opening
Xcode the likely trigger; this remains an inference, not proven attribution.
The user subsequently reported the proposed app identifier was unavailable too.
The approved identifier family is now `me.nore.ig.apps.packing`, with CloudKit
container `iCloud.me.nore.ig.apps.packing`. The displayed app name remains Scramble.
No registration or removal of the previous container is part of these edits.

1. Open this worktree's `Scramble/Scramble.xcodeproj`. The project-level and all
   target Debug/Release configurations now specify the user-selected team
   `4PJS97G236`. Signing remains Automatic. Confirm Xcode shows that team for
   `Scramble`, `ScrambleTests`, and `ScrambleUITests`.
2. For the app's iCloud capability, confirm CloudKit is enabled and select
   `iCloud.me.nore.ig.apps.packing` under that team. Confirm the app's
   Push Notifications capability and remote-notification background mode.
   A missing container or provisioning error needs the intended team's
   account owner to configure/authorize the corresponding resources. The
   local edits alone do not create them or establish identifier availability.
3. Review any signing changes Xcode proposes before allowing provisioning.
   Device installation and cloud acceptance are separate validation steps.
   The opt-in `SCRAMBLE_CK_HARNESS` performs cloud writes and must only be run
   deliberately after the account and development container are ready.

Changing the bundle ID gives the app a separate sandbox/defaults identity on
a device; existing installations are not upgraded in place by this ID. The
new CloudKit container is a distinct backend. No fallback to the old container
or data-copy/reset behavior has been added. Do not interpret local build or
synthetic test success as evidence of new-team signing or CloudKit access.

See [release-prep.md](release-prep.md) for the later schema deployment checklist.
That checklist is not authorization to promote a schema during local testing.

## Validation and acceptance

- Release iOS 27 simulator build passed. Its app reports bundle identifier
  `me.nore.ig.apps.packing`, displayed name Scramble, and the expected CloudKit
  simulated entitlement. Debug app and both test bundles report the identifiers
  in the inventory.
- Focused `ModelStoreEnvironmentTests`: 20 passed. Strict lint: zero violations
  in 228 files. Project/entitlement plist checks and all-eight-team settings
  validation passed.
- The user reported a successful physical-device check on the new account:
  create a trip, tick a packing item, close and reopen, and verify persistence.
  This is user-reported basic persistence acceptance, not independently verified
  CloudKit synchronisation between devices.
- Simulator build/test invocations omit provisioning-update and device-registration
  flags. Automation did not create or change developer portal resources. No data
  copy, deletion, reset or fallback to the previous container was implemented.

Device provisioning and container setup were handled by the user. Future releases
still require the [CloudKit schema deployment checklist](release-prep.md).

## Pre-merge verification

The required full simulator suite completed with **806 passed, 38 failed and
12 skipped** (856 declarations). All 38 failures exactly match the pre-existing
UI selector list in [T-2459 verification](../specs/bugfixes/trips-disappear-packing/verification.md);
none is new in this migration. All unit suites passed, including the changed
configuration expectations. The repeated packing/foreground lifecycle regression
also passed under the new bundle identifier. Failing tests were not weakened.

Xcode stalled gathering optional simulator diagnostics after native tests completed.
Only this run's diagnostic collector was stopped; xcodebuild then finalised a
readable xcresult with the exact totals above and exited 65 for the UI failures.
No tests were interrupted. Strict lint, changed-Swift formatting checks, plist
validation, identifier/team inventory and `git diff --check` passed. Verification
did not change any tracked source file. The full suite was run once.
