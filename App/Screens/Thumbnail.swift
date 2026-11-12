import SwiftUI
import UIKit

/// A square thumbnail from what is stored on this device. Decorative: rows and the detail describe the photo in text.
struct Thumbnail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let id: String
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side / 8))
        .accessibilityHidden(true)
        .task(id: id) {
            image = await model.library.thumbnail(for: id, pixelSide: side * displayScale)
        }
    }
}
