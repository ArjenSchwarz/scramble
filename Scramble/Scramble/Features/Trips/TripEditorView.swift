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

  @State private var draft: TripDraft
  @State private var errors: [TripDraft.Field: String] = [:]
  /// Text buffer for the country-code field. Kept separate from
  /// `draft.countryCode` so the editor can hold transient invalid input
  /// (e.g. mid-typing "N") without overwriting the draft's validated
  /// value (Phase 6 Req 6.5).
  @State private var countryCodeInput: String

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
      _countryCodeInput = State(initialValue: "")
    case .edit(let trip):
      _draft = State(initialValue: TripDraft(from: trip))
      _countryCodeInput = State(initialValue: trip.countryCode ?? "")
    }
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        Form {
          nameSection
          datesSection
          countrySection
          attributesSection
          TripEditorPeoplePicker(participantIDs: $draft.participantIDs)
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
    }
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

  private var countrySection: some View {
    Section("Destination") {
      HStack {
        TextField("Country code (e.g. NL)", text: $countryCodeInput)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .onChange(of: countryCodeInput) { _, newValue in
            switch TripDraft.normaliseCountryCode(newValue) {
            case .clear:
              draft.countryCode = nil
              errors[.countryCode] = nil
              if countryCodeInput != "" && !newValue.isEmpty {
                countryCodeInput = ""
              }
            case .set(let code):
              draft.countryCode = code
              errors[.countryCode] = nil
              if countryCodeInput != code {
                countryCodeInput = code
              }
            case .invalid:
              errors[.countryCode] = "Enter two letters (e.g. NL)"
            }
          }
        if let flag = CountryFlag.emoji(for: draft.countryCode) {
          Text(flag).font(.title2).accessibilityHidden(true)
        }
      }
      if let message = errors[.countryCode] {
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
