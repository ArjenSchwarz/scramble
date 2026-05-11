import Foundation
import SwiftData

@Model
final class TripTask {
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false

    init(
        id: UUID = UUID(),
        trip: Trip? = nil,
        masterItemID: UUID? = nil,
        name: String = "",
        phase: Phase = .weeksBefore,
        isCompleted: Bool = false,
        source: ItemSource = .manual,
        currentlyMatchesRules: Bool = true,
        pinnedByUser: Bool = false
    ) {
        self.id = id
        self.trip = trip
        self.masterItemID = masterItemID
        self.name = name
        self.phaseRaw = phase.rawValue
        self.isCompleted = isCompleted
        self.sourceRaw = source.rawValue
        self.currentlyMatchesRules = currentlyMatchesRules
        self.pinnedByUser = pinnedByUser
    }
}

extension TripTask {
    var phase: Phase {
        get { Phase(rawValue: phaseRaw) ?? .weeksBefore }
        set { phaseRaw = newValue.rawValue }
    }

    var source: ItemSource {
        get { ItemSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
