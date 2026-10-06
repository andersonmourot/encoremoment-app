import Foundation
import Photos
import EncoreMomentCore

/// Downloads a ``MediaItem``'s asset and saves it to the user's photo library so they
/// can use it however they like (the core promise of EncoreMoment).
enum MediaDownloader {
    enum DownloadError: LocalizedError {
        case notDownloadable
        case permissionDenied
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notDownloadable: return "The creator disabled downloads for this item."
            case .permissionDenied: return "Allow photo library access in Settings to save media."
            case .badResponse: return "Couldn't download this item. Try again."
            }
        }
    }

    /// Result of a batch download: how many items saved vs. failed/skipped.
    struct BatchResult: Sendable {
        var saved: Int
        var failed: Int
    }

    /// Downloads every downloadable item in `items` to the photo library.
    /// Permission is requested once up front; individual failures are counted,
    /// not thrown. Up to four items transfer concurrently — each streams to a
    /// temp file rather than sitting in memory.
    static func saveAllToPhotoLibrary(_ items: [MediaItem]) async throws -> BatchResult {
        let downloadable = items.filter(\.isDownloadable)
        guard !downloadable.isEmpty else { throw DownloadError.notDownloadable }
        try await requestAddPermission()

        return await withTaskGroup(of: Bool.self) { group in
            var iterator = downloadable.makeIterator()
            var saved = 0, failed = 0, running = 0
            while running < 4, let item = iterator.next() {
                group.addTask { (try? await saveToPhotoLibrary(item)) != nil }
                running += 1
            }
            while let success = await group.next() {
                if success { saved += 1 } else { failed += 1 }
                running -= 1
                if let item = iterator.next() {
                    group.addTask { (try? await saveToPhotoLibrary(item)) != nil }
                    running += 1
                }
            }
            return BatchResult(saved: saved, failed: failed)
        }
    }

    /// Downloads `item` and writes it to the photo library, requesting permission if needed.
    static func saveToPhotoLibrary(_ item: MediaItem) async throws {
        guard item.isDownloadable else { throw DownloadError.notDownloadable }
        try await requestAddPermission()

        let assetURL = MediaStorage.playableURL(for: item.url)
        let fileURL: URL
        let cleanupTemp: Bool
        if assetURL.isFileURL {
            fileURL = assetURL
            cleanupTemp = false
        } else {
            // Download task lands straight on disk — no full-file Data in memory.
            let (tmp, response) = try await URLSession.shared.download(from: assetURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: tmp)
                throw DownloadError.badResponse
            }
            let ext = assetURL.pathExtension.isEmpty
                ? (item.kind == .video ? "mp4" : "jpg")
                : assetURL.pathExtension
            let named = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.moveItem(at: tmp, to: named)
            fileURL = named
            cleanupTemp = true
        }
        defer { if cleanupTemp { try? FileManager.default.removeItem(at: fileURL) } }

        // addResource(fileURL:) streams for both photos and videos — no Data buffer.
        let resourceType: PHAssetResourceType = item.kind == .video ? .video : .photo
        try await performChange { request in
            request.addResource(with: resourceType, fileURL: fileURL, options: nil)
        }
    }

    private static func requestAddPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw DownloadError.permissionDenied
            }
        default:
            throw DownloadError.permissionDenied
        }
    }

    private static func performChange(_ body: @escaping (PHAssetCreationRequest) -> Void) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            body(request)
        }
    }
}
