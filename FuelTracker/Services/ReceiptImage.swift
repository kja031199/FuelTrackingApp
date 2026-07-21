import UIKit

/// Prepares photos for storage as fill-up receipts. Full-resolution camera
/// shots are several megabytes; downsizing and recompressing keeps the
/// SwiftData store — and each synced CloudKit record — lean while leaving
/// the numbers on the receipt readable.
enum ReceiptImage {
    static func compressed(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.resized(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    static func compressed(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        image.resized(maxDimension: maxDimension).jpegData(compressionQuality: quality)
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
