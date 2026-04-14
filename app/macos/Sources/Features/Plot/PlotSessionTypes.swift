import CoreGraphics
import Foundation

enum PlotPreviewRefreshPolicy {
    case immediate
    case debounced
}

struct PlotTemplateGalleryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let thumbnailKind: PlotTemplateThumbnailKind
    let aspectRatio: CGFloat
    let availability: ActionAvailability

    var selectable: Bool {
        availability.isEnabled
    }
}

struct PlotSampleColumn: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct PlotSampleRow: Identifiable, Hashable {
    let id: Int
    let values: [JSONValue]

    func value(at index: Int) -> JSONValue {
        guard values.indices.contains(index) else {
            return .null
        }
        return values[index]
    }
}
