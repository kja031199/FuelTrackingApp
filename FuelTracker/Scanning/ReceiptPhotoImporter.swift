import Foundation

/// Everything extractable from a photo of a fuel receipt: the fuel numbers
/// and station via OCR, the printed purchase date, and — as fallbacks — the
/// photo's own EXIF capture date and GPS position.
struct ReceiptPhotoImport {
    var reading = PumpReading()
    /// Date printed on the receipt (preferred — it's the actual purchase).
    var purchaseDate: Date?
    /// When the photo was taken (fallback when the receipt date is unreadable).
    var capturedAt: Date?
    var stationName: String?
    var latitude: Double?
    var longitude: Double?
    var ocrLines: [String] = []

    /// The best date we have: what the receipt says, else when it was shot.
    var bestDate: Date? { purchaseDate ?? capturedAt }

    var foundAnything: Bool {
        reading != PumpReading()
            || purchaseDate != nil
            || capturedAt != nil
            || stationName != nil
            || latitude != nil
    }
}

/// Reads a receipt photo into a fill-up. It reuses ``PumpPhotoImporter`` for
/// the on-device Vision OCR and the EXIF/GPS metadata, then re-parses the
/// same recognized text with ``ReceiptScanParser`` to pull the fuel numbers,
/// the printed date, and the station brand.
enum ReceiptPhotoImporter {
    static func process(data: Data) async -> ReceiptPhotoImport {
        reading(from: await PumpPhotoImporter.process(data: data))
    }

    /// Derives the receipt fields from an already-OCR'd pump import — no second
    /// OCR pass. Lets a caller run OCR once and interpret the same text as
    /// either a pump display or a receipt.
    static func reading(from pump: PumpPhotoImport) -> ReceiptPhotoImport {
        // The photo's capture date is the best reference for resolving a
        // two-digit year and for rejecting an impossible future date.
        let receipt = ReceiptScanParser.parse(pump.ocrLines, referenceDate: pump.capturedAt ?? .now)

        return ReceiptPhotoImport(
            reading: receipt.reading,
            purchaseDate: receipt.purchaseDate,
            capturedAt: pump.capturedAt,
            stationName: receipt.stationName,
            latitude: pump.latitude,
            longitude: pump.longitude,
            ocrLines: pump.ocrLines
        )
    }
}
