import Foundation
import UIKit

/// Shared image loader with a memory cache on top of a big `URLCache` disk
/// cache. `AsyncImage` does neither — every cell that scrolled off-screen
/// re-fetched and re-decoded its image. In-flight requests are coalesced so
/// two cells showing the same URL don't fetch twice.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        session = URLSession(configuration: config)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            memoryCache.setObject(result, forKey: url as NSURL)
        }
        return result
    }
}
