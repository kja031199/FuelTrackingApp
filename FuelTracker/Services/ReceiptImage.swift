import ImageIO
import UIKit

/// Prepares photos for storage as fill-up receipts. Full-resolution camera
/// shots are several megabytes; downsizing and recompressing keeps the
/// SwiftData store — and each synced CloudKit record — lean while leaving
/// the numbers on the receipt readable.
///
/// Decoding goes through ImageIO's thumbnail generator rather than
/// `UIImage(data:)`. `UIImage(data:)` decompresses the *entire* image into a
/// bitmap first, so a small but maliciously crafted file that expands to
/// enormous pixel dimensions (a "decompression bomb") would exhaust memory
/// and crash the app before any downsizing could help. The thumbnail path
/// decodes straight to a bounded size and never materializes the full-
/// resolution bitmap.
enum ReceiptImage {
    static func compressed(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = boundedThumbnail(from: source, maxPixelSize: Int(maxDimension)) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: quality)
    }

    static func compressed(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        image.resized(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// Decodes the image to at most `maxPixelSize` on its longest side,
    /// applying the EXIF orientation. Bounded memory regardless of the
    /// source's declared dimensions.
    static func boundedThumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
