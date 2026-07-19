import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Everything extractable from a photo of a gas pump: the pump numbers via
/// OCR, and when/where it was taken via the photo's EXIF and GPS metadata.
struct PumpPhotoImport {
    var reading = PumpReading()
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?
    /// Raw OCR lines, so callers can run further extraction (e.g. the
    /// odometer parser, which needs vehicle history this importer lacks).
    var ocrLines: [String] = []

    var foundAnything: Bool {
        reading != PumpReading() || capturedAt != nil || latitude != nil
    }
}

/// Reads a pump photo the user took earlier: on-device Vision OCR feeds the
/// same PumpScanParser as the live camera scanner, and ImageIO surfaces the
/// capture date and GPS position embedded in the photo file.
enum PumpPhotoImporter {
    static func process(data: Data) async -> PumpPhotoImport {
        var result = PumpPhotoImport()

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return result
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                result.capturedAt = exifDate(from: exif)
            }
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let coordinate = gpsCoordinate(from: gps) {
                result.latitude = coordinate.latitude
                result.longitude = coordinate.longitude
            }
        }

        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            result.ocrLines = recognizeText(in: cgImage)
            result.reading = PumpScanParser.parse(result.ocrLines)
        }

        return result
    }

    /// EXIF stores capture dates as "yyyy:MM:dd HH:mm:ss" with no time zone;
    /// the convention is the local zone where the photo was taken, which for
    /// a same-phone photo is the device zone.
    static func exifDate(from exif: [CFString: Any]) -> Date? {
        guard let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }

    /// GPS metadata stores unsigned degrees plus N/S and E/W reference letters.
    static func gpsCoordinate(from gps: [CFString: Any]) -> (latitude: Double, longitude: Double)? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latitudeSign = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" ? -1.0 : 1.0
        let longitudeSign = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" ? -1.0 : 1.0
        let signedLatitude = latitude * latitudeSign
        let signedLongitude = longitude * longitudeSign

        // Reject implausible fixes: out-of-range degrees, and the exact
        // (0, 0) "null island" some cameras write when they had no GPS
        // lock — otherwise we'd hunt for gas stations in the Atlantic.
        guard abs(signedLatitude) <= 90,
              abs(signedLongitude) <= 180,
              !(signedLatitude == 0 && signedLongitude == 0) else {
            return nil
        }
        return (signedLatitude, signedLongitude)
    }

    private static func recognizeText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Pump displays are numbers and terse labels; language correction
        // "fixes" them into words.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
