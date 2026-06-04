import UIKit

/// Loads and caches images served from Penpot's `/assets/by-id/<media-id>` endpoint.
/// The shared cookie storage carries the auth cookie automatically.
/// `NSCache` and `URLSession` are thread-safe, so this is safe to use from any task.
final class RemoteImageLoader: @unchecked Sendable {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func assetURL(mediaID: String, baseURL: URL) -> URL {
        baseURL.appendingPathComponent("assets/by-id/\(mediaID)")
    }

    func image(mediaID: String, baseURL: URL) async -> UIImage? {
        await image(at: assetURL(mediaID: mediaID, baseURL: baseURL))
    }

    func image(at url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}
