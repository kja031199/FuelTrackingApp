import Foundation
import Testing
@testable import FuelTracker

struct PumpScanParserTests {
    @Test func parsesFullyLabeledDisplay() {
        let reading = PumpScanParser.parse([
            "THIS SALE $30.48",
            "GALLONS 8.712",
            "PRICE/GAL $3.499",
        ])
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
        #expect(reading.totalCost == 30.48)
        #expect(reading.isComplete)
    }

    @Test func parsesLabelsOnSeparateLines() {
        let reading = PumpScanParser.parse([
            "GALLONS",
            "8.712",
            "PRICE PER GALLON",
            "3.499",
            "TOTAL SALE",
            "30.48",
        ])
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
        #expect(reading.totalCost == 30.48)
    }

    @Test func handlesNineTenthsPriceNotation() {
        let reading = PumpScanParser.parse([
            "PRICE/GAL",
            "$3.49 9/10",
        ])
        #expect(reading.pricePerGallon == 3.499)
    }

    @Test func unlabeledTripleIsIdentifiedByArithmeticConsistency() {
        // 8.712 × 3.499 = 30.483... ≈ 30.48 — that consistency alone
        // tells us which number is which.
        let reading = PumpScanParser.parse(["30.48", "8.712", "3.499"])
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
        #expect(reading.totalCost == 30.48)
    }

    @Test func derivesGallonsFromTotalAndPrice() {
        let reading = PumpScanParser.parse([
            "TOTAL $35.00",
            "PRICE/GAL $3.500",
        ])
        #expect(reading.pricePerGallon == 3.5)
        #expect(reading.gallons == 10.0)
    }

    @Test func derivesTotalFromGallonsAndPrice() {
        let reading = PumpScanParser.parse([
            "GALLONS 10.000",
            "PRICE/GAL $3.500",
        ])
        #expect(reading.totalCost == 35.0)
    }

    @Test func threeDecimalHeuristicResolvesUnlabeledPriceAndGallons() {
        // No labels, no consistent triple — but only one three-decimal
        // value sits in the plausible price band and one in the gallons band.
        let reading = PumpScanParser.parse(["3.499", "12.345"])
        #expect(reading.pricePerGallon == 3.499)
        #expect(reading.gallons == 12.345)
    }

    @Test func ambiguousValuesAreNotGuessed() {
        // Two three-decimal values in the price band: refusing to guess
        // beats guessing wrong.
        let reading = PumpScanParser.parse(["3.499", "2.999"])
        #expect(reading.pricePerGallon == nil)
        #expect(!reading.isComplete)
    }

    @Test func noiseAndEmptyInputProduceNothing() {
        #expect(PumpScanParser.parse([]) == PumpReading())
        #expect(PumpScanParser.parse(["REGULAR", "UNLEADED", "INSERT CARD"]) == PumpReading())
        #expect(!PumpScanParser.parse(["WELCOME"]).isComplete)
    }

    @Test func implausibleValuesAreIgnored() {
        // 87 (octane), 42150.0 (odometer-ish) — out of range for everything.
        let reading = PumpScanParser.parse(["87.0", "42150.0"])
        #expect(reading == PumpReading())
    }

    @Test func mergeKeepsBestValuesAcrossFrames() {
        let first = PumpScanParser.merge(
            current: PumpReading(),
            new: PumpReading(gallons: 8.712, pricePerGallon: nil, totalCost: nil)
        )
        #expect(first.gallons == 8.712)

        let second = PumpScanParser.merge(
            current: first,
            new: PumpReading(gallons: nil, pricePerGallon: 3.499, totalCost: nil)
        )
        #expect(second.gallons == 8.712)
        #expect(second.pricePerGallon == 3.499)
        #expect(second.isComplete)
    }

    @Test func labeledValuesAreNotOverwrittenByLaterNumbers() {
        let reading = PumpScanParser.parse([
            "GALLONS 8.712",
            "GALLONS 9.999",
        ])
        #expect(reading.gallons == 8.712)
    }
}

@MainActor
struct FillUpFormCoordinateTests {
    @Test func coordinatesRoundTripThroughSaveAndEdit() {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.5
        form.station = "Shell"
        form.latitude = 37.7749
        form.longitude = -122.4194
        form.save(to: vehicle, in: container.mainContext)

        let saved = vehicle.fillUps.first!
        #expect(saved.latitude == 37.7749)
        #expect(saved.longitude == -122.4194)

        let editForm = FillUpFormModel(entry: saved)
        #expect(editForm.latitude == 37.7749)
        #expect(editForm.longitude == -122.4194)
    }

    @Test func resetClearsCoordinates() {
        let form = FillUpFormModel()
        form.latitude = 1
        form.longitude = 2
        form.resetForNextEntry()
        #expect(form.latitude == nil)
        #expect(form.longitude == nil)
    }
}
