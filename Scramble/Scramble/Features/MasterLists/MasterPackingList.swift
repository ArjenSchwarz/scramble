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
            Section {
              ForEach(items) { item in
                itemRow(item, variant: variant)
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
      // 5s (vs the app-wide 3s default) is deliberate so the post-copy
      // confirmation isn't lost while the picker sheet finishes dismissing.
      .transientToast(message: $toastMessage, duration: 5)
    }
  }

  // MARK: - Rows

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
  /// non-empty.
  private func isCopyEligible(_ item: MasterPackingItem) -> Bool {
    guard allPeople.count >= 2 else { return false }
    guard item.person != nil else { return false }
    return !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

  /// save → engine → toast sequence (design Flow). `copyPacking` only inserts;
  /// this method owns `save()`, the recompute, and the user-facing toast — the
  /// list stays mounted while the picker dismisses, so the toast renders here.
  private func performCopy(source: MasterPackingItem, toPersonIDs ids: [UUID]) {
    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: ids,
      in: modelContext
    )

    // All targets skipped at confirm (3.7): no save, no engine run — report
    // that everyone already had it.
    guard result.createdCount > 0 else {
      announce(toastMessage(for: result))
      return
    }

    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      announce("Copy failed — try again.")
      return
    }

    // Materialise onto matching non-past trips (4.1). Best-effort: a top-level
    // recompute failure keeps the saved masters and surfaces the deferred-
    // update wording (4.2), mirroring MasterPackingEditor.runEngineAndDismiss.
    let runner = RulesEngineRunner(
      context: tripsLocalContainer.mainContext,
      mastersContext: modelContext,
      hook: hook
    )
    do {
      _ = try runner.runForAllNonPastTrips()
    } catch {
      announce("Copied. Some trips couldn't be updated — they'll sync on next launch.")
      return
    }

    announce(toastMessage(for: result))
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
