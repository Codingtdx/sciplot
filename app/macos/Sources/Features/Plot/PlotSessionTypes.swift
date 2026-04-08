import Foundation

enum PlotPreviewRefreshPolicy {
    case immediate
    case debounced
}

struct PlotTemplateGalleryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let hint: String
    let selectable: Bool
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
