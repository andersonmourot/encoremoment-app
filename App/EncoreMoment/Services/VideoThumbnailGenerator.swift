import AVFoundation
import Foundation
import UIKit

enum VideoThumbnailGenerator {
    static func jpegData(for videoData: Data, fileExtension: String) throws -> Data? {
        let ext = fileExtension.isEmpty ? "mp4" : fileExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try videoData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        let image = try generator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}
