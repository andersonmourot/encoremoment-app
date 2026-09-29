import Foundation
import UniformTypeIdentifiers
import EncoreMomentCore

struct EventMediaImportItem {
    let data: Data
    let supportedContentTypes: [UTType]
}

enum EventMediaImporter {
    static func importItems(_ items: [EventMediaImportItem], to eventId: UUID, model: AppModel) async throws {
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: UTType.movie) }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
            let kind: MediaKind = isVideo ? .video : .photo
            let thumbnailData = isVideo ? try? VideoThumbnailGenerator.jpegData(for: item.data, fileExtension: ext) : nil
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
