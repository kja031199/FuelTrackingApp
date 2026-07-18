import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import FuelTracker

struct PumpPhotoImporterTests {
    // MARK: - EXIF dates

    @Test func exifDateParsesTheStandardFormat() throws {
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2025:07:12 16:41:33"]
        let date = try #require(PumpPhotoImporter.exifDate(from: exif))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(components.year == 2025)
        #expect(components.month == 7)
        #expect(components.day == 12)
        #expect(components.hour == 16)
        #expect(components.minute == 41)
        #expect(components.second == 33)
    }

    @Test func exifDateRejectsGarbageAndAbsence() {
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "not a date"]) == nil)
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "2025-07-12T16:41:33Z"]) == nil)
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: ""]) == nil)
        #expect(PumpPhotoImporter.exifDate(from: [:]) == nil)
    }

    @Test func exifDateRejectsImpossibleCalendarValues() {
        // Month 13, February 30th, and the all-zeros timestamp some cameras
        // write when their clock was never set: the non-lenient formatter
        // must refuse them all rather than invent a date.
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "2025:13:01 12:00:00"]) == nil)
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "2025:02:30 12:00:00"]) == nil)
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "0000:00:00 00:00:00"]) == nil)
    }

    @Test func exifDateWithWrongValueTypeReturnsNil() {
        #expect(PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: 20250712]) == nil)
    }

    @Test func exifFutureDatesParseAndFlowThrough() throws {
        // A wrong camera clock is the user's data to correct; the importer
        // reports what the photo says, and the statistics layer already
        // tolerates future-dated entries.
        let date = try #require(
            PumpPhotoImporter.exifDate(from: [kCGImagePropertyExifDateTimeOriginal: "2099:01:01 00:00:00"])
        )
        #expect(date > .now)
    }

    // MARK: - GPS coordinates

    @Test func gpsAppliesHemisphereReferenceSigns() throws {
        let sydney: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 33.8688,
            kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2093,
            kCGImagePropertyGPSLongitudeRef: "E",
        ]
        let coordinate = try #require(PumpPhotoImporter.gpsCoordinate(from: sydney))
        #expect(coordinate.latitude == -33.8688)
        #expect(coordinate.longitude == 151.2093)

        let sanFrancisco: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 37.7749,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.4194,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]
        let sf = try #require(PumpPhotoImporter.gpsCoordinate(from: sanFrancisco))
        #expect(sf.latitude == 37.7749)
        #expect(sf.longitude == -122.4194)
    }

    @Test func gpsMissingRefsDefaultToNorthAndEast() throws {
        let bare: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 10.0,
            kCGImagePropertyGPSLongitude: 20.0,
        ]
        let coordinate = try #require(PumpPhotoImporter.gpsCoordinate(from: bare))
        #expect(coordinate.latitude == 10.0)
        #expect(coordinate.longitude == 20.0)
    }

    @Test func gpsIncompleteCoordinatesReturnNil() {
        #expect(PumpPhotoImporter.gpsCoordinate(from: [kCGImagePropertyGPSLatitude: 10.0]) == nil)
        #expect(PumpPhotoImporter.gpsCoordinate(from: [:]) == nil)
    }

    @Test func gpsRejectsNullIslandZeroZero() {
        // Cameras with no GPS lock sometimes write exact (0, 0). Accepting
        // it would send the station lookup to the Atlantic Ocean.
        let nullIsland: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 0.0,
            kCGImagePropertyGPSLongitude: 0.0,
        ]
        #expect(PumpPhotoImporter.gpsCoordinate(from: nullIsland) == nil)
    }

    @Test func gpsRejectsOutOfRangeDegrees() {
        #expect(PumpPhotoImporter.gpsCoordinate(from: [
            kCGImagePropertyGPSLatitude: 91.0,
            kCGImagePropertyGPSLongitude: 10.0,
        ]) == nil)
        #expect(PumpPhotoImporter.gpsCoordinate(from: [
            kCGImagePropertyGPSLatitude: 10.0,
            kCGImagePropertyGPSLongitude: 181.0,
        ]) == nil)
        #expect(PumpPhotoImporter.gpsCoordinate(from: [
            kCGImagePropertyGPSLatitude: 95.0,
            kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 10.0,
        ]) == nil)
    }

    @Test func gpsToleratesLowercaseHemisphereRefs() throws {
        // The EXIF spec says uppercase, but not every writer conforms.
        let coordinate = try #require(PumpPhotoImporter.gpsCoordinate(from: [
            kCGImagePropertyGPSLatitude: 33.8688,
            kCGImagePropertyGPSLatitudeRef: "s",
            kCGImagePropertyGPSLongitude: 122.4194,
            kCGImagePropertyGPSLongitudeRef: "w",
        ]))
        #expect(coordinate.latitude == -33.8688)
        #expect(coordinate.longitude == -122.4194)
    }

    @Test func gpsWrongValueTypesReturnNil() {
        let stringly: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: "37.7749",
            kCGImagePropertyGPSLongitude: "122.4194",
        ]
        #expect(PumpPhotoImporter.gpsCoordinate(from: stringly) == nil)
    }

    // MARK: - Full pipeline against a real JPEG

    @Test func metadataRoundTripsThroughARealJPEGFile() async throws {
        // Build a tiny gray JPEG carrying EXIF and GPS metadata, exactly as
        // a photo file would, and run it through the full import pipeline.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let cgImage = try #require(image.cgImage)

        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2025:07:12 16:41:33",
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

        let imported = await PumpPhotoImporter.process(data: data as Data)

        let latitude = try #require(imported.latitude)
        let longitude = try #require(imported.longitude)
        #expect(abs(latitude - 37.7749) < 0.001)
        #expect(abs(longitude - -122.4194) < 0.001)

        let capturedAt = try #require(imported.capturedAt)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: capturedAt)
        #expect(components.year == 2025)
        #expect(components.month == 7)
        #expect(components.day == 12)

        // A featureless gray square has no pump numbers to read.
        #expect(imported.reading == PumpReading())
        #expect(imported.foundAnything)
    }

    @Test func ocrReadsRenderedPumpTextEndToEnd() async {
        // The real thing: render pump-display text into an image and run it
        // through the complete pipeline — Vision OCR into PumpScanParser.
        let size = CGSize(width: 900, height: 620)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("GALLONS 8.712" as NSString).draw(at: CGPoint(x: 48, y: 80), withAttributes: attributes)
            ("PRICE/GAL 3.499" as NSString).draw(at: CGPoint(x: 48, y: 260), withAttributes: attributes)
            ("TOTAL 30.48" as NSString).draw(at: CGPoint(x: 48, y: 440), withAttributes: attributes)
        }
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            Issue.record("Could not encode the rendered test image")
            return
        }

        let imported = await PumpPhotoImporter.process(data: data)

        #expect(imported.reading.gallons == 8.712)
        #expect(imported.reading.pricePerGallon == 3.499)
        #expect(imported.reading.totalCost == 30.48)
        #expect(imported.reading.isComplete)
    }

    @Test func corruptDataProducesAnEmptyImportNotACrash() async {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE])
        let imported = await PumpPhotoImporter.process(data: garbage)
        #expect(!imported.foundAnything)
        #expect(imported.reading == PumpReading())
        #expect(imported.capturedAt == nil)
        #expect(imported.latitude == nil)
    }

    @Test func completelyEmptyDataProducesAnEmptyImport() async {
        let imported = await PumpPhotoImporter.process(data: Data())
        #expect(!imported.foundAnything)
    }

    @Test func imageWithoutMetadataYieldsNoDateOrLocation() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        let imported = await PumpPhotoImporter.process(data: data)
        #expect(imported.capturedAt == nil)
        #expect(imported.latitude == nil)
        #expect(imported.longitude == nil)
    }
}
