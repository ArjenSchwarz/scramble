# T-2459 verification record

## Final source checks

The app and test Swift files stayed byte-identical through the final focused run,
the single full run, and publication. No source changes followed those runs.

| Run | Result |
| --- | --- |
| Focused final (fix + review refinements) | 21 declarations passed; zero failures/skips; 34 executions including dynamic parameters. `make` exit 0. |
| Single full suite | 806 passed, 38 failed, 12 skipped (856 declarations); all unit suites passed. `make` exit 2 / xcodebuild exit 65. |
| One baseline retry, source `0a37052721da3b5bd0c8a0a99e019ab82511dc8f` | All 38 failed UI methods failed again; zero passes. Native suite duration 580.604 seconds. Xcode stalled in bundle finalisation for over three minutes; only the runner was terminated after native completion. The complete log establishes all 38 failures; the baseline xcresult is incomplete. `make` returned 2 after xcodebuild was terminated (143). |
| Strict lint | `swiftlint lint --strict --no-cache`: zero violations across 228 files. |

Native full-suite UI totals were 27 passed, 38 failed, nine skipped. The new packing
lifecycle regression passed both focused and full runs. The live CloudKit harness
was skipped. No live trip store or cloud mutation was part of verification.

## Full and baseline failure comparison

| Existing UI class | Failed in full run | Failed on unchanged baseline |
| --- | ---: | ---: |
| `ColdLaunchSequencingUITests` | 1 | 1 |
| `PackingSheetUITests` | 12 | 12 |
| `PackingSubItemsUITests` | 1 | 1 |
| `PersonDeletionGuardUITests` | 1 | 1 |
| `Phase5MigrationStateUITests` | 2 | 2 |
| `Phase5SharingUITests` | 6 | 6 |
| `RootNavigationUITests` | 3 | 3 |
| `RulesEnginePopulationUITests` | 2 | 2 |
| `TimelineAndTaskUITests` | 7 | 7 |
| `TripCRUDUITests` | 2 | 2 |
| `TripEditorPickerReactivityUITests` | 1 | 1 |

These are pre-existing UI check failures. The legacy trip fixtures seed globals
while today’s Trips UI reads tripsLocal; several tests fail before reaching their
intended interaction. Migration/sharing and picker checks also fail on baseline.
Their individual root causes were not expanded into this sync bugfix. No unrelated
tickets were created and no failing expectations were weakened.

### Exact failed UI selectors

- `ScrambleUITests/ColdLaunchSequencingUITests/testColdLaunchScanCompletesBeforeAutoOpen`
- `ScrambleUITests/PackingSheetUITests/testAddManualItemAppearsInUnpacked`
- `ScrambleUITests/PackingSheetUITests/testInnerFormSwipeDownKeepsPackingSheet`
- `ScrambleUITests/PackingSheetUITests/testLeftBehindRowIsReadOnly`
- `ScrambleUITests/PackingSheetUITests/testPackModeCheckboxTogglesState`
- `ScrambleUITests/PackingSheetUITests/testPackingSummaryRendersInDayBeforePhase`
- `ScrambleUITests/PackingSheetUITests/testPhaseSublineCombined`
- `ScrambleUITests/PackingSheetUITests/testRenameViaSwipe`
- `ScrambleUITests/PackingSheetUITests/testRepackOpensFromDayBeforeReturn`
- `ScrambleUITests/PackingSheetUITests/testRestoreReverses`
- `ScrambleUITests/PackingSheetUITests/testSheetCounterIncludesDimmed`
- `ScrambleUITests/PackingSheetUITests/testSkipMovesItemToNotBringing`
- `ScrambleUITests/PackingSheetUITests/testTappingSummaryRowOpensSheet`
- `ScrambleUITests/PackingSubItemsUITests/testAddRemoveAndReadOnlySubItem`
- `ScrambleUITests/PersonDeletionGuardUITests/testPersonOwningMasterPackingItemCannotBeDeleted`
- `ScrambleUITests/Phase5MigrationStateUITests/testFailedMigrationRowAppearsInRetryBanner`
- `ScrambleUITests/Phase5MigrationStateUITests/testStageBInProgressTripShowsSyncingBadge`
- `ScrambleUITests/Phase5SharingUITests/testOwnerSideTapPresentsManageParticipantsAffordance`
- `ScrambleUITests/Phase5SharingUITests/testParticipantsSectionDisplayNameFallbackChain`
- `ScrambleUITests/Phase5SharingUITests/testParticipantsSectionDistinguishesPendingFromAccepted`
- `ScrambleUITests/Phase5SharingUITests/testParticipantsSectionIsReadOnlyForParticipants`
- `ScrambleUITests/Phase5SharingUITests/testShareButtonHiddenForParticipant`
- `ScrambleUITests/Phase5SharingUITests/testShareButtonVisibleForOwner`
- `ScrambleUITests/RootNavigationUITests/testAutoOpenDoesNotRefireOnTabSwitch`
- `ScrambleUITests/RootNavigationUITests/testColdLaunchOneQualifyingTripAutoOpensDetail`
- `ScrambleUITests/RootNavigationUITests/testTabBarHiddenOnDetailRestoredOnPop`
- `ScrambleUITests/RulesEnginePopulationUITests/testCreateTripPopulatesMatchingMasterPackingItem`
- `ScrambleUITests/RulesEnginePopulationUITests/testEditTripAttributesPopulatesMatchingMasterPackingItem`
- `ScrambleUITests/TimelineAndTaskUITests/testAccordionAutoExpandsCurrentPhase`
- `ScrambleUITests/TimelineAndTaskUITests/testAssigneePickerEmptyParticipants`
- `ScrambleUITests/TimelineAndTaskUITests/testCheckboxToggleAndStrikethrough`
- `ScrambleUITests/TimelineAndTaskUITests/testManualTaskAddPersistsAcrossLaunch`
- `ScrambleUITests/TimelineAndTaskUITests/testOnlyOnePhaseExpandedAtATime`
- `ScrambleUITests/TimelineAndTaskUITests/testRuleDeletionPersistsAcrossReevaluation`
- `ScrambleUITests/TimelineAndTaskUITests/testSwipeRevealsEditAndDelete`
- `ScrambleUITests/TripCRUDUITests/testDeleteTripRemovesItFromList`
- `ScrambleUITests/TripCRUDUITests/testEditTripAttributesUpdatesChips`
- `ScrambleUITests/TripEditorPickerReactivityUITests/testNewPersonCreatedInlineAppearsInPickerWithoutLeavingEditor`

## Reproduction commands

Focused final:

```sh
make test SIMULATOR='Scramble Packing Regression 20261015,OS=27.0' XCBEAUTIFY= \
  TEST_ARGS='-parallel-testing-enabled NO -only-testing:ScrambleTests/TripSyncEngineTests -only-testing:ScrambleUITests/PackingSheetUITests/testRepeatedPackingTogglesPreserveTripAcrossForeground'
```

Required full run (executed once):

```sh
make test SIMULATOR='Scramble Packing Regression 20261015,OS=27.0' XCBEAUTIFY= \
  TEST_ARGS='-parallel-testing-enabled NO -resultBundlePath /tmp/scramble-full-final.xcresult'
```

The baseline retry used the same dedicated empty simulator, baseline app/test source,
and only the 38 selectors above. Its sole checkout modification added `$(TEST_ARGS)`
forwarding to Makefile test recipes; no app or test code was changed. The exact
argument vector is retained at `/tmp/scramble-review-inputs/baseline-retry-command.json`.

## Retained local evidence

- Focused result: `DerivedData/Logs/Test/Test-Scramble-2026.10.15_10-15-25-+1100.xcresult`.
- Full result and log: `/tmp/scramble-full-final.xcresult`, `/tmp/scramble-full-final.log`.
- Baseline complete native log: `/tmp/scramble-baseline-retry.log`; `/tmp/scramble-baseline-retry.xcresult` is incomplete after stalled bundle finalisation and is not used as structured evidence.
- Structured results, JUnit conversion and source hashes: `/tmp/scramble-review-inputs/`.

## Unrun and unproven

- Physical-device and live CloudKit validation were not run.
- Historical last-trip deletion, its triggering event, and data recovery remain unproven.
- The fix prevents the reproduced foreign-zone local deletion; it is not a recovery operation.
