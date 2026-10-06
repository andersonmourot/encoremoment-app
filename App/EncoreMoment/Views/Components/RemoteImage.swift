import SwiftUI
import UIKit

/// Remote image view backed by ``ImageLoader`` (memory + disk cache with
/// request coalescing) rather than `AsyncImage`, which re-fetches and
/// re-decodes every time a cell re-enters the screen.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var loaded: UIImage?
    @State private var failed = false

    @ViewBuilder
    var body: some View {
        Group {
            if let url, url.isFileURL {
                localImage(url)
            } else {
                remote
            }
        }
        .task(id: url) {
            loaded = nil
            failed = false
            guard let url, !url.isFileURL,
                  let remoteURL = MediaStorage.displayURL(for: url) else { return }
            loaded = await ImageLoader.shared.image(for: remoteURL)
            failed = loaded == nil
        }
    }

    @ViewBuilder
    private var remote: some View {
        if let loaded {
            Image(uiImage: loaded)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if failed {
            placeholder(systemImage: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shimmering()
        }
    }

    @ViewBuilder
    private func localImage(_ url: URL) -> some View {
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
