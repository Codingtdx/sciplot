import AppKit
import Foundation

enum PreviewImageDecoder {
    static func decodeBase64PNG(_ base64: String) -> NSImage? {
        guard
            let data = Data(base64Encoded: base64),
            let image = NSImage(data: data)
        else {
            return nil
        }
        return image
    }
}
