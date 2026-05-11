import Foundation
import SwiftData
import os

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast
    var attributesData: Data = Data()

    @Relationship(deleteRule: .nullify, inverse: \Person.trips)
    var participants: [Person] = []

    @Relationship(deleteRule: .cascade, inverse: \TripTask.trip)
    var tasks: [TripTask] = []

    @Relationship(deleteRule: .cascade, inverse: \TripPackingItem.trip)
    var packingItems: [TripPackingItem] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        startDate: Date = .distantPast,
        endDate: Date = .distantPast,
        attributes: TripAttributes = TripAttributes()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.attributesData = (try? JSONEncoder().encode(attributes)) ?? Data()
    }
}

extension Trip {
    var attributes: TripAttributes {
        get {
            guard !attributesData.isEmpty else { return TripAttributes() }
            do {
                return try JSONDecoder().decode(TripAttributes.self, from: attributesData)
            } catch {
                modelLogger.error(
                    "Trip.attributes decode failed: \(error.localizedDescription, privacy: .public)"
                )
                return TripAttributes()
            }
        }
        set {
            do {
                attributesData = try JSONEncoder().encode(newValue)
            } catch {
                modelLogger.error(
                    "Trip.attributes encode failed: \(error.localizedDescription, privacy: .public)"
                )
                attributesData = Data()
            }
        }
    }
}
