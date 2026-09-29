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
    /// Permission is requested once up front; individual failures are counted, not thrown.
    static func saveAllToPhotoLibrary(_ items: [MediaItem]) async throws -> BatchResult {
        let downloadable = items.filter(\.isDownloadable)
        guard !downloadable.isEmpty else { throw DownloadError.notDownloadable }
        try await requestAddPermission()

        var result = BatchResult(saved: 0, failed: 0)
        for item in downloadable {
            do {
                try await saveToPhotoLibrary(item)
                result.saved += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    /// Downloads `item` and writes it to the photo library, requesting permission if needed.
    static func saveToPhotoLibrary(_ item: MediaItem) async throws {
        guard item.isDownloadable else { throw DownloadError.notDownloadable }
        try await requestAddPermission()

        let assetURL = MediaStorage.playableURL(for: item.url)
        let data: Data
        if assetURL.isFileURL {
            data = try Data(contentsOf: assetURL)
        } else {
            let (downloaded, response) = try await URLSession.shared.data(from: assetURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DownloadError.badResponse
            }
            data = downloaded
        }

        switch item.kind {
        case .photo:
            try await performChange { request in
                request.addResource(with: .photo, data: data, options: nil)
            }
        case .video:
            // PHPhotoLibrary requires a file URL for video resources.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(assetURL.pathExtension.isEmpty ? "mp4" : assetURL.pathExtension)
            try data.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await performChange { request in
                request.addResource(with: .video, fileURL: tmp, options: nil)
            }
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
