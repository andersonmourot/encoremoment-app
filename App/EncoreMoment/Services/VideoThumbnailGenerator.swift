import AVFoundation
import Foundation
import UIKit

enum VideoThumbnailGenerator {
    /// Extracts a poster frame directly from the picked file — no in-memory
    /// copy of the video data needed.
    static func jpegData(for fileURL: URL) throws -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        let image = try generator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}
