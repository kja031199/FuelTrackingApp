import Foundation
import SwiftData

/// In-memory container pre-filled with realistic data for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Vehicle.self, FuelEntry.self,
            configurations: config
        )

        let vehicle = Vehicle(name: "Daily Driver", make: "Honda", model: "Civic", year: 2021)
        container.mainContext.insert(vehicle)

        var odometer = 42_150.0
        var date = Calendar.current.date(byAdding: .day, value: -180, to: .now)!
        let prices = [3.199, 3.249, 3.399, 3.359, 3.289, 3.459, 3.599, 3.549, 3.479, 3.389, 3.299, 3.349]

        for (index, price) in prices.enumerated() {
            let miles = Double.random(in: 280...360)
            let gallons = miles / Double.random(in: 30...36)
            odometer += index == 0 ? 0 : miles
            let entry = FuelEntry(
                date: date,
                odometer: odometer,
                gallons: (gallons * 1000).rounded() / 1000,
                pricePerGallon: price,
                isFullTank: true,
                fuelGrade: .regular,
                station: ["Shell", "Costco", "Chevron", "76"].randomElement()!,
                vehicle: vehicle
            )
            container.mainContext.insert(entry)
            date = Calendar.current.date(byAdding: .day, value: 15, to: date)!
        }

        return container
    }()
}
