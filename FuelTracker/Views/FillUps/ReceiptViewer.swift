import SwiftUI
import UIKit

/// Full-screen viewer for a saved receipt photo, with pinch-to-zoom and a
/// share option (for expense reports, warranty claims, etc.).
struct ReceiptViewer: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    private var image: UIImage? {
        UIImage(data: imageData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = min(max(lastScale * value.magnification, 1), 6)
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Color.black)
                } else {
                    ContentUnavailableView("Couldn't Load Receipt", systemImage: "photo")
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let image {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Receipt", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share receipt")
                    }
                }
            }
        }
    }
}
