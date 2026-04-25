import Foundation

struct ExtraAxisPayload: Codable, Equatable, Sendable {
    var enabled: Bool
    var position: String
    var bindingMode: String
    var seriesIDs: [String]
    var title: String?
    var displayUnit: String?
    var dataValue: Double
    var displayValue: Double

    init(
        enabled: Bool = false,
        position: String = "top",
        bindingMode: String = "conversion",
        seriesIDs: [String] = [],
        title: String? = nil,
        displayUnit: String? = nil,
        dataValue: Double = 1.0,
        displayValue: Double = 1.0
    ) {
        self.enabled = enabled
        self.position = position
        self.bindingMode = bindingMode
        self.seriesIDs = seriesIDs
        self.title = title
        self.displayUnit = displayUnit
        self.dataValue = dataValue
        self.displayValue = displayValue
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case position
        case bindingMode = "binding_mode"
        case seriesIDs = "series_ids"
        case title
        case displayUnit = "display_unit"
        case dataValue = "data_value"
        case displayValue = "display_value"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        position = try container.decodeIfPresent(String.self, forKey: .position) ?? "top"
        bindingMode = try container.decodeIfPresent(String.self, forKey: .bindingMode) ?? "conversion"
        seriesIDs = try container.decodeIfPresent([String].self, forKey: .seriesIDs) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        displayUnit = try container.decodeIfPresent(String.self, forKey: .displayUnit)
        dataValue = try container.decodeIfPresent(Double.self, forKey: .dataValue) ?? 1.0
        displayValue = try container.decodeIfPresent(Double.self, forKey: .displayValue) ?? 1.0
    }
}

struct ReferenceLinePayload: Codable, Equatable, Sendable {
    var enabled: Bool
    var axis: String
    var value: Double
    var label: String?

    init(
        enabled: Bool = false,
        axis: String = "y",
        value: Double = 0.0,
        label: String? = nil
    ) {
        self.enabled = enabled
        self.axis = axis
        self.value = value
        self.label = label
    }
}

struct ReferenceBandPayload: Codable, Equatable, Sendable {
    var enabled: Bool
    var axis: String
    var start: Double
    var end: Double
    var label: String?

    init(
        enabled: Bool = false,
        axis: String = "y",
        start: Double = 0.0,
        end: Double = 1.0,
        label: String? = nil
    ) {
        self.enabled = enabled
        self.axis = axis
        self.start = start
        self.end = end
        self.label = label
    }
}

struct ReferenceGuidePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var kind: String
    var axisTarget: String
    var value: Double?
    var start: Double?
    var end: Double?
    var label: String?

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        kind: String = "line",
        axisTarget: String = "y_primary",
        value: Double? = 0.0,
        start: Double? = nil,
        end: Double? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.axisTarget = axisTarget
        self.value = value
        self.start = start
        self.end = end
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case kind
        case axisTarget
        case value
        case start
        case end
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "line"
        axisTarget = try container.decodeIfPresent(String.self, forKey: .axisTarget) ?? "y_primary"
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        start = try container.decodeIfPresent(Double.self, forKey: .start)
        end = try container.decodeIfPresent(Double.self, forKey: .end)
        label = try container.decodeIfPresent(String.self, forKey: .label)
    }
}

struct AxisBreakPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var start: Double
    var end: Double
    var displayMode: String

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        start: Double = 0.0,
        end: Double = 1.0,
        displayMode: String = "compress"
    ) {
        self.id = id
        self.enabled = enabled
        self.start = start
        self.end = end
        self.displayMode = displayMode
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case start
        case end
        case displayMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0.0
        end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 1.0
        displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode) ?? "compress"
    }
}

struct TextAnnotationPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var text: String
    var coordinateSpace: String
    var x: Double
    var y: Double
    var yAxisTarget: String
    var horizontalAlignment: String
    var verticalAlignment: String
    var displayStyle: String
    var connectorEnabled: Bool
    var targetX: Double
    var targetY: Double
    var targetYAxisTarget: String

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        text: String = "",
        coordinateSpace: String = "axes_fraction",
        x: Double = 0.5,
        y: Double = 0.95,
        yAxisTarget: String = "y_primary",
        horizontalAlignment: String = "center",
        verticalAlignment: String = "top",
        displayStyle: String = "plain",
        connectorEnabled: Bool = false,
        targetX: Double = 0.5,
        targetY: Double = 0.5,
        targetYAxisTarget: String = "y_primary"
    ) {
        self.id = id
        self.enabled = enabled
        self.text = text
        self.coordinateSpace = coordinateSpace
        self.x = x
        self.y = y
        self.yAxisTarget = yAxisTarget
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.displayStyle = displayStyle
        self.connectorEnabled = connectorEnabled
        self.targetX = targetX
        self.targetY = targetY
        self.targetYAxisTarget = targetYAxisTarget
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case text
        case coordinateSpace
        case x
        case y
        case yAxisTarget
        case horizontalAlignment
        case verticalAlignment
        case displayStyle
        case connectorEnabled
        case targetX
        case targetY
        case targetYAxisTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        coordinateSpace = try container.decodeIfPresent(String.self, forKey: .coordinateSpace) ?? "axes_fraction"
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.95
        yAxisTarget = try container.decodeIfPresent(String.self, forKey: .yAxisTarget) ?? "y_primary"
        horizontalAlignment = try container.decodeIfPresent(String.self, forKey: .horizontalAlignment) ?? "center"
        verticalAlignment = try container.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "top"
        displayStyle = try container.decodeIfPresent(String.self, forKey: .displayStyle) ?? "plain"
        connectorEnabled = try container.decodeIfPresent(Bool.self, forKey: .connectorEnabled) ?? false
        targetX = try container.decodeIfPresent(Double.self, forKey: .targetX) ?? 0.5
        targetY = try container.decodeIfPresent(Double.self, forKey: .targetY) ?? 0.5
        targetYAxisTarget = try container.decodeIfPresent(String.self, forKey: .targetYAxisTarget) ?? "y_primary"
    }
}

struct ShapeAnnotationPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var kind: String
    var bracketOrientation: String
    var xStart: Double
    var xEnd: Double
    var yStart: Double
    var yEnd: Double
    var yAxisTarget: String
    var label: String?

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        kind: String = "rectangle",
        bracketOrientation: String = "horizontal",
        xStart: Double = 0.0,
        xEnd: Double = 1.0,
        yStart: Double = 0.0,
        yEnd: Double = 1.0,
        yAxisTarget: String = "y_primary",
        label: String? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.bracketOrientation = bracketOrientation
        self.xStart = xStart
        self.xEnd = xEnd
        self.yStart = yStart
        self.yEnd = yEnd
        self.yAxisTarget = yAxisTarget
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case kind
        case bracketOrientation
        case xStart
        case xEnd
        case yStart
        case yEnd
        case yAxisTarget
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "rectangle"
        bracketOrientation = try container.decodeIfPresent(String.self, forKey: .bracketOrientation) ?? "horizontal"
        xStart = try container.decodeIfPresent(Double.self, forKey: .xStart) ?? 0.0
        xEnd = try container.decodeIfPresent(Double.self, forKey: .xEnd) ?? 1.0
        yStart = try container.decodeIfPresent(Double.self, forKey: .yStart) ?? 0.0
        yEnd = try container.decodeIfPresent(Double.self, forKey: .yEnd) ?? 1.0
        yAxisTarget = try container.decodeIfPresent(String.self, forKey: .yAxisTarget) ?? "y_primary"
        label = try container.decodeIfPresent(String.self, forKey: .label)
    }
}

struct AnalyticalLayerPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var kind: String
    var expression: String
    var xStart: Double
    var xEnd: Double
    var sampleCount: Int
    var yAxisTarget: String
    var label: String?

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        kind: String = "function",
        expression: String = "sin(x)",
        xStart: Double = 0.0,
        xEnd: Double = 1.0,
        sampleCount: Int = 200,
        yAxisTarget: String = "y_primary",
        label: String? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.expression = expression
        self.xStart = xStart
        self.xEnd = xEnd
        self.sampleCount = sampleCount
        self.yAxisTarget = yAxisTarget
        self.label = label
    }
}

struct DataTransformPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var kind: String
    var label: String?
    var targetColumn: String?
    var expression: String?
    var column: String?
    var filterOperator: String
    var value: JSONValue?
    var lower: Double?
    var upper: Double?
    var xColumn: String?
    var yColumn: String?
    var zColumn: String?
    var outputMode: String
    var columns: [String]?
    var targetType: String?
    var ascending: Bool
    var bins: Int?
    var window: Int?
    var method: String?
    var groupBy: [String]?
    var valueColumns: [String]?
    var statistics: [String]?

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        kind: String = "derived_column",
        label: String? = nil,
        targetColumn: String? = nil,
        expression: String? = nil,
        column: String? = nil,
        filterOperator: String = "eq",
        value: JSONValue? = nil,
        lower: Double? = nil,
        upper: Double? = nil,
        xColumn: String? = nil,
        yColumn: String? = nil,
        zColumn: String? = nil,
        outputMode: String = "xyz_long",
        columns: [String]? = nil,
        targetType: String? = nil,
        ascending: Bool = true,
        bins: Int? = nil,
        window: Int? = nil,
        method: String? = nil,
        groupBy: [String]? = nil,
        valueColumns: [String]? = nil,
        statistics: [String]? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.label = label
        self.targetColumn = targetColumn
        self.expression = expression
        self.column = column
        self.filterOperator = filterOperator
        self.value = value
        self.lower = lower
        self.upper = upper
        self.xColumn = xColumn
        self.yColumn = yColumn
        self.zColumn = zColumn
        self.outputMode = outputMode
        self.columns = columns
        self.targetType = targetType
        self.ascending = ascending
        self.bins = bins
        self.window = window
        self.method = method
        self.groupBy = groupBy
        self.valueColumns = valueColumns
        self.statistics = statistics
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case kind
        case label
        case targetColumn
        case expression
        case column
        case filterOperator = "operator"
        case value
        case lower
        case upper
        case xColumn
        case yColumn
        case zColumn
        case outputMode
        case columns
        case targetType
        case ascending
        case bins
        case window
        case method
        case groupBy
        case valueColumns
        case statistics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "derived_column"
        label = try container.decodeIfPresent(String.self, forKey: .label)
        targetColumn = try container.decodeIfPresent(String.self, forKey: .targetColumn)
        expression = try container.decodeIfPresent(String.self, forKey: .expression)
        column = try container.decodeIfPresent(String.self, forKey: .column)
        filterOperator = try container.decodeIfPresent(String.self, forKey: .filterOperator) ?? "eq"
        value = try container.decodeIfPresent(JSONValue.self, forKey: .value)
        lower = try container.decodeIfPresent(Double.self, forKey: .lower)
        upper = try container.decodeIfPresent(Double.self, forKey: .upper)
        xColumn = try container.decodeIfPresent(String.self, forKey: .xColumn)
        yColumn = try container.decodeIfPresent(String.self, forKey: .yColumn)
        zColumn = try container.decodeIfPresent(String.self, forKey: .zColumn)
        outputMode = try container.decodeIfPresent(String.self, forKey: .outputMode) ?? "xyz_long"
        columns = try container.decodeIfPresent([String].self, forKey: .columns)
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        bins = try container.decodeIfPresent(Int.self, forKey: .bins)
        window = try container.decodeIfPresent(Int.self, forKey: .window)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        groupBy = try container.decodeIfPresent([String].self, forKey: .groupBy)
        valueColumns = try container.decodeIfPresent([String].self, forKey: .valueColumns)
        statistics = try container.decodeIfPresent([String].self, forKey: .statistics)
    }
}

struct DataVariablePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var enabled: Bool
    var kind: String
    var label: String?
    var value: Double?
    var expression: String?

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        kind: String = "scalar",
        label: String? = nil,
        value: Double? = 1.0,
        expression: String? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.label = label
        self.value = value
        self.expression = expression
    }
}

struct RenderOptionsPayload: Codable, Equatable, Sendable {
    var size: String?
    var xscale: String?
    var yscale: String?
    var reverseX: Bool
    var xMin: Double?
    var xMax: Double?
    var yMin: Double?
    var yMax: Double?
    var xTickDensity: String?
    var yTickDensity: String?
    var xTickEdgeLabels: String?
    var yTickEdgeLabels: String?
    var seriesOrder: [String]?
    var xLabelOverride: String?
    var yLabelOverride: String?
    var baseline: String?
    var showColorbar: Bool?
    var stylePreset: String
    var palettePreset: String
    var useSidecar: Bool?
    var visualThemeID: String?
    var extraXAxis: ExtraAxisPayload?
    var extraYAxis: ExtraAxisPayload?
    var xAxisBreaks: [AxisBreakPayload]?
    var yAxisBreaks: [AxisBreakPayload]?
    var referenceGuides: [ReferenceGuidePayload]?
    var textAnnotations: [TextAnnotationPayload]?
    var shapeAnnotations: [ShapeAnnotationPayload]?
    var analyticalLayers: [AnalyticalLayerPayload]?
    var dataVariables: [DataVariablePayload]?
    var dataTransforms: [DataTransformPayload]?

    init(
        size: String? = nil,
        xscale: String? = nil,
        yscale: String? = nil,
        reverseX: Bool = false,
        xMin: Double? = nil,
        xMax: Double? = nil,
        yMin: Double? = nil,
        yMax: Double? = nil,
        xTickDensity: String? = nil,
        yTickDensity: String? = nil,
        xTickEdgeLabels: String? = nil,
        yTickEdgeLabels: String? = nil,
        seriesOrder: [String]? = nil,
        xLabelOverride: String? = nil,
        yLabelOverride: String? = nil,
        baseline: String? = nil,
        showColorbar: Bool? = nil,
        stylePreset: String = "nature",
        palettePreset: String = "colorblind_safe",
        useSidecar: Bool? = nil,
        visualThemeID: String? = nil,
        extraXAxis: ExtraAxisPayload? = nil,
        extraYAxis: ExtraAxisPayload? = nil,
        xAxisBreaks: [AxisBreakPayload]? = nil,
        yAxisBreaks: [AxisBreakPayload]? = nil,
        referenceGuides: [ReferenceGuidePayload]? = nil,
        textAnnotations: [TextAnnotationPayload]? = nil,
        shapeAnnotations: [ShapeAnnotationPayload]? = nil,
        analyticalLayers: [AnalyticalLayerPayload]? = nil,
        dataVariables: [DataVariablePayload]? = nil,
        dataTransforms: [DataTransformPayload]? = nil
    ) {
        self.size = size
        self.xscale = xscale
        self.yscale = yscale
        self.reverseX = reverseX
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.xTickDensity = xTickDensity
        self.yTickDensity = yTickDensity
        self.xTickEdgeLabels = xTickEdgeLabels
        self.yTickEdgeLabels = yTickEdgeLabels
        self.seriesOrder = seriesOrder
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.baseline = baseline
        self.showColorbar = showColorbar
        self.stylePreset = stylePreset
        self.palettePreset = palettePreset
        self.useSidecar = useSidecar
        self.visualThemeID = visualThemeID
        self.extraXAxis = extraXAxis
        self.extraYAxis = extraYAxis
        self.xAxisBreaks = xAxisBreaks
        self.yAxisBreaks = yAxisBreaks
        self.referenceGuides = referenceGuides
        self.textAnnotations = textAnnotations
        self.shapeAnnotations = shapeAnnotations
        self.analyticalLayers = analyticalLayers
        self.dataVariables = dataVariables
        self.dataTransforms = dataTransforms
    }

    enum CodingKeys: String, CodingKey {
        case size
        case xscale
        case yscale
        case reverseX
        case xMin
        case xMax
        case yMin
        case yMax
        case xTickDensity
        case yTickDensity
        case xTickEdgeLabels
        case yTickEdgeLabels
        case seriesOrder
        case xLabelOverride
        case yLabelOverride
        case baseline
        case showColorbar
        case stylePreset
        case palettePreset
        case useSidecar
        case visualThemeID = "visualThemeId"
        case extraXAxis
        case extraYAxis
        case xAxisBreaks
        case yAxisBreaks
        case referenceGuides
        case referenceLine
        case referenceBand
        case textAnnotations
        case shapeAnnotations
        case analyticalLayers
        case dataVariables
        case dataTransforms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(String.self, forKey: .size)
        xscale = try container.decodeIfPresent(String.self, forKey: .xscale)
        yscale = try container.decodeIfPresent(String.self, forKey: .yscale)
        reverseX = try container.decodeIfPresent(Bool.self, forKey: .reverseX) ?? false
        xMin = try container.decodeIfPresent(Double.self, forKey: .xMin)
        xMax = try container.decodeIfPresent(Double.self, forKey: .xMax)
        yMin = try container.decodeIfPresent(Double.self, forKey: .yMin)
        yMax = try container.decodeIfPresent(Double.self, forKey: .yMax)
        xTickDensity = try container.decodeIfPresent(String.self, forKey: .xTickDensity)
        yTickDensity = try container.decodeIfPresent(String.self, forKey: .yTickDensity)
        xTickEdgeLabels = try container.decodeIfPresent(String.self, forKey: .xTickEdgeLabels)
        yTickEdgeLabels = try container.decodeIfPresent(String.self, forKey: .yTickEdgeLabels)
        seriesOrder = try container.decodeIfPresent([String].self, forKey: .seriesOrder)
        xLabelOverride = try container.decodeIfPresent(String.self, forKey: .xLabelOverride)
        yLabelOverride = try container.decodeIfPresent(String.self, forKey: .yLabelOverride)
        baseline = try container.decodeIfPresent(String.self, forKey: .baseline)
        showColorbar = try container.decodeIfPresent(Bool.self, forKey: .showColorbar)
        stylePreset = try container.decodeIfPresent(String.self, forKey: .stylePreset) ?? "nature"
        palettePreset = try container.decodeIfPresent(String.self, forKey: .palettePreset) ?? "colorblind_safe"
        useSidecar = try container.decodeIfPresent(Bool.self, forKey: .useSidecar)
        visualThemeID = try container.decodeIfPresent(String.self, forKey: .visualThemeID)
        extraXAxis = try container.decodeIfPresent(ExtraAxisPayload.self, forKey: .extraXAxis)
        extraYAxis = try container.decodeIfPresent(ExtraAxisPayload.self, forKey: .extraYAxis)
        xAxisBreaks = try container.decodeIfPresent([AxisBreakPayload].self, forKey: .xAxisBreaks)
        yAxisBreaks = try container.decodeIfPresent([AxisBreakPayload].self, forKey: .yAxisBreaks)
        referenceGuides = try container.decodeIfPresent([ReferenceGuidePayload].self, forKey: .referenceGuides)
        if referenceGuides == nil {
            var legacyGuides: [ReferenceGuidePayload] = []
            if let legacyLine = try container.decodeIfPresent(ReferenceLinePayload.self, forKey: .referenceLine) {
                legacyGuides.append(
                    ReferenceGuidePayload(
                        id: "reference-line-1",
                        enabled: legacyLine.enabled,
                        kind: "line",
                        axisTarget: legacyLine.axis == "x" ? "x" : "y_primary",
                        value: legacyLine.value,
                        label: legacyLine.label
                    )
                )
            }
            if let legacyBand = try container.decodeIfPresent(ReferenceBandPayload.self, forKey: .referenceBand) {
                legacyGuides.append(
                    ReferenceGuidePayload(
                        id: "reference-band-1",
                        enabled: legacyBand.enabled,
                        kind: "band",
                        axisTarget: legacyBand.axis == "x" ? "x" : "y_primary",
                        value: nil,
                        start: legacyBand.start,
                        end: legacyBand.end,
                        label: legacyBand.label
                    )
                )
            }
            referenceGuides = legacyGuides.isEmpty ? nil : legacyGuides
        }
        textAnnotations = try container.decodeIfPresent([TextAnnotationPayload].self, forKey: .textAnnotations)
        shapeAnnotations = try container.decodeIfPresent([ShapeAnnotationPayload].self, forKey: .shapeAnnotations)
        analyticalLayers = try container.decodeIfPresent([AnalyticalLayerPayload].self, forKey: .analyticalLayers)
        dataVariables = try container.decodeIfPresent([DataVariablePayload].self, forKey: .dataVariables)
        dataTransforms = try container.decodeIfPresent([DataTransformPayload].self, forKey: .dataTransforms)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(xscale, forKey: .xscale)
        try container.encodeIfPresent(yscale, forKey: .yscale)
        try container.encode(reverseX, forKey: .reverseX)
        try container.encodeIfPresent(xMin, forKey: .xMin)
        try container.encodeIfPresent(xMax, forKey: .xMax)
        try container.encodeIfPresent(yMin, forKey: .yMin)
        try container.encodeIfPresent(yMax, forKey: .yMax)
        try container.encodeIfPresent(xTickDensity, forKey: .xTickDensity)
        try container.encodeIfPresent(yTickDensity, forKey: .yTickDensity)
        try container.encodeIfPresent(xTickEdgeLabels, forKey: .xTickEdgeLabels)
        try container.encodeIfPresent(yTickEdgeLabels, forKey: .yTickEdgeLabels)
        try container.encodeIfPresent(seriesOrder, forKey: .seriesOrder)
        try container.encodeIfPresent(xLabelOverride, forKey: .xLabelOverride)
        try container.encodeIfPresent(yLabelOverride, forKey: .yLabelOverride)
        try container.encodeIfPresent(baseline, forKey: .baseline)
        try container.encodeIfPresent(showColorbar, forKey: .showColorbar)
        try container.encode(stylePreset, forKey: .stylePreset)
        try container.encode(palettePreset, forKey: .palettePreset)
        try container.encodeIfPresent(useSidecar, forKey: .useSidecar)
        try container.encodeIfPresent(visualThemeID, forKey: .visualThemeID)
        try container.encodeIfPresent(extraXAxis, forKey: .extraXAxis)
        try container.encodeIfPresent(extraYAxis, forKey: .extraYAxis)
        try container.encodeIfPresent(xAxisBreaks, forKey: .xAxisBreaks)
        try container.encodeIfPresent(yAxisBreaks, forKey: .yAxisBreaks)
        try container.encodeIfPresent(referenceGuides, forKey: .referenceGuides)
        try container.encodeIfPresent(textAnnotations, forKey: .textAnnotations)
        try container.encodeIfPresent(shapeAnnotations, forKey: .shapeAnnotations)
        try container.encodeIfPresent(analyticalLayers, forKey: .analyticalLayers)
        try container.encodeIfPresent(dataVariables, forKey: .dataVariables)
        try container.encodeIfPresent(dataTransforms, forKey: .dataTransforms)
    }
}

struct FitOptionsPayload: Codable, Equatable, Sendable {
    var enabled: Bool
    var modelID: String
    var customFunction: FitCustomFunctionPayload?

    init(enabled: Bool = false, modelID: String = "linear", customFunction: FitCustomFunctionPayload? = nil) {
        self.enabled = enabled
        self.modelID = modelID
        self.customFunction = customFunction
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case modelID = "modelId"
        case customFunction
    }
}

struct FitCustomParameterPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var initial: Double
}

struct FitCustomFunctionPayload: Codable, Equatable, Sendable {
    var expression: String
    var parameters: [FitCustomParameterPayload]
}

struct FileRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let options: RenderOptionsPayload?

    init(inputPath: String, sheet: SheetValue, options: RenderOptionsPayload? = nil) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.options = options
    }
}

struct SourceTablePreviewRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let offset: Int
    let limit: Int
    let encoding: String?
    let delimiter: String?
    let segmentID: String?
    let headerRowIndex: Int?
    let unitRowIndex: Int?
    let dataStartRowIndex: Int?
    let options: RenderOptionsPayload?

    init(
        inputPath: String,
        sheet: SheetValue = .index(0),
        offset: Int = 0,
        limit: Int = 50,
        encoding: String? = nil,
        delimiter: String? = nil,
        segmentID: String? = nil,
        headerRowIndex: Int? = nil,
        unitRowIndex: Int? = nil,
        dataStartRowIndex: Int? = nil,
        options: RenderOptionsPayload? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.offset = offset
        self.limit = limit
        self.encoding = encoding
        self.delimiter = delimiter
        self.segmentID = segmentID
        self.headerRowIndex = headerRowIndex
        self.unitRowIndex = unitRowIndex
        self.dataStartRowIndex = dataStartRowIndex
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case offset
        case limit
        case encoding
        case delimiter
        case segmentID = "segment_id"
        case headerRowIndex = "header_row_index"
        case unitRowIndex = "unit_row_index"
        case dataStartRowIndex = "data_start_row_index"
        case options
    }
}

struct SourceTableSegmentResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let sheetName: String
    let label: String
    let resultLabel: String?
    let intervalIndex: Int?
    let startRow: Int
    let endRow: Int
    let headerRowIndex: Int?
    let unitRowIndex: Int?
    let dataStartRowIndex: Int?
    let columnCount: Int
    let rowCount: Int
}

struct SourceTablePreviewResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let offset: Int
    let limit: Int
    let totalRows: Int
    let totalCols: Int
    let columnHeaders: [String]
    let rows: [[JSONValue]]
    let candidateRoles: PlotCandidateRolesResponse
    let detectedXLabel: String?
    let detectedYLabel: String?
    let columnProfiles: [PlotColumnProfileResponse]
    let segments: [SourceTableSegmentResponse]
    let selectedSegmentID: String?
    let encoding: String?
    let delimiter: String?

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case offset
        case limit
        case totalRows
        case totalCols
        case columnHeaders
        case rows
        case candidateRoles
        case detectedXLabel
        case detectedYLabel
        case columnProfiles
        case segments
        case selectedSegmentID = "selectedSegmentId"
        case encoding
        case delimiter
    }

    init(
        inputPath: String,
        sheet: SheetValue,
        offset: Int,
        limit: Int,
        totalRows: Int,
        totalCols: Int,
        columnHeaders: [String],
        rows: [[JSONValue]],
        candidateRoles: PlotCandidateRolesResponse,
        detectedXLabel: String?,
        detectedYLabel: String?,
        columnProfiles: [PlotColumnProfileResponse] = [],
        segments: [SourceTableSegmentResponse] = [],
        selectedSegmentID: String? = nil,
        encoding: String? = nil,
        delimiter: String? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.offset = offset
        self.limit = limit
        self.totalRows = totalRows
        self.totalCols = totalCols
        self.columnHeaders = columnHeaders
        self.rows = rows
        self.candidateRoles = candidateRoles
        self.detectedXLabel = detectedXLabel
        self.detectedYLabel = detectedYLabel
        self.columnProfiles = columnProfiles
        self.segments = segments
        self.selectedSegmentID = selectedSegmentID
        self.encoding = encoding
        self.delimiter = delimiter
    }
}

struct FitAnalysisRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let modelID: String
    let seriesID: String?
    let offset: Int
    let limit: Int
    let options: RenderOptionsPayload?
    let customFunction: FitCustomFunctionPayload?

    init(
        inputPath: String,
        sheet: SheetValue,
        modelID: String = "linear",
        seriesID: String? = nil,
        offset: Int = 0,
        limit: Int = 50,
        options: RenderOptionsPayload? = nil,
        customFunction: FitCustomFunctionPayload? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.modelID = modelID
        self.seriesID = seriesID
        self.offset = offset
        self.limit = limit
        self.options = options
        self.customFunction = customFunction
    }

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case modelID = "modelId"
        case seriesID = "seriesId"
        case offset
        case limit
        case options
        case customFunction
    }
}

struct FitDerivedRowResponse: Codable, Equatable, Sendable, Identifiable {
    let rowIndex: Int
    let x: Double
    let y: Double
    let yFit: Double
    let residual: Double

    var id: Int { rowIndex }
}

struct FitSeriesSummaryResponse: Codable, Equatable, Sendable, Identifiable {
    let seriesID: String
    let seriesLabel: String
    let equationDisplay: String
    let rSquared: Double
    let rmse: Double
    let pointCount: Int
    let slope: Double?
    let intercept: Double?
    let warnings: [String]

    var id: String { seriesID }

    enum CodingKeys: String, CodingKey {
        case seriesID = "seriesId"
        case seriesLabel
        case equationDisplay
        case rSquared
        case rmse
        case pointCount
        case slope
        case intercept
        case warnings
    }
}

struct FitAnalysisResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let modelID: String
    let xLabel: String?
    let yLabel: String?
    let selectedSeriesID: String?
    let equationDisplay: String
    let slope: Double?
    let intercept: Double?
    let rSquared: Double
    let rmse: Double
    let pointCount: Int
    let seriesSummaries: [FitSeriesSummaryResponse]
    let warnings: [String]
    let totalRows: Int
    let offset: Int
    let limit: Int
    let rows: [FitDerivedRowResponse]

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case modelID = "modelId"
        case xLabel
        case yLabel
        case selectedSeriesID = "selectedSeriesId"
        case equationDisplay
        case slope
        case intercept
        case rSquared
        case rmse
        case pointCount
        case seriesSummaries
        case warnings
        case totalRows
        case offset
        case limit
        case rows
    }
}

struct CodeConsoleContextRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String?
    let options: RenderOptionsPayload
    let sourceKind: String?
    let sourceLabel: String?

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String? = nil,
        options: RenderOptionsPayload = RenderOptionsPayload(),
        sourceKind: String? = nil,
        sourceLabel: String? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
    }
}

struct CodeConsoleContextResponse: Codable, Equatable, Sendable {
    let contextID: String
    let inputPath: String
    let sheet: SheetValue
    let sheetNames: [String]
    let inspection: InputInspectionResponse
    let dataset: PlotDatasetPreviewResponse?
    let template: String
    let options: RenderOptionsPayload
    let promptText: String
    let starterCode: String
    let sourceKind: String?
    let sourceLabel: String?
}

struct CodeConsoleRunRequest: Codable, Equatable, Sendable {
    let contextID: String?
    let context: CodeConsoleContextRequest?
    let code: String
    let timeoutSeconds: Int

    init(
        contextID: String? = nil,
        context: CodeConsoleContextRequest? = nil,
        code: String,
        timeoutSeconds: Int
    ) {
        self.contextID = contextID
        self.context = context
        self.code = code
        self.timeoutSeconds = timeoutSeconds
    }
}

struct CodeConsoleGeneratedFileResponse: Codable, Equatable, Sendable, Identifiable {
    let path: String
    let name: String
    let fileType: String
    let sizeBytes: Int

    var id: String { path }
}

struct CodeConsoleRunResponse: Codable, Equatable, Sendable {
    let status: String
    let exitCode: Int?
    let durationSeconds: Double
    let stdout: String
    let stderr: String
    let runDir: String
    let outputDir: String
    let scriptPath: String
    let promptPath: String
    let contextPath: String
    let stdoutPath: String
    let stderrPath: String
    let generatedFiles: [CodeConsoleGeneratedFileResponse]
}

struct RenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let fitOptions: FitOptionsPayload

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String,
        options: RenderOptionsPayload,
        fitOptions: FitOptionsPayload = FitOptionsPayload()
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.fitOptions = fitOptions
    }
}

struct ExportRenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let fitOptions: FitOptionsPayload
    let outputDir: String?

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String,
        options: RenderOptionsPayload,
        fitOptions: FitOptionsPayload = FitOptionsPayload(),
        outputDir: String? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.fitOptions = fitOptions
        self.outputDir = outputDir
    }
}

struct PlotProjectSourceProvenancePayload: Codable, Equatable, Sendable {
    let originalInputPath: String?
    let savedInputMtimeNs: Int?
    let savedAt: String?
}

struct PlotProjectPayload: Codable, Equatable, Sendable {
    let sessionKind: String
    let sourceFilename: String
    let sourceMediaType: String?
    let embeddedSourceRelpath: String
    let sourceSHA256: String
    let sheet: SheetValue
    let selectedTemplateID: String
    let renderOptions: RenderOptionsPayload
    let fitOptions: FitOptionsPayload
    let projectDisplayName: String?
    let sourceProvenance: PlotProjectSourceProvenancePayload

    enum CodingKeys: String, CodingKey {
        case sessionKind
        case sourceFilename
        case sourceMediaType
        case embeddedSourceRelpath
        case sourceSHA256
        case sheet
        case selectedTemplateID
        case renderOptions
        case fitOptions
        case projectDisplayName
        case sourceProvenance
    }
}

struct DataStudioProjectWorkbookPayload: Codable, Equatable, Sendable, Identifiable {
    let workbookFilename: String
    let embeddedWorkbookRelpath: String
    let workbookSHA256: String
    let originalWorkbookPath: String?
    let savedWorkbookMtimeNs: Int?

    var id: String { embeddedWorkbookRelpath }

    enum CodingKeys: String, CodingKey {
        case workbookFilename
        case embeddedWorkbookRelpath
        case workbookSHA256
        case originalWorkbookPath
        case savedWorkbookMtimeNs
    }
}

struct DataStudioProjectPayload: Codable, Equatable, Sendable {
    let sessionKind: String
    let version: Int
    let selectedTemplateID: String?
    let workbookPaths: [String]
    let selectedWorkbookID: String?
    let primaryWorkbookID: String?
    let selectedRecipeID: String?
    let comparisonRecipeIDs: [String]
    let selectedFigureFamilyID: String?
    let selectedFigureTemplateID: String?
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]
    let figurePreferences: [DataStudioFigurePreferencePayload]
    let importedPaths: [String]
    let templateDraftPath: String?
    let embeddedWorkbooks: [DataStudioProjectWorkbookPayload]
    let projectDisplayName: String?
    let sourceProvenance: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case sessionKind
        case version
        case selectedTemplateID
        case workbookPaths
        case selectedWorkbookID
        case primaryWorkbookID
        case selectedRecipeID
        case comparisonRecipeIDs
        case selectedFigureFamilyID
        case selectedFigureTemplateID
        case groupStates
        case specimenStates
        case figurePreferences
        case importedPaths
        case templateDraftPath
        case embeddedWorkbooks
        case projectDisplayName
        case sourceProvenance
    }
}

struct ProjectBundlePayload: Codable, Equatable, Sendable {
    let version: Int
    let selectedWorkbench: String
    let plot: PlotProjectPayload?
    let dataStudio: DataStudioProjectPayload?
    let composer: JSONValue?
    let codeConsole: JSONValue?
    let artifacts: [String: JSONValue]
}

struct SaveProjectRequest: Codable, Equatable, Sendable {
    let projectPath: String
    let sourcePath: String?
    let payload: ProjectBundlePayload
}

struct SaveProjectResponse: Codable, Equatable, Sendable {
    let projectPath: String
    let payload: ProjectBundlePayload
}

struct OpenProjectRequest: Codable, Equatable, Sendable {
    let projectPath: String
}

struct OpenProjectResponse: Codable, Equatable, Sendable {
    let projectPath: String
    let restoredSourcePath: String?
    let restoredWorkbookPaths: [String]
    let payload: ProjectBundlePayload
}

struct TemplateRecommendationResponse: Codable, Equatable, Sendable, Identifiable {
    let templateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let score: Double
    let rank: Int?
    let reason: String
    let suitabilityHint: String
    let scoreGapToTop: Double
    let whyHardMatch: [String]
    let whySoftPrior: [String]
    let inferredMapping: [String: String]
    let optionalEnhancements: [String]
    let previewConfigSummary: [String: JSONValue]

    var id: String { templateID }

    enum CodingKeys: String, CodingKey {
        case templateID = "templateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case score
        case rank
        case reason
        case suitabilityHint
        case scoreGapToTop
        case whyHardMatch
        case whySoftPrior
        case inferredMapping
        case optionalEnhancements
        case previewConfigSummary
    }
}

struct InputInspectionResponse: Codable, Equatable, Sendable {
    let model: String
    let modelLabel: String
    let recommendations: [TemplateRecommendationResponse]
    let primaryRecommendation: [TemplateRecommendationResponse]
    let alternativeRecommendations: [TemplateRecommendationResponse]
    let advancedTemplates: [TemplateRecommendationResponse]
    let recommendationConfidence: Double
    let recommendationSummary: String
    let warnings: [String]
    let signals: [String]
}

struct PlotColumnProfileResponse: Codable, Equatable, Sendable {
    let name: String
    let headerPreview: [String?]
    let inferredType: String
    let nonEmptyCount: Int
    let missingCount: Int
    let minValue: Double?
    let maxValue: Double?
}

struct PlotCandidateRolesResponse: Codable, Equatable, Sendable {
    let x: [String]
    let y: [String]
    let z: [String]
    let group: [String]
    let sample: [String]
    let value: [String]
    let metric: [String]
    let label: [String]
    let series: [String]
}

struct PlotDatasetPreviewResponse: Codable, Equatable, Sendable {
    let datasetID: String
    let sourcePath: String?
    let sheet: SheetValue?
    let model: String
    let rawRows: Int
    let rawCols: Int
    let columnProfiles: [PlotColumnProfileResponse]
    let candidateRoles: PlotCandidateRolesResponse
    let dataShapes: [String]
    let semanticSignals: [String]
    let qualityFlags: [String]
    let sampleRows: [[JSONValue]]

    enum CodingKeys: String, CodingKey {
        case datasetID = "datasetId"
        case sourcePath
        case sheet
        case model
        case rawRows
        case rawCols
        case columnProfiles
        case candidateRoles
        case dataShapes
        case semanticSignals
        case qualityFlags
        case sampleRows
    }
}

struct InspectFileResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let sheetNames: [String]
    let inspection: InputInspectionResponse
    let dataset: PlotDatasetPreviewResponse?
}

struct PreflightResultResponse: Codable, Equatable, Sendable {
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let warnings: [String]
    let errors: [String]
    let outputFilenames: [String]
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case warnings
        case errors
        case outputFilenames
        case submissionReport
    }
}

struct PreflightRenderResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let sheet: SheetValue
    let options: RenderOptionsPayload
    let preflight: PreflightResultResponse

    enum CodingKeys: String, CodingKey {
        case inputPath
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case sheet
        case options
        case preflight
    }
}

struct RenderPreviewResponse: Codable, Equatable, Sendable {
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let sheet: SheetValue
    let previews: [PreviewItemResponse]
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case sheet
        case previews
        case submissionReport
    }
}

struct ExportRenderResponse: Codable, Equatable, Sendable {
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let outputs: [String]
    let outputDir: String
    let previewOutputs: [String]
    let artifactPaths: [String]
    let manifestPath: String?
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case outputs
        case outputDir
        case previewOutputs
        case artifactPaths
        case manifestPath
        case submissionReport
    }
}

struct MetaDefaultsResponse: Codable, Equatable, Sendable {
    let stylePreset: String
    let palettePreset: String
}

struct MetaSizeResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let widthMm: Double
    let heightMm: Double
}

struct MetaStyleResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let `public`: Bool
    let description: String
    let hardConstraints: Bool
    let presetNote: String
    let recommendedPalettePreset: String
    let recommendedVisualThemeID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case `public`
        case description
        case hardConstraints
        case presetNote
        case recommendedPalettePreset
        case recommendedVisualThemeID = "recommendedVisualThemeId"
    }
}

struct MetaPaletteResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let `public`: Bool
    let description: String
    let swatches: [String]
}

struct MetaTemplateSummary: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
    let category: String
    let presentationKind: String
    let defaultSize: String
    let allowedSizes: [String]
    let editableOptions: [String]
    let defaultOptions: [String: JSONValue]
    let availableStyles: [String]
    let availablePalettes: [String]
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case description
        case category
        case presentationKind
        case defaultSize
        case allowedSizes
        case editableOptions
        case defaultOptions
        case availableStyles
        case availablePalettes
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
    }
}

struct VisualThemeResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
}

struct SidecarMetaResponse: Codable, Equatable, Sendable {
    let version: Int
    let defaults: MetaDefaultsResponse
    let sizes: [MetaSizeResponse]
    let styles: [MetaStyleResponse]
    let palettes: [MetaPaletteResponse]
    let templates: [MetaTemplateSummary]
    let templateIds: [String]
    let sizeIds: [String]
    let palettePresetIds: [String]
    let visualThemes: [VisualThemeResponse]
}

struct ContractTemplateResponse: Codable, Equatable, Sendable {
    let label: String
    let description: String
    let category: String
    let presentationKind: String
    let defaultSize: String
    let allowedSizes: [String]
    let editableOptions: [String]
    let defaultOptions: [String: JSONValue]
    let availableStyles: [String]
    let availablePalettes: [String]
    let hardRules: [String]
    let softRules: [String]
}

struct ContractSizePresetResponse: Codable, Equatable, Sendable {
    let label: String
    let widthMm: Double
    let heightMm: Double
}

struct PlotContractResponse: Codable, Equatable, Sendable {
    let version: Int
    let defaults: MetaDefaultsResponse
    let sizePresets: [String: ContractSizePresetResponse]
    let styles: [String: JSONValue]
    let palettes: [String: JSONValue]
    let templates: [String: ContractTemplateResponse]
}
