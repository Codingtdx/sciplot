import CoreGraphics
import Foundation

struct PlotPreviewPixelBucket: Equatable, Hashable, Sendable {
    static let pixelBucketSize = 128
    static let minPixelDimension = 512
    static let maxPixelDimension = 2600

    let config: PreviewRenderConfigPayload

    init(stageSize: CGSize, displayScale: CGFloat) {
        let scale = max(Double(displayScale), 1.0)
        var pixelWidth = max(Double(stageSize.width) * scale, Double(Self.minPixelDimension))
        var pixelHeight = max(Double(stageSize.height) * scale, Double(Self.minPixelDimension))
        let longestEdge = max(pixelWidth, pixelHeight)

        if longestEdge > Double(Self.maxPixelDimension) {
            let ratio = Double(Self.maxPixelDimension) / longestEdge
            pixelWidth *= ratio
            pixelHeight *= ratio
        }

        config = PreviewRenderConfigPayload(
            pixelWidth: Self.bucketedPixelDimension(pixelWidth),
            pixelHeight: Self.bucketedPixelDimension(pixelHeight),
            scale: scale
        )
    }

    private static func bucketedPixelDimension(_ value: Double) -> Int {
        let rounded = Int((value / Double(pixelBucketSize)).rounded()) * pixelBucketSize
        return min(max(rounded, minPixelDimension), maxPixelDimension)
    }
}

enum PlotPreviewRefreshPolicy {
    case immediate
    case debounced
}

enum PlotDataWorkbookTab: String, CaseIterable, Identifiable, Hashable {
    case sourceData
    case transformed
    case variables
    case fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceData:
            return "Source Data"
        case .transformed:
            return "Transformed"
        case .variables:
            return "Variables"
        case .fit:
            return "Fit"
        }
    }
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

struct PlotWorkbookTableRow: Identifiable, Hashable {
    let id: Int
    let values: [JSONValue]

    func value(at index: Int) -> JSONValue {
        guard values.indices.contains(index) else {
            return .null
        }
        return values[index]
    }
}
