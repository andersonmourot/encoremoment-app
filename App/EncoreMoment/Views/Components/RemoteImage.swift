import SwiftUI
import UIKit

/// Thin wrapper over `AsyncImage` with a consistent placeholder and fill behaviour.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @ViewBuilder
    var body: some View {
        if let url, url.isFileURL {
            if let localURL = MediaStorage.displayURL(for: url),
               let image = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                placeholder(systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        } else {
            AsyncImage(url: MediaStorage.displayURL(for: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    placeholder(systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    Rectangle()
                        .fill(.quaternary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shimmering()
                @unknown default:
                    placeholder(systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipped()
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
