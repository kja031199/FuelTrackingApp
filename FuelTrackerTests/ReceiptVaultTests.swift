import Foundation
import SwiftData
import Testing
import UIKit
@testable import FuelTracker

private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1   // keep pixel dimensions equal to point dimensions
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.darkGray.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

@MainActor
struct ReceiptVaultModelTests {
    @Test func receiptDataRoundTripsAndHasReceiptReflectsIt() throws {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let entry = FuelEntry(odometer: 100, gallons: 10, pricePerGallon: 3,
                              receiptImageData: data, vehicle: vehicle)
        container.mainContext.insert(entry)
        try container.mainContext.save()

        #expect(entry.hasReceipt)
        #expect(entry.receiptImageData == data)
    }

    @Test func entryWithoutAReceiptHasNone() {
        let entry = FuelEntry(odometer: 100, gallons: 10, pricePerGallon: 3)
        #expect(!entry.hasReceipt)
        #expect(entry.receiptImageData == nil)
    }

    @Test func formModelAttachesEditsRemovesAndResetsTheReceipt() throws {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        // Attach on a new entry.
        let form = FillUpFormModel()
        form.odometer = 100
        form.gallons = 10
        form.pricePerGallon = 3
        let data = Data([1, 2, 3, 4])
        form.receiptImageData = data
        form.save(to: vehicle, in: container.mainContext)

        let saved = try #require(vehicle.fillUps.first)
        #expect(saved.receiptImageData == data)

        // Editing loads it back.
        let editForm = FillUpFormModel(entry: saved)
        #expect(editForm.receiptImageData == data)

        // Removing it persists on save.
        editForm.receiptImageData = nil
        editForm.save(to: vehicle, in: container.mainContext)
        #expect(saved.receiptImageData == nil)
        #expect(!saved.hasReceipt)

        // Reset clears it for the next quick entry.
        let fresh = FillUpFormModel()
        fresh.receiptImageData = data
        fresh.resetForNextEntry()
        #expect(fresh.receiptImageData == nil)
    }

    @Test func largeReceiptSurvivesSaveAndAFreshFetch() throws {
        // Exercises the actual @Attribute(.externalStorage) round-trip with a
        // real JPEG, not just retention of the in-memory instance.
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let jpeg = try #require(solidImage(width: 1200, height: 1600).jpegData(compressionQuality: 0.8))
        let entry = FuelEntry(odometer: 100, gallons: 10, pricePerGallon: 3,
                              receiptImageData: jpeg, vehicle: vehicle)
        container.mainContext.insert(entry)
        try container.mainContext.save()

        let entryID = entry.id
        let fetched = try #require(
            try container.mainContext.fetch(FetchDescriptor<FuelEntry>()).first { $0.id == entryID }
        )
        #expect(fetched.receiptImageData == jpeg)
        #expect(UIImage(data: try #require(fetched.receiptImageData)) != nil)
    }

    @Test func editingOtherFieldsPreservesAnUntouchedReceipt() throws {
        // A save path that forgot to copy the receipt would silently drop the
        // photo on any unrelated edit — guard against that.
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let form = FillUpFormModel()
        form.odometer = 100
        form.gallons = 10
        form.pricePerGallon = 3
        let data = Data([9, 8, 7, 6])
        form.receiptImageData = data
        form.save(to: vehicle, in: container.mainContext)
        let saved = try #require(vehicle.fillUps.first)

        let editForm = FillUpFormModel(entry: saved)
        editForm.station = "Shell"            // change something unrelated
        editForm.save(to: vehicle, in: container.mainContext)

        #expect(saved.station == "Shell")
        #expect(saved.receiptImageData == data)
        #expect(saved.hasReceipt)
    }

    @Test func replacingTheReceiptSwapsTheData() throws {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let first = Data([1, 1, 1])
        let second = Data([2, 2, 2, 2])
        let form = FillUpFormModel()
        form.odometer = 100
        form.gallons = 10
        form.pricePerGallon = 3
        form.receiptImageData = first
        form.save(to: vehicle, in: container.mainContext)
        let saved = try #require(vehicle.fillUps.first)

        let editForm = FillUpFormModel(entry: saved)
        editForm.receiptImageData = second
        editForm.save(to: vehicle, in: container.mainContext)
        #expect(saved.receiptImageData == second)
    }

    @Test func hasReceiptTreatsEmptyDataAsNoneButAcceptsUndecodableBytes() {
        // Zero bytes is not a receipt — no paperclip, no empty thumbnail slot.
        let empty = FuelEntry(odometer: 100, gallons: 10, pricePerGallon: 3, receiptImageData: Data())
        #expect(!empty.hasReceipt)

        // Non-empty but undecodable: present (paperclip shows) and must not
        // crash — the viewer handles the decode failure separately.
        let junk = FuelEntry(odometer: 100, gallons: 10, pricePerGallon: 3, receiptImageData: Data([0, 1, 2]))
        #expect(junk.hasReceipt)
        #expect(UIImage(data: junk.receiptImageData!) == nil)
    }
}

struct ReceiptImageTests {
    @Test func downsizesLargePhotosToTheMaxDimension() throws {
        let data = try #require(solidImage(width: 2400, height: 1600).pngData())
        let compressed = try #require(ReceiptImage.compressed(from: data, maxDimension: 800))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(max(result.size.width, result.size.height) - 800) <= 2)
        // Still a decodable image, and aspect ratio preserved (3:2).
        #expect(abs(result.size.width / result.size.height - 1.5) < 0.02)
    }

    @Test func leavesAlreadySmallPhotosAtTheirSize() throws {
        let data = try #require(solidImage(width: 120, height: 120).pngData())
        let compressed = try #require(ReceiptImage.compressed(from: data, maxDimension: 800))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(result.size.width - 120) <= 1)
        #expect(abs(result.size.height - 120) <= 1)
    }

    @Test func compressesFromAUIImageDirectly() throws {
        let compressed = try #require(ReceiptImage.compressed(from: solidImage(width: 1000, height: 500), maxDimension: 400))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(max(result.size.width, result.size.height) - 400) <= 2)
    }

    @Test func imageExactlyAtMaxDimensionIsNotResized() throws {
        // Longest side equals the cap; the guard uses a strict >, so no resize.
        let compressed = try #require(ReceiptImage.compressed(from: solidImage(width: 800, height: 600), maxDimension: 800))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(result.size.width - 800) <= 1)
        #expect(abs(result.size.height - 600) <= 1)
    }

    @Test func downsizesPortraitPhotosOnTheHeight() throws {
        let compressed = try #require(ReceiptImage.compressed(from: solidImage(width: 1600, height: 2400), maxDimension: 800))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(max(result.size.width, result.size.height) - 800) <= 2)
        #expect(result.size.height > result.size.width)               // still portrait
        #expect(abs(result.size.width / result.size.height - 2.0 / 3.0) < 0.02)
    }

    @Test func handlesAnExtremeAspectRatioWithoutCrashing() throws {
        // A panorama-shaped receipt: the short side downsizes to a sliver but
        // must still yield a decodable image.
        let compressed = try #require(ReceiptImage.compressed(from: solidImage(width: 4000, height: 200), maxDimension: 1600))
        let result = try #require(UIImage(data: compressed))
        #expect(abs(max(result.size.width, result.size.height) - 1600) <= 2)
        #expect(result.size.height >= 1)
    }

    @Test func handlesATinyOnePixelImage() throws {
        let compressed = try #require(ReceiptImage.compressed(from: solidImage(width: 1, height: 1), maxDimension: 800))
        #expect(UIImage(data: compressed) != nil)
    }

    @Test func returnsNilForNonImageData() {
        #expect(ReceiptImage.compressed(from: Data([0x00, 0x01, 0x02, 0x03])) == nil)
        #expect(ReceiptImage.compressed(from: Data()) == nil)
    }
}
