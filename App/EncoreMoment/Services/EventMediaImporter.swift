import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import EncoreMomentCore

struct EventMediaImportItem {
    let data: Data
    let supportedContentTypes: [UTType]
}

/// Generates a small JPEG thumbnail for a photo upload so feeds and grids
/// don't pull down the full-resolution image.
enum PhotoThumbnailGenerator {
    static func jpegData(for data: Data, maxDimension: CGFloat = 800) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        return UIGraphicsImageRenderer(size: target).jpegData(
            withCompressionQuality: 0.72
        ) { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        #else
        return nil
        #endif
    }
}

enum EventMediaImporter {
    static func importItems(_ items: [EventMediaImportItem], to eventId: UUID, model: AppModel) async throws {
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: UTType.movie) }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
            let kind: MediaKind = isVideo ? .video : .photo
            let thumbnailData = isVideo
                ? try? VideoThumbnailGenerator.jpegData(for: item.data, fileExtension: ext)
                : PhotoThumbnailGenerator.jpegData(for: item.data)
            do {
                try await model.uploadMedia(
                    data: item.data,
                    fileExtension: ext,
                    kind: kind,
                    thumbnailData: thumbnailData,
                    to: eventId
                )
                continue
            } catch {
                guard AppConfig.usesLocalAPI else {
                    throw error
                }
                // Local development can keep working without a deployed upload backend.
            }

            let url = try MediaStorage.store(data: item.data, fileExtension: ext)
            let thumbnailURL = try thumbnailData.map { try MediaStorage.store(data: $0, fileExtension: "jpg") }
            let media = MediaItem(
                eventId: eventId,
                kind: kind,
                url: url,
                thumbnailURL: thumbnailURL ?? (isVideo ? nil : url)
            )
            await model.addMedia(media, to: eventId)
        }
    }
}
