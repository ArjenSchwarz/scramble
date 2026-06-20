import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Target-person picker for copying a single `MasterPackingItem` to other
/// people (Req 1.2). Presentation only: it owns the multi-select state and
/// passes the RAW selected ids to `onCopy` — `MasterPersistence.copyPacking`
/// is the sole authority that drops ineligible / raced-out targets, so the
/// sheet never re-filters on confirm (design "Components and Interfaces").
///
/// Eligibility for display is read off `Person.masterPackingItems` via the
/// SAME `MasterPersistence.normalizedName` comparator the persistence skip
/// uses, so the picker display and the confirm-time skip agree.
@MainActor struct CopyPackingItemSheet: View {
  let source: MasterPackingItem
  /// Raw selected person ids; the parent (`MasterPackingList.performCopy`)
  /// does the work and `copyPacking` re-checks eligibility.
  let onCopy: ([UUID]) -> Void
  let onCancel: () -> Void

  @Query(sort: \Person.name) private var allPeople: [Person]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @State private var selected: Set<UUID> = []

  /// Eligible target people for a copy of `source`: everyone EXCEPT the source
  /// owner (2.1), MINUS anyone who already owns a same-name item (2.3). Uses
  /// `MasterPersistence.normalizedName` — the same comparator `copyPacking`
  /// applies — over each person's `masterPackingItems` relationship, the same
  /// data path the persistence skip reads.
  static func eligibleTargets(source: MasterPackingItem, people: [Person]) -> [Person] {
    let ownerID = source.person?.id
    let sourceKey = MasterPersistence.normalizedName(source.name)
    return people.filter { person in
      guard person.id != ownerID else { return false }
      let alreadyOwns = (person.masterPackingItems ?? []).contains {
        MasterPersistence.normalizedName($0.name) == sourceKey
      }
      return !alreadyOwns
    }
  }

  /// People rendered in the picker: everyone except the owner, sorted by name
  /// (2.1). Ineligible (same-name owner) people stay in the list but disabled.
  private var targetPeople: [Person] {
    allPeople.filter { $0.id != source.person?.id }
  }

  private var eligibleIDs: Set<UUID> {
    Set(Self.eligibleTargets(source: source, people: allPeople).map(\.id))
  }

  private var hasEligibleTarget: Bool {
    !eligibleIDs.isEmpty
  }

  /// Confirm enabled only when at least one *eligible* person is selected
  /// (2.4). Intersecting against `eligibleIDs` means a stale selection of a
  /// since-ineligible person cannot enable the button.
  private var canConfirm: Bool {
    !selected.isDisjoint(with: eligibleIDs)
  }

  var body: some View {
    NavigationStack {
      Group {
        if hasEligibleTarget {
          peopleList
        } else {
          emptyState
        }
      }
      .navigationTitle("Copy “\(source.name)”")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { onCancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Copy") { confirm() }
            .disabled(!canConfirm)
            .accessibilityLabel("Copy item to selected people")
            #if DEBUG
              .accessibilityIdentifier("copyPacking.confirm")
            #endif
        }
      }
    }
  }

  // MARK: - Subviews

  private var peopleList: some View {
    let variant = theme.variant(for: colorScheme)
    return List {
      Section {
        ForEach(targetPeople) { person in
          row(for: person, variant: variant)
        }
      } footer: {
        Text("Already-owned items are skipped.")
      }
    }
    .listStyle(.insetGrouped)
  }

  @ViewBuilder
  private func row(for person: Person, variant: ThemeVariant) -> some View {
    let isEligible = eligibleIDs.contains(person.id)
    let isSelected = selected.contains(person.id)

    Button {
      toggle(person.id)
    } label: {
      HStack {
        Text(person.name.isEmpty ? "Unnamed" : person.name)
          .foregroundStyle(isEligible ? variant.textPrimary : variant.textSecondary)
        Spacer()
        if !isEligible {
          Text("already has it")
            .font(.footnote)
            .foregroundStyle(variant.textSecondary)
        } else if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(variant.accent)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEligible)
    .accessibilityValue(isEligible ? "" : "already has this item")
    #if DEBUG
      .accessibilityIdentifier("copyPacking.person.\(person.name)")
    #endif
  }

  private var emptyState: some View {
    ContentUnavailableView(
      "No one else needs this",
      systemImage: "checkmark.circle",
      description: Text("Everyone else already has an item named “\(source.name)”.")
    )
    #if DEBUG
      .accessibilityIdentifier("copyPacking.emptyState")
    #endif
  }

  // MARK: - Interaction

  private func toggle(_ id: UUID) {
    if selected.contains(id) {
      selected.remove(id)
    } else {
      selected.insert(id)
    }
  }

  private func confirm() {
    // Pass the RAW selected ids; copyPacking is the sole authority that drops
    // ineligible / raced-out targets (design "Components and Interfaces").
    onCopy(Array(selected))
  }
}
