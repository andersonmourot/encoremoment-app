import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import EncoreMomentCore

struct EventMediaImportItem {
    /// Temp-file copy of the picked media — uploads stream from disk instead
    /// of holding full-resolution `Data` in memory.
    let fileURL: URL
    let supportedContentTypes: [UTType]
}

/// A picked asset vended as an on-disk file rather than decoded `Data` — a
/// 90MB video stays out of memory. The file URL received during import is
/// temporary, so it's copied into our own temp location.
private struct PickedMediaFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let ext = received.file.pathExtension.isEmpty ? "bin" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMediaFile(url: destination)
        }
    }
}

extension PhotosPickerItem {
    /// Copies the picked asset into a temp file without decoding it into memory.
    func persistedToTempFile() async throws -> URL? {
        try await loadTransferable(type: PickedMediaFile.self)?.url
    }
}

/// Generates a small JPEG thumbnail for a photo upload so feeds and grids
/// don't pull down the full-resolution image. ImageIO decodes directly at the
/// target size instead of rasterizing the full image first.
enum PhotoThumbnailGenerator {
    static func jpegData(for fileURL: URL, maxDimension: CGFloat = 800) -> Data? {
        #if canImport(UIKit)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.72)
        #else
        return nil
        #endif
    }
}

enum EventMediaImporter {
    /// Copies picked items to temp files so the upload pipeline streams them.
    static func makeImportItems(from items: [PhotosPickerItem]) async throws -> [EventMediaImportItem] {
        var importItems: [EventMediaImportItem] = []
        for item in items {
            guard let fileURL = try await item.persistedToTempFile() else { continue }
            importItems.append(EventMediaImportItem(
                fileURL: fileURL,
                supportedContentTypes: item.supportedContentTypes
            ))
        }
        return importItems
    }

    static func importItems(_ items: [EventMediaImportItem], to eventId: UUID, model: AppModel) async throws {
        var firstError: Error?
        for item in items {
            defer { try? FileManager.default.removeItem(at: item.fileURL) }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: UTType.movie) }
            let ext = item.fileURL.pathExtension.isEmpty
                ? (isVideo ? "mp4" : "jpg")
                : item.fileURL.pathExtension
            let kind: MediaKind = isVideo ? .video : .photo
            let thumbnailData = isVideo
                ? try? VideoThumbnailGenerator.jpegData(for: item.fileURL)
                : PhotoThumbnailGenerator.jpegData(for: item.fileURL)
            do {
                try await model.uploadMedia(
                    fileURL: item.fileURL,
                    fileExtension: ext,
                    kind: kind,
                    thumbnailData: thumbnailData,
                    to: eventId,
                    refreshes: false
                )
                continue
            } catch {
                guard AppConfig.usesLocalAPI else {
                    // Stop the batch but still refresh so completed files appear.
                    firstError = error
                    break
                }
                // Local development can keep working without a deployed upload backend.
            }

            let url = try MediaStorage.store(fileAt: item.fileURL, fileExtension: ext)
            let thumbnailURL = try thumbnailData.map { try MediaStorage.store(data: $0, fileExtension: "jpg") }
            let media = MediaItem(
                eventId: eventId,
                kind: kind,
                url: url,
                thumbnailURL: thumbnailURL ?? (isVideo ? nil : url)
            )
            await model.addMedia(media, to: eventId)
        }
        // One refresh for the whole batch, not one per uploaded file.
        await model.refreshFeeds()
        if let firstError { throw firstError }
    }
}
