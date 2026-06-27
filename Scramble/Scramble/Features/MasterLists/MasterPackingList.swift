import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// AC 2.1 — list every `MasterPackingItem` grouped by `Person`, sorted by
/// `Person.name` ascending, people with zero items omitted, per-person count
/// in the header. AC 2.7 — when no `Person` exists, show empty state and hide
/// the "+ Add item" affordance.
///
/// Copy feature: each eligible row also exposes a "Copy to people…" action via
/// a trailing swipe + long-press context menu (Decision 7 — net-new UI; the
/// whole-row tap still opens the editor). Confirming the picker runs the
/// save → engine → toast sequence in `performCopy`.
@MainActor struct MasterPackingList: View {
  @Query(sort: \MasterPackingItem.name) private var allItems: [MasterPackingItem]
  @Query(sort: \Person.name) private var allPeople: [Person]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext
  @Environment(\.tripsLocalContainer) private var tripsLocalContainer
  @Environment(\.localWriteHook) private var hook

  @State private var sheetTarget: SheetTarget?
  @State private var toastMessage: String?

  /// 5s (vs the app-wide 3s default) is deliberate so the post-copy
  /// confirmation isn't lost while the picker sheet finishes dismissing.
  private static let copyToastDuration: TimeInterval = 5

  enum SheetTarget: Identifiable, Hashable {
    case create
    case edit(PersistentIdentifier)
    case copy(PersistentIdentifier)

    var id: AnyHashable {
      switch self {
      case .create: AnyHashable("create")
      case .edit(let id): AnyHashable(id)
      // The "copy-" prefix is load-bearing: it keeps `.copy(x)` and `.edit(x)`
      // from resolving to the same `.sheet(item:)` identity for one item id.
      // Without it, presenting an edit sheet then a copy sheet for the same
      // item would reuse the prior identity and the copy sheet wouldn't show.
      case .copy(let id): AnyHashable("copy-\(id)")
      }
    }
  }

  var body: some View {
    if allPeople.isEmpty {
      ContentUnavailableView(
        "No people yet",
        systemImage: "person.crop.circle.badge.plus",
        description: Text(
          "Add a person to a trip first, then return here to define their packing items."
        )
      )
    } else {
      let variant = theme.variant(for: colorScheme)
      let grouped = Dictionary(grouping: allItems) { $0.person?.id }

      List {
        ForEach(allPeople) { person in
          let items = grouped[person.id] ?? []
          if !items.isEmpty {
            // Sub-group within the person by category, ordering consistent with
            // the Packing Sheet (uncategorised last, same collation). A person
            // with no categorised item is a single `key == nil` / `label == nil`
            // section, so its rows render flat with no sub-header (Req 6.2);
            // pre-existing/never-categorised items land in that bucket (Req 1.4).
            let sections = PackingListHelpers.categorySections(
              items,
              category: \.category,
              sortWithin: { items in items.sorted { byName($0, $1) } }
            )
            Section {
              ForEach(sections, id: \.key) { section in
                if let label = section.label {
                  Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                }
                ForEach(section.items) { item in
                  itemRow(item, variant: variant)
                }
              }
            } header: {
              HStack {
                Text(person.name.isEmpty ? "Unnamed" : person.name)
                Spacer()
                Text("\(items.count)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Section {
          DashedAddButton(title: "Add item", accent: variant.accent) {
            sheetTarget = .create
          }
        }
      }
      .listStyle(.insetGrouped)
      .sheet(item: $sheetTarget) { target in
        sheet(for: target)
      }
      .transientToast(message: $toastMessage, duration: Self.copyToastDuration)
    }
  }

  // MARK: - Rows

  /// Case-insensitive ascending name order with an `id` tiebreak — the same
  /// name tier the Packing Sheet uses (`PackingListHelpers.sorted`), so a
  /// category's items collate identically across both surfaces.
  private func byName(_ lhs: MasterPackingItem, _ rhs: MasterPackingItem) -> Bool {
    let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    if order != .orderedSame { return order == .orderedAscending }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  @ViewBuilder
  private func itemRow(_ item: MasterPackingItem, variant: ThemeVariant) -> some View {
    let canCopy = isCopyEligible(item)
    Button {
      sheetTarget = .edit(item.persistentModelID)
    } label: {
      Text(item.name.isEmpty ? "Unnamed item" : item.name)
        .foregroundStyle(variant.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if canCopy {
        Button {
          sheetTarget = .copy(item.persistentModelID)
        } label: {
          Label("Copy to people…", systemImage: "person.2")
        }
        .tint(variant.accent)
      }
    }
    .contextMenu {
      if canCopy {
        Button {
          sheetTarget = .copy(item.persistentModelID)
        } label: {
          Label("Copy to people…", systemImage: "person.2")
        }
      }
    }
    #if DEBUG
      .accessibilityIdentifier("masterPacking.itemRow.\(item.name)")
    #endif
  }

  /// Source eligibility for the copy action (Req 1.3 / Decision 6): at least
  /// two people exist, the source has an owner, and its trimmed name is
  /// non-empty. Computes the three inputs and delegates to the pure decision.
  private func isCopyEligible(_ item: MasterPackingItem) -> Bool {
    Self.isCopyEligible(
      trimmedName: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
      hasOwner: item.person != nil,
      peopleCount: allPeople.count
    )
  }

  /// Pure copy-eligibility decision (Req 1.3 / Decision 6), extracted so it is
  /// unit-testable without SwiftData: at least two people exist, the source has
  /// an owner, and its (already-trimmed) name is non-empty.
  nonisolated static func isCopyEligible(
    trimmedName: String,
    hasOwner: Bool,
    peopleCount: Int
  ) -> Bool {
    guard peopleCount >= 2 else { return false }
    guard hasOwner else { return false }
    return !trimmedName.isEmpty
  }

  // MARK: - Sheet

  @ViewBuilder
  private func sheet(for target: SheetTarget) -> some View {
    switch target {
    case .create:
      MasterPackingEditor(mode: .create)
    case .edit(let id):
      if let item = allItems.first(where: { $0.persistentModelID == id }) {
        MasterPackingEditor(mode: .edit(item))
      }
    case .copy(let id):
      // An unresolved `.copy` id (source deleted / owner changed between row
      // tap and presentation) renders nothing; dismissing writes nothing.
      if let item = allItems.first(where: { $0.persistentModelID == id }) {
        CopyPackingItemSheet(
          source: item,
          onCopy: { ids in
            sheetTarget = nil
            performCopy(source: item, toPersonIDs: ids)
          },
          onCancel: { sheetTarget = nil }
        )
      }
    }
  }

  // MARK: - Copy

  /// Branch selection of the post-`copyPacking` orchestration, extracted as a
  /// pure function so it is unit-testable without SwiftData. It owns ONLY the
  /// control flow; `performCopy` supplies the real save / run-engine closures
  /// and maps the outcome onto the rollback + toast side effects.
  enum CopyOutcome: Equatable {
    case nothingToCopy
    case saveFailed
    case copied(deferred: Bool)
  }

  /// Decides the outcome of a copy:
  /// - `createdCount == 0` → `.nothingToCopy` — calls NEITHER `save` nor
  ///   `runEngine`.
  /// - else `try save()`; on throw → `.saveFailed` — does NOT call `runEngine`.
  /// - else `try runEngine()`; on throw → `.copied(deferred: true)`.
  /// - else → `.copied(deferred: false)`.
  static func copyOutcome(
    createdCount: Int,
    save: () throws -> Void,
    runEngine: () throws -> Void
  ) -> CopyOutcome {
    guard createdCount > 0 else { return .nothingToCopy }
    do {
      try save()
    } catch {
      return .saveFailed
    }
    do {
      try runEngine()
    } catch {
      return .copied(deferred: true)
    }
    return .copied(deferred: false)
  }

  /// save → engine → toast sequence (design Flow). `copyPacking` only inserts;
  /// this method owns `save()`, the recompute, and the user-facing toast — the
  /// list stays mounted while the picker dismisses, so the toast renders here.
  /// The branch selection is delegated to the pure `copyOutcome(...)`; this
  /// method maps the outcome onto rollback + the existing toast wording.
  private func performCopy(source: MasterPackingItem, toPersonIDs ids: [UUID]) {
    // The source is captured at sheet-build time; a CloudKit sync could delete
    // it while the picker is open, so copying from a deleted model is a no-op.
    guard !source.isDeleted else { return }

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: ids,
      in: modelContext
    )

    // Materialise onto matching non-past trips (4.1). Best-effort: a top-level
    // recompute failure keeps the saved masters and surfaces the deferred-
    // update wording (4.2), mirroring MasterPackingEditor.runEngineAndDismiss.
    let runner = RulesEngineRunner(
      context: tripsLocalContainer.mainContext,
      mastersContext: modelContext,
      hook: hook
    )

    let outcome = Self.copyOutcome(
      createdCount: result.createdCount,
      save: { try modelContext.save() },
      runEngine: { _ = try runner.runForAllNonPastTrips() }
    )

    switch outcome {
    case .saveFailed:
      modelContext.rollback()
      announce("Copy failed — try again.")
    case .copied(deferred: true):
      announce("Copied. Some trips couldn't be updated — they'll sync on next launch.")
    case .nothingToCopy, .copied(deferred: false):
      // All targets skipped at confirm (3.7) reports everyone already had it;
      // a clean copy reports who received it — both via copyToastMessage.
      announce(toastMessage(for: result))
    }
  }

  private func toastMessage(for result: CopyResult) -> String {
    MasterPersistence.copyToastMessage(
      copiedNames: result.copiedNames,
      skippedNames: result.skippedNames
    )
  }

  /// Shows the toast and posts a VoiceOver announcement, matching
  /// `PackingItemRow`'s move-announcement pattern.
  private func announce(_ message: String) {
    toastMessage = message
    #if canImport(UIKit)
      UIAccessibility.post(notification: .announcement, argument: message)
    #endif
  }
}
