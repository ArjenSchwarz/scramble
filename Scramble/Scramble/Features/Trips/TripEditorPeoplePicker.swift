import SwiftData
import SwiftUI

/// Phase 5.1 — cross-container people picker for the Trip Editor.
///
/// `TripEditorView` is rooted in the `tripsLocal` container (Trips tab
/// subtree), but `Person` rows live in `globals`. SwiftUI's `@Query`
/// does not cross containers: a `@Query var allPeople: [Person]`
/// declared inside a view rooted in `tripsLocal` resolves against
/// `tripsLocal`, where no `Person` rows exist. This wrapper re-roots
/// the picker subtree to the globals container via
/// `.modelContainer(globalsContainer)`; the inner `PickerContent` then
/// reads `@Query<Person>` and writes via
/// `@Environment(\.modelContext)` — both resolve to globals.
///
/// The inline `PersonEditor` sheet inherits the picker's
/// `.modelContainer(globals)`, so its `@Environment(\.modelContext)`
/// also points at globals — no extra context plumbing needed.
@MainActor struct TripEditorPeoplePicker: View {
  @Binding var participantIDs: [UUID]

  @Environment(\.globalsContainer) private var globalsContainer

  var body: some View {
    PickerContent(participantIDs: $participantIDs)
      .modelContainer(globalsContainer)
  }
}

@MainActor private struct PickerContent: View {
  @Binding var participantIDs: [UUID]

  @Environment(\.modelContext) private var globalsContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @Query(sort: \Person.name) private var allPeople: [Person]

  @State private var showPersonEditor = false
  @State private var newlyCreatedPerson: Person?
  @State private var personPendingDelete: Person?
  @State private var personDeleteConflict: PersonDeleteBlocker?
  @State private var deleteErrorMessage: String?

  var body: some View {
    let selected = orderedSelectedPeople
    let unselected = orderedUnselectedPeople

    Section("People") {
      if !selected.isEmpty {
        ForEach(selected) { person in
          personRow(person, isSelected: true)
        }
      }

      if !unselected.isEmpty {
        DisclosureGroup("Add existing person") {
          ForEach(unselected) { person in
            personRow(person, isSelected: false)
          }
        }
      }

      Button {
        showPersonEditor = true
      } label: {
        Label("Create new person", systemImage: "plus")
      }
    }
    .sheet(isPresented: $showPersonEditor) {
      PersonEditor(newlyCreated: $newlyCreatedPerson)
    }
    .onChange(of: newlyCreatedPerson) { _, person in
      guard let person else { return }
      if !participantIDs.contains(person.id) {
        participantIDs.append(person.id)
      }
      newlyCreatedPerson = nil
    }
    .confirmationDialog(
      "Delete this person?",
      isPresented: deleteConfirmationBinding,
      titleVisibility: .visible,
      presenting: personPendingDelete
    ) { person in
      Button("Delete \(person.name.isEmpty ? "person" : person.name)", role: .destructive) {
        performDelete(person)
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text(
        "This removes the person from the app. Their packing items on past trips will keep their snapshot data."
      )
    }
    .alert(
      "Can't delete this person",
      isPresented: conflictAlertBinding,
      presenting: personDeleteConflict
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { conflict in
      Text(conflict.message)
    }
    .alert(
      "Couldn't delete",
      isPresented: deleteErrorAlertBinding,
      presenting: deleteErrorMessage
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(message)
    }
  }

  private var deleteErrorAlertBinding: Binding<Bool> {
    Binding(
      get: { deleteErrorMessage != nil },
      set: { if !$0 { deleteErrorMessage = nil } }
    )
  }

  // MARK: - Row

  @ViewBuilder
  private func personRow(_ person: Person, isSelected: Bool) -> some View {
    Button {
      toggleParticipant(person)
    } label: {
      HStack(spacing: 12) {
        PersonAvatar(name: person.name, colorKey: person.colorKey, size: .standard)
        VStack(alignment: .leading, spacing: 2) {
          Text(person.name.isEmpty ? "Unnamed" : person.name)
            .foregroundStyle(.primary)
          Text(theme.personPalette.entry(forKey: person.colorKey)?.displayName ?? person.colorKey)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if isSelected {
          Image(systemName: "minus.circle.fill")
            .foregroundStyle(.red)
        } else {
          Image(systemName: "plus.circle")
            .foregroundStyle(theme.variant(for: colorScheme).accent)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(role: .destructive) {
        requestDelete(person)
      } label: {
        Label("Delete person from app…", systemImage: "trash")
      }
    }
  }

  // MARK: - Person delete (AC 9.7 — UI-level enforcement per Decision 16)

  private func requestDelete(_ person: Person) {
    if let blocker = PersonDeleteBlocker.make(
      for: person,
      tripPacking: person.tripPackingItems ?? [],
      masterPacking: person.masterPackingItems ?? []
    ) {
      personDeleteConflict = blocker
    } else {
      personPendingDelete = person
    }
  }

  private func performDelete(_ person: Person) {
    let removedIndex = participantIDs.firstIndex(of: person.id)
    if let removedIndex {
      participantIDs.remove(at: removedIndex)
    }
    let personID = person.id
    globalsContext.delete(person)
    do {
      try globalsContext.save()  // LocalWriteHookContract: allow — globals context, not tripsLocal
    } catch {
      globalsContext.rollback()
      // Rollback restored the Person in the store, so the binding must reflect
      // that too — otherwise the UI shows the person gone while they're still
      // around. Re-insert at the original position.
      if let removedIndex {
        participantIDs.insert(personID, at: removedIndex)
      }
      let errorMessage = error.localizedDescription
      modelLogger.error(
        """
        [TripEditorPeoplePicker.performDelete] save failed for \
        personID=\(personID, privacy: .public): \
        \(errorMessage, privacy: .public)
        """
      )
      deleteErrorMessage = "Couldn't delete this person — try again."
    }
    personPendingDelete = nil
  }

  // MARK: - Derived people

  private var peopleByID: [UUID: Person] {
    Dictionary(uniqueKeysWithValues: allPeople.map { ($0.id, $0) })
  }

  private var orderedSelectedPeople: [Person] {
    let byID = peopleByID
    return participantIDs.compactMap { byID[$0] }
  }

  private var orderedUnselectedPeople: [Person] {
    let selectedIDs = Set(participantIDs)
    return allPeople.filter { !selectedIDs.contains($0.id) }
  }

  private func toggleParticipant(_ person: Person) {
    if let index = participantIDs.firstIndex(of: person.id) {
      participantIDs.remove(at: index)
    } else {
      participantIDs.append(person.id)
    }
  }

  // MARK: - Bindings

  private var deleteConfirmationBinding: Binding<Bool> {
    Binding(
      get: { personPendingDelete != nil },
      set: { if !$0 { personPendingDelete = nil } }
    )
  }

  private var conflictAlertBinding: Binding<Bool> {
    Binding(
      get: { personDeleteConflict != nil },
      set: { if !$0 { personDeleteConflict = nil } }
    )
  }
}
