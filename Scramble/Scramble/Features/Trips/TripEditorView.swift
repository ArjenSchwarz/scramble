import SwiftData
import SwiftUI

/// Trip create / edit form. The editor operates on a `TripDraft` value copy so a
/// cancel discards pending edits. On save, the parent screen owns the apply-to-model
/// step (see `TripListView` / `TripDetailView`).
@MainActor struct TripEditorView: View {
  enum Mode: Equatable {
    case create
    case edit(Trip)
  }

  let mode: Mode
  /// Attribute the editor should auto-scroll to on appear (when launched from a
  /// chip tap in `TripDetailView`).
  var focusAttribute: TripAttribute?
  /// Called with the validated draft when the user taps Save. The closure is
  /// responsible for applying the draft to the model context and persisting.
  /// Returning `false` keeps the sheet open; `true` dismisses it.
  let onSave: (TripDraft) -> Bool

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Person.name) private var allPeople: [Person]

  @State private var draft: TripDraft
  @State private var errors: [TripDraft.Field: String] = [:]
  @State private var showPersonEditor = false
  @State private var newlyCreatedPerson: Person?
  @State private var personPendingDelete: Person?
  @State private var personDeleteConflict: PersonDeleteBlocker?

  init(
    mode: Mode,
    focusAttribute: TripAttribute? = nil,
    onSave: @escaping (TripDraft) -> Bool
  ) {
    self.mode = mode
    self.focusAttribute = focusAttribute
    self.onSave = onSave
    switch mode {
    case .create:
      _draft = State(initialValue: TripDraft.newDraft())
    case .edit(let trip):
      _draft = State(initialValue: TripDraft(from: trip))
    }
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        Form {
          nameSection
          datesSection
          attributesSection
          peopleSection
        }
        .onAppear {
          if let focus = focusAttribute {
            withAnimation { proxy.scrollTo(attributeAnchor(focus), anchor: .top) }
          }
        }
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { attemptSave() }
        }
      }
      .sheet(isPresented: $showPersonEditor) {
        PersonEditor(newlyCreated: $newlyCreatedPerson)
      }
      .onChange(of: newlyCreatedPerson) { _, person in
        guard let person else { return }
        if !draft.participantIDs.contains(person.id) {
          draft.participantIDs.append(person.id)
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
    }
  }

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

  private var navigationTitle: String {
    switch mode {
    case .create: "New Trip"
    case .edit: "Edit Trip"
    }
  }

  // MARK: - Sections

  private var nameSection: some View {
    Section("Name") {
      TextField("Trip name", text: $draft.name)
        .textInputAutocapitalization(.words)
      if let message = errors[.name] {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var datesSection: some View {
    Section("Dates") {
      DatePicker(
        "Start",
        selection: $draft.startDate,
        displayedComponents: .date
      )
      DatePicker(
        "End",
        selection: $draft.endDate,
        displayedComponents: .date
      )
      if let message = errors[.dateRange] {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var attributesSection: some View {
    ForEach(TripAttribute.allCases, id: \.self) { attribute in
      Section(attribute.displayName) {
        attributePicker(for: attribute)
      }
      .id(attributeAnchor(attribute))
    }
  }

  @ViewBuilder
  private func attributePicker(for attribute: TripAttribute) -> some View {
    if attribute.isMultiSelect {
      multiSelectRows(for: attribute)
    } else {
      singleSelectPicker(for: attribute)
    }
  }

  private func singleSelectPicker(for attribute: TripAttribute) -> some View {
    let values = TripAttributeOptions.values(for: attribute)
    return Picker(
      attribute.displayName,
      selection: Binding<String?>(
        get: { draft.attributes.selected(attribute).first },
        set: { draft.attributes.setSingle(attribute, value: $0) }
      )
    ) {
      Text("None").tag(String?.none)
      ForEach(values, id: \.self) { value in
        Text(value.attributeValueDisplay).tag(Optional(value))
      }
    }
    .pickerStyle(.menu)
  }

  private func multiSelectRows(for attribute: TripAttribute) -> some View {
    let values = TripAttributeOptions.values(for: attribute)
    let selected = Set(draft.attributes.selected(attribute))
    return ForEach(values, id: \.self) { value in
      Button {
        draft.attributes.toggle(attribute, value: value)
      } label: {
        HStack {
          Text(value.attributeValueDisplay)
            .foregroundStyle(.primary)
          Spacer()
          if selected.contains(value) {
            Image(systemName: "checkmark")
              .foregroundStyle(theme.variant(for: colorScheme).accent)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private var peopleSection: some View {
    Section("People") {
      let selected = orderedSelectedPeople
      let unselected = orderedUnselectedPeople

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
  }

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
    let removedIndex = draft.participantIDs.firstIndex(of: person.id)
    if let removedIndex {
      draft.participantIDs.remove(at: removedIndex)
    }
    modelContext.delete(person)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      // Rollback restored the Person in the store, so the draft must reflect
      // that too — otherwise the UI shows the person gone while they're still
      // around. Re-insert at the original position.
      if let removedIndex {
        draft.participantIDs.insert(person.id, at: removedIndex)
      }
    }
    personPendingDelete = nil
  }

  // MARK: - Derived people

  private var peopleByID: [UUID: Person] {
    Dictionary(uniqueKeysWithValues: allPeople.map { ($0.id, $0) })
  }

  private var orderedSelectedPeople: [Person] {
    let byID = peopleByID
    return draft.participantIDs.compactMap { byID[$0] }
  }

  private var orderedUnselectedPeople: [Person] {
    let selectedIDs = Set(draft.participantIDs)
    return allPeople.filter { !selectedIDs.contains($0.id) }
  }

  private func toggleParticipant(_ person: Person) {
    if let index = draft.participantIDs.firstIndex(of: person.id) {
      draft.participantIDs.remove(at: index)
    } else {
      draft.participantIDs.append(person.id)
    }
  }

  // MARK: - Save

  private func attemptSave() {
    let newErrors = draft.validate()
    errors = newErrors
    guard newErrors.isEmpty else { return }
    if onSave(draft) {
      dismiss()
    }
  }

  // MARK: - Anchors

  private func attributeAnchor(_ attribute: TripAttribute) -> String {
    "attr-\(attribute.rawValue)"
  }
}
