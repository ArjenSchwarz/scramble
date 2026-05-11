import Foundation

/// AC 9.7 / Decision 16 delete-guard payload. SwiftData's `.deny` rule does not
/// throw on iOS 26, so the trip editor pre-checks references before calling
/// `context.delete(person)` and surfaces this struct via an alert when references
/// are found. Kept as a pure value type so the rule itself is unit-testable
/// without spinning up a `ModelContainer` or driving the UI.
struct PersonDeleteBlocker: Identifiable {
  let id = UUID()
  let personName: String
  let referencingTripNames: [String]
  let referencingMasterItemNames: [String]

  /// Returns a blocker describing the references that prevent `person` from being
  /// deleted, or `nil` when the delete is allowed. The caller is responsible for
  /// supplying the trip-level and master-level packing items that point at this
  /// person (the inputs are already plain arrays so the helper is pure).
  static func make(
    for person: Person,
    tripPacking: [TripPackingItem],
    masterPacking: [MasterPackingItem]
  ) -> PersonDeleteBlocker? {
    guard !tripPacking.isEmpty || !masterPacking.isEmpty else { return nil }
    let tripNames = Set(tripPacking.compactMap { $0.trip?.name })
      .map { $0.isEmpty ? "Untitled trip" : $0 }
      .sorted()
    let masterNames = masterPacking
      .map { $0.name.isEmpty ? "Unnamed item" : $0.name }
      .sorted()
    return PersonDeleteBlocker(
      personName: person.name.isEmpty ? "This person" : person.name,
      referencingTripNames: tripNames,
      referencingMasterItemNames: masterNames
    )
  }

  var message: String {
    var lines: [String] = ["\(personName) is still referenced by:"]
    if !referencingTripNames.isEmpty {
      lines.append("Trips: \(referencingTripNames.joined(separator: ", "))")
    }
    if !referencingMasterItemNames.isEmpty {
      lines.append("Master packing items: \(referencingMasterItemNames.joined(separator: ", "))")
    }
    lines.append("Remove the references before deleting.")
    return lines.joined(separator: "\n")
  }
}
