import Foundation
import SwiftData

#if DEBUG
  extension UITestSeed {
    static func seedPackingTripStability(
      globals: ModelContext, trips: ModelContext, today: Date, calendar: Calendar
    ) {
      let person = Person(name: "Fixture Person", colorKey: "Cyan")
      globals.insert(person)
      let day = calendar.startOfDay(for: today)
      let draft = TripDraft(
        name: "Synthetic Packing Trip",
        startDate: calendar.date(byAdding: .day, value: 1, to: day)!,
        endDate: calendar.date(byAdding: .day, value: 6, to: day)!,
        attributes: TripAttributes(), participantIDs: [person.id])
      let (trip, _) = TripPersistence.create(from: draft, in: trips, globals: globals)
      let snapshot = (trip.participantSnapshots ?? []).first
      trips.insert(TripPackingItem(trip: trip, name: "Fixture item", personSnapshot: snapshot))
      try? globals.save()
      try? trips.save()
    }

  }
#endif
