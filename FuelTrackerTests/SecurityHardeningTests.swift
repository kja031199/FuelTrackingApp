import Foundation
import ImageIO
import Testing
import UIKit
@testable import FuelTracker

private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.gray.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// Regression tests for the hardening in the security review: the OCR
/// parser's cubic search and the image-decode path both process untrusted,
/// attacker-supplied photo data and must stay bounded.
struct SecurityHardeningTests {
    // MARK: - Algorithmic-complexity DoS (PumpScanParser)

    @Test func labeledValuesSurviveANumberFloodWithoutHanging() {
        // A crafted, number-dense image could yield hundreds of OCR tokens.
        // With the O(n³) consistency search capped, labeled values still
        // resolve — and the call returning promptly (rather than grinding
        // through ~800³ comparisons) is itself the regression guard.
        var lines = ["GALLONS 8.712", "PRICE/GAL 3.499"]
        lines += (0..<800).map { "ITEM \(Double($0 % 55) + 1.234)" }

        let reading = PumpScanParser.parse(lines)
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
    }

    @Test func anUnlabeledNumberFloodReturnsAndNeverFabricatesOutOfRangeFuel() {
        let reading = PumpScanParser.parse((0..<1_000).map { "\(Double($0 % 50) + 1.111)" })
        // A flood has no genuine triple to find; the point is that it returns
        // at all, and never invents an out-of-range gallons/price value.
        if let gallons = reading.gallons { #expect((0.3...60.0).contains(gallons)) }
        if let price = reading.pricePerGallon { #expect((1.5...9.999).contains(price)) }
    }

    @Test func aRealTripleIsStillFoundAmidModerateNoise() {
        // The cap must not break legitimate parsing: a genuine unlabeled
        // triple embedded in a handful of noise numbers is still recovered.
        let reading = PumpScanParser.parse(["73.0", "0.02", "30.48", "8.712", "3.499", "19.0"])
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
        #expect(reading.totalCost == 30.48)
    }

    // MARK: - Image decompression bomb (ReceiptImage)

    @Test func boundedThumbnailCapsLargeSourceImages() throws {
        // A 15-megapixel source must decode down to the cap, never at full
        // resolution — the defense against a decompression-bomb DoS.
        let data = try #require(solidImage(width: 5000, height: 3000).jpegData(compressionQuality: 1))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let thumbnail = try #require(ReceiptImage.boundedThumbnail(from: source, maxPixelSize: 1600))
        #expect(max(thumbnail.width, thumbnail.height) <= 1600)
    }

    @Test func compressionAlwaysReencodesLargePhotosBelowTheCap() throws {
        // What actually gets persisted is the re-encoded, bounded image —
        // so a huge source can't land full-size in the store or in sync.
        let data = try #require(solidImage(width: 4000, height: 4000).jpegData(compressionQuality: 1))
        let out = try #require(ReceiptImage.compressed(from: data, maxDimension: 1600))
        let decoded = try #require(UIImage(data: out))
        #expect(max(decoded.size.width, decoded.size.height) <= 1600)
    }

    @Test func undecodableBytesProduceNilSoTheyAreNeverStored() {
        // The call sites persist only a non-nil compressed result, so junk or
        // an unbounded payload that fails to decode is dropped, not saved.
        #expect(ReceiptImage.compressed(from: Data([0xDE, 0xAD, 0xBE, 0xEF])) == nil)
        #expect(ReceiptImage.compressed(from: Data()) == nil)
    }
}
