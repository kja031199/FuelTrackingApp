import Foundation
import SwiftData

@Model
final class Vehicle {
    @Attribute(.unique) var id: UUID
    var name: String
    var make: String
    var model: String
    var year: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var entries: [FuelEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        make: String = "",
        model: String = "",
        year: Int = Calendar.current.component(.year, from: .now),
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.make = make
        self.model = model
        self.year = year
        self.createdAt = createdAt
    }

    /// "2021 Honda Civic" if make/model are set, otherwise just the nickname.
    var displaySubtitle: String {
        let details = [String(year), make, model]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return details == String(year) ? "" : details
    }
}
