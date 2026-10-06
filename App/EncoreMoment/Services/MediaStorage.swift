import Foundation
import EncoreMomentCore

/// Persists media picked by a creator into the app's Documents directory and
/// returns a stable file URL that the rest of the app can display and download.
///
/// This stands in for uploading to a real media backend; the returned URL is what
/// a server would otherwise hand back.
enum MediaStorage {
    private static var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func store(data: Data, fileExtension: String) throws -> URL {
        let url = mediaDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "dat" : fileExtension)
        try data.write(to: url)
        return url
    }

    static func store(fileAt source: URL, fileExtension: String) throws -> URL {
        let url = mediaDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "dat" : fileExtension)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    static func resolvedLocalFileURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let fallback = mediaDirectory.appendingPathComponent(url.lastPathComponent)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    static func displayURL(for url: URL?) -> URL? {
        guard let url else { return nil }
        if url.isFileURL {
            return resolvedLocalFileURL(for: url)
        }
        return normalizedRemoteURL(for: url)
    }

    static func displayCoverURL(for event: Event) -> URL? {
        if let cover = displayURL(for: event.coverImageURL) {
            return cover
        }
        return displayURL(for: event.media.first?.previewURL)
    }

    static func playableURL(for url: URL) -> URL {
        if let local = resolvedLocalFileURL(for: url) { return local }
        return normalizedRemoteURL(for: url)
    }

    private static func normalizedRemoteURL(for url: URL) -> URL {
        guard url.scheme == "http",
              url.host == "inthemoment-api.fly.dev",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }
}
