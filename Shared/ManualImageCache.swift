import Foundation
import UIKit

@MainActor
final class ManualImageCache {
    static let shared = ManualImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 96 * 1_024 * 1_024
        cache.countLimit = 48
    }

    func image(path: String) async -> UIImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "ManualBundle/media") else { return nil }
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url, options: [.mappedIfSafe]) }.value
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString, cost: data.count)
        return image
    }

    func syncImage(path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "ManualBundle/media"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
