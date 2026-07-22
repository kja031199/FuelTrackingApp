import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import FuelTracker

struct ReceiptPhotoImporterTests {
    // MARK: - bestDate preference (deterministic, no OCR)

    @Test func bestDatePrefersThePrintedReceiptDateOverTheCaptureDate() {
        let printed = Date(timeIntervalSince1970: 1_700_000_000)
        let captured = Date(timeIntervalSince1970: 1_700_500_000)
        let imported = ReceiptPhotoImport(purchaseDate: printed, capturedAt: captured)
        #expect(imported.bestDate == printed)
    }

    @Test func bestDateFallsBackToTheCaptureDateWhenNoDateIsPrinted() {
        let captured = Date(timeIntervalSince1970: 1_700_500_000)
        #expect(ReceiptPhotoImport(capturedAt: captured).bestDate == captured)
    }

    @Test func bestDateIsNilWhenNeitherIsKnown() {
        #expect(ReceiptPhotoImport().bestDate == nil)
    }

    // MARK: - foundAnything (deterministic, no OCR)

    @Test func foundAnythingIsFalseForACompletelyEmptyImport() {
        #expect(!ReceiptPhotoImport().foundAnything)
    }

    @Test func foundAnythingIsTrueIfAnySingleFieldIsPresent() {
        #expect(ReceiptPhotoImport(reading: PumpReading(gallons: 10, pricePerGallon: 3, totalCost: 30)).foundAnything)
        #expect(ReceiptPhotoImport(purchaseDate: .now).foundAnything)
        #expect(ReceiptPhotoImport(capturedAt: .now).foundAnything)
        #expect(ReceiptPhotoImport(stationName: "Shell").foundAnything)
        #expect(ReceiptPhotoImport(latitude: 37.0, longitude: -122.0).foundAnything)
    }

    // MARK: - Full pipeline against a rendered receipt JPEG

    @Test func readsFuelStationAndMetadataFromARenderedReceipt() async throws {
        // A receipt image with no printed date: OCR reads the fuel and brand,
        // EXIF/GPS carry the capture time and location, and — with no printed
        // date — bestDate must fall back to the EXIF capture date.
        let size = CGSize(width: 900, height: 620)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("SHELL" as NSString).draw(at: CGPoint(x: 48, y: 60), withAttributes: attributes)
            ("GALLONS 8.712" as NSString).draw(at: CGPoint(x: 48, y: 240), withAttributes: attributes)
            ("PRICE/GAL 3.499" as NSString).draw(at: CGPoint(x: 48, y: 420), withAttributes: attributes)
        }
        let cgImage = try #require(image.cgImage)

        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:08:01 10:15:00",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let imported = await ReceiptPhotoImporter.process(data: data as Data)

        #expect(imported.reading.gallons == 8.712)
        #expect(imported.reading.pricePerGallon == 3.499)
        #expect(imported.stationName == "Shell")
        #expect(!imported.ocrLines.isEmpty)
        #expect(imported.foundAnything)

        // No date on the receipt text → bestDate uses the EXIF capture date.
        #expect(imported.purchaseDate == nil)
        let captured = try #require(imported.capturedAt)
        #expect(imported.bestDate == captured)

        let latitude = try #require(imported.latitude)
        let longitude = try #require(imported.longitude)
        #expect(abs(latitude - 37.7749) < 0.001)
        #expect(abs(longitude - -122.4194) < 0.001)
    }

    @Test func corruptDataProducesAnEmptyImportNotACrash() async {
        let imported = await ReceiptPhotoImporter.process(data: Data([0x00, 0x01, 0x02, 0x03]))
        #expect(!imported.foundAnything)
        #expect(imported.reading == PumpReading())
        #expect(imported.stationName == nil)
        #expect(imported.bestDate == nil)
    }

    @Test func completelyEmptyDataProducesAnEmptyImport() async {
        let imported = await ReceiptPhotoImporter.process(data: Data())
        #expect(!imported.foundAnything)
        #expect(imported.ocrLines.isEmpty)
    }
}
