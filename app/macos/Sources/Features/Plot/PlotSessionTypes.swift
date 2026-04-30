import CoreGraphics
import Foundation

struct PlotPreviewPixelBucket: Equatable, Hashable, Sendable {
    static let pixelBucketSize = 128
    static let minPixelDimension = 512
    static let maxPixelDimension = 4200

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

struct PlotCanvasDataPoint: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

enum PlotCanvasInteractionMode: Equatable, Hashable, Identifiable, Sendable {
    case select
    case text
    case callout
    case rectangle
    case ellipse
    case bracket
    case guideLine(axisTarget: String)
    case guideRegion(axisTarget: String)

    var id: String {
        switch self {
        case .select:
            return "select"
        case .text:
            return "text"
        case .callout:
            return "callout"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "ellipse"
        case .bracket:
            return "bracket"
        case .guideLine(let axisTarget):
            return "guide-line:\(axisTarget)"
        case .guideRegion(let axisTarget):
            return "guide-region:\(axisTarget)"
        }
    }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .text:
            return "Text"
        case .callout:
            return "Callout"
        case .rectangle:
            return "Rectangle"
        case .ellipse:
            return "Ellipse"
        case .bracket:
            return "Bracket"
        case .guideLine(let axisTarget):
            return axisTarget == "x" ? "X Line" : "Y Line"
        case .guideRegion(let axisTarget):
            return axisTarget == "x" ? "X Region" : "Y Region"
        }
    }

    var systemImage: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .text:
            return "character.cursor.ibeam"
        case .callout:
            return "text.bubble"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "oval"
        case .bracket:
            return "square.split.diagonal"
        case .guideLine:
            return "ruler"
        case .guideRegion:
            return "rectangle.dashed"
        }
    }

    var requiresDrag: Bool {
        switch self {
        case .rectangle, .ellipse, .bracket, .guideRegion:
            return true
        case .select, .text, .callout, .guideLine:
            return false
        }
    }

    var isPlacementMode: Bool {
        self != .select
    }
}

enum PlotCanvasDraft: Equatable, Sendable {
    case text(point: PlotCanvasDataPoint, displayStyle: String, connectorTarget: PlotCanvasDataPoint?)
    case shape(kind: String, start: PlotCanvasDataPoint, end: PlotCanvasDataPoint)
    case guideLine(axisTarget: String, value: Double)
    case guideRegion(axisTarget: String, start: Double, end: Double)
}

enum PlotCanvasResizeHandle: Equatable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case start
    case end
}

enum PlotOverlayHitTarget: Equatable, Hashable, Sendable {
    case move(PlotLayerSelection)
    case resizeShape(id: String, handle: PlotCanvasResizeHandle)
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
