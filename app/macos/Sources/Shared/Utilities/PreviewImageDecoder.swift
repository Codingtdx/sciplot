import AppKit
import Foundation

@MainActor
enum PreviewImageDecoder {
    private static let dataCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 48
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    static func fingerprint(forBase64 payload: String) -> Int {
        var hasher = Hasher()
        hasher.combine(payload.count)
        hasher.combine(payload.prefix(32))
        hasher.combine(payload.suffix(32))
        return hasher.finalize()
    }

    static func decodeBase64Data(_ base64: String) -> Data? {
        let key = cacheKey(forBase64: base64)
        if let cached = dataCache.object(forKey: key) {
            return Data(referencing: cached)
        }
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        let bridged = data as NSData
        dataCache.setObject(bridged, forKey: key, cost: data.count)
        return data
    }

    static func decodeBase64PNG(_ base64: String) -> NSImage? {
        let key = cacheKey(forBase64: base64)
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard
            let data = decodeBase64Data(base64),
            let image = NSImage(data: data)
        else {
            return nil
        }
        imageCache.setObject(image, forKey: key)
        return image
    }

    static func looksLikePDFData(_ data: Data) -> Bool {
        guard data.count >= 4 else {
            return false
        }
        return data.starts(with: [0x25, 0x50, 0x44, 0x46]) // %PDF
    }

    private static func cacheKey(forBase64 payload: String) -> NSString {
        NSString(string: String(fingerprint(forBase64: payload)))
    }
}
