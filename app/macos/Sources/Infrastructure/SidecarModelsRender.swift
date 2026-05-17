import Foundation

struct CustomPlotThemePalettePayload: Codable, Equatable, Sendable {
    var categorical: [String]

    init(categorical: [String] = []) {
        self.categorical = categorical
    }
}

struct CustomPlotThemePackagePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var baseStyleID: String
    var palettePreset: String?
    var visualThemeID: String?
    var palette: CustomPlotThemePalettePayload
    var hardOverrides: [String: [String: JSONValue]]
    var softOverrides: [String: JSONValue]
    var expertRcParams: [String: JSONValue]

    init(
        id: String,
        label: String,
        baseStyleID: String = "nature",
        palettePreset: String? = nil,
        visualThemeID: String? = nil,
        palette: CustomPlotThemePalettePayload = .init(),
        hardOverrides: [String: [String: JSONValue]] = [:],
        softOverrides: [String: JSONValue] = [:],
        expertRcParams: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.label = label
        self.baseStyleID = baseStyleID
        self.palettePreset = palettePreset
        self.visualThemeID = visualThemeID
        self.palette = palette
        self.hardOverrides = hardOverrides
        self.softOverrides = softOverrides
        self.expertRcParams = expertRcParams
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case baseStyleID = "baseStyleId"
        case palettePreset
        case visualThemeID = "visualThemeId"
        case palette
        case hardOverrides
        case softOverrides
        case expertRcParams = "expertRcparams"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        baseStyleID = try container.decodeIfPresent(String.self, forKey: .baseStyleID) ?? "nature"
        palettePreset = try container.decodeIfPresent(String.self, forKey: .palettePreset)
        visualThemeID = try container.decodeIfPresent(String.self, forKey: .visualThemeID)
        palette = try container.decodeIfPresent(CustomPlotThemePalettePayload.self, forKey: .palette) ?? .init()
        hardOverrides = try container.decodeIfPresent([String: [String: JSONValue]].self, forKey: .hardOverrides) ?? [:]
        softOverrides = try container.decodeIfPresent([String: JSONValue].self, forKey: .softOverrides) ?? [:]
        expertRcParams = try container.decodeIfPresent([String: JSONValue].self, forKey: .expertRcParams) ?? [:]
    }
}

struct PlotThemeSummaryResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let builtin: Bool
    let baseStyleID: String
    let palettePreset: String?
    let visualThemeID: String?
    let swatches: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case builtin
        case baseStyleID = "baseStyleId"
        case palettePreset
        case visualThemeID = "visualThemeId"
        case swatches
    }
}

struct PlotThemeListResponse: Codable, Equatable, Sendable {
    let themes: [PlotThemeSummaryResponse]
}

struct PlotThemePreviewRequest: Codable, Equatable, Sendable {
    let theme: CustomPlotThemePackagePayload
}

struct PlotThemePreviewResponse: Codable, Equatable, Sendable {
    let theme: CustomPlotThemePackagePayload
    let blockedKeys: [String]
    let warnings: [String]
}

struct PlotThemeSaveRequest: Codable, Equatable, Sendable {
    let theme: CustomPlotThemePackagePayload
}

struct PlotThemeSaveResponse: Codable, Equatable, Sendable {
    let theme: CustomPlotThemePackagePayload
    let blockedKeys: [String]
    let warnings: [String]
}

struct ScientificTextRulePayload: Codable, Equatable, Sendable {
    var id: String?
    var kind: String
    var input: String
    var output: String
    var enabled: Bool
    var canonicalInput: String?

    init(
        id: String? = nil,
        kind: String = "unit",
        input: String = "",
        output: String = "",
        enabled: Bool = true,
        canonicalInput: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.input = input
        self.output = output
        self.enabled = enabled
        self.canonicalInput = canonicalInput
    }
}

struct ScientificTextRuleResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let input: String
    let output: String
    let enabled: Bool
    let canonicalInput: String
}

struct ScientificTextRuleListResponse: Codable, Equatable, Sendable {
    let rules: [ScientificTextRuleResponse]
}

struct ScientificTextRulePreviewResponse: Codable, Equatable, Sendable {
    let rule: ScientificTextRuleResponse
    let automaticOutput: String
    let effectiveOutput: String
    let errors: [String]
    let warnings: [String]
}

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
        case bindingMode
        case bindingModeLegacy = "binding_mode"
        case seriesIDs = "seriesIds"
        case seriesIDsLegacy = "series_ids"
        case title
        case displayUnit
        case displayUnitLegacy = "display_unit"
        case dataValue
        case dataValueLegacy = "data_value"
        case displayValue
        case displayValueLegacy = "display_value"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        position = try container.decodeIfPresent(String.self, forKey: .position) ?? "top"
        bindingMode = (
            try container.decodeIfPresent(String.self, forKey: .bindingMode)
            ?? container.decodeIfPresent(String.self, forKey: .bindingModeLegacy)
        ) ?? "conversion"
        seriesIDs = (
            try container.decodeIfPresent([String].self, forKey: .seriesIDs)
            ?? container.decodeIfPresent([String].self, forKey: .seriesIDsLegacy)
        ) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        displayUnit = try container.decodeIfPresent(String.self, forKey: .displayUnit)
            ?? container.decodeIfPresent(String.self, forKey: .displayUnitLegacy)
        dataValue = (
            try container.decodeIfPresent(Double.self, forKey: .dataValue)
            ?? container.decodeIfPresent(Double.self, forKey: .dataValueLegacy)
        ) ?? 1.0
        displayValue = (
            try container.decodeIfPresent(Double.self, forKey: .displayValue)
            ?? container.decodeIfPresent(Double.self, forKey: .displayValueLegacy)
        ) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(position, forKey: .position)
        try container.encode(bindingMode, forKey: .bindingMode)
        try container.encode(seriesIDs, forKey: .seriesIDs)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(displayUnit, forKey: .displayUnit)
        try container.encode(dataValue, forKey: .dataValue)
        try container.encode(displayValue, forKey: .displayValue)
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

struct SeriesStylePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String { seriesID }
    var seriesID: String
    var enabled: Bool
    var color: String?
    var lineWidth: Double?
    var marker: String?
    var yAxisTarget: String?

    init(
        seriesID: String,
        enabled: Bool = true,
        color: String? = nil,
        lineWidth: Double? = nil,
        marker: String? = nil,
        yAxisTarget: String? = nil
    ) {
        self.seriesID = seriesID
        self.enabled = enabled
        self.color = color
        self.lineWidth = lineWidth
        self.marker = marker
        self.yAxisTarget = yAxisTarget
    }

    enum CodingKeys: String, CodingKey {
        case seriesID = "seriesId"
        case enabled
        case color
        case lineWidth
        case marker
        case yAxisTarget
    }
}

struct SeriesOffsetPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String { seriesID }
    var seriesID: String
    var enabled: Bool
    var xOffset: Double
    var yOffset: Double
    var yAxisTarget: String?

    init(
        seriesID: String,
        enabled: Bool = true,
        xOffset: Double = 0.0,
        yOffset: Double = 0.0,
        yAxisTarget: String? = nil
    ) {
        self.seriesID = seriesID
        self.enabled = enabled
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.yAxisTarget = yAxisTarget
    }

    enum CodingKeys: String, CodingKey {
        case seriesID = "seriesId"
        case enabled
        case xOffset
        case yOffset
        case yAxisTarget
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
    var legendPosition: String?
    var xLabelOverride: String?
    var yLabelOverride: String?
    var baseline: String?
    var showColorbar: Bool?
    var stylePreset: String
    var palettePreset: String
    var useSidecar: Bool?
    var visualThemeID: String?
    var customThemeID: String?
    var customThemeDraft: CustomPlotThemePackagePayload?
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
    var seriesStyles: [SeriesStylePayload]?
    var seriesOffsets: [SeriesOffsetPayload]?

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
        legendPosition: String? = nil,
        xLabelOverride: String? = nil,
        yLabelOverride: String? = nil,
        baseline: String? = nil,
        showColorbar: Bool? = nil,
        stylePreset: String = "nature",
        palettePreset: String = "colorblind_safe",
        useSidecar: Bool? = nil,
        visualThemeID: String? = nil,
        customThemeID: String? = nil,
        customThemeDraft: CustomPlotThemePackagePayload? = nil,
        extraXAxis: ExtraAxisPayload? = nil,
        extraYAxis: ExtraAxisPayload? = nil,
        xAxisBreaks: [AxisBreakPayload]? = nil,
        yAxisBreaks: [AxisBreakPayload]? = nil,
        referenceGuides: [ReferenceGuidePayload]? = nil,
        textAnnotations: [TextAnnotationPayload]? = nil,
        shapeAnnotations: [ShapeAnnotationPayload]? = nil,
        analyticalLayers: [AnalyticalLayerPayload]? = nil,
        dataVariables: [DataVariablePayload]? = nil,
        dataTransforms: [DataTransformPayload]? = nil,
        seriesStyles: [SeriesStylePayload]? = nil,
        seriesOffsets: [SeriesOffsetPayload]? = nil
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
        self.legendPosition = legendPosition
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.baseline = baseline
        self.showColorbar = showColorbar
        self.stylePreset = stylePreset
        self.palettePreset = palettePreset
        self.useSidecar = useSidecar
        self.visualThemeID = visualThemeID
        self.customThemeID = customThemeID
        self.customThemeDraft = customThemeDraft
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
        self.seriesStyles = seriesStyles
        self.seriesOffsets = seriesOffsets
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
        case legendPosition
        case xLabelOverride
        case yLabelOverride
        case baseline
        case showColorbar
        case stylePreset
        case palettePreset
        case useSidecar
        case visualThemeID = "visualThemeId"
        case customThemeID = "customThemeId"
        case customThemeDraft
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
        case seriesStyles
        case seriesOffsets
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
        legendPosition = try container.decodeIfPresent(String.self, forKey: .legendPosition)
        xLabelOverride = try container.decodeIfPresent(String.self, forKey: .xLabelOverride)
        yLabelOverride = try container.decodeIfPresent(String.self, forKey: .yLabelOverride)
        baseline = try container.decodeIfPresent(String.self, forKey: .baseline)
        showColorbar = try container.decodeIfPresent(Bool.self, forKey: .showColorbar)
        stylePreset = try container.decodeIfPresent(String.self, forKey: .stylePreset) ?? "nature"
        palettePreset = try container.decodeIfPresent(String.self, forKey: .palettePreset) ?? "colorblind_safe"
        useSidecar = try container.decodeIfPresent(Bool.self, forKey: .useSidecar)
        visualThemeID = try container.decodeIfPresent(String.self, forKey: .visualThemeID)
        customThemeID = try container.decodeIfPresent(String.self, forKey: .customThemeID)
        customThemeDraft = try container.decodeIfPresent(CustomPlotThemePackagePayload.self, forKey: .customThemeDraft)
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
        seriesStyles = try container.decodeIfPresent([SeriesStylePayload].self, forKey: .seriesStyles)
        seriesOffsets = try container.decodeIfPresent([SeriesOffsetPayload].self, forKey: .seriesOffsets)
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
        try container.encodeIfPresent(legendPosition, forKey: .legendPosition)
        try container.encodeIfPresent(xLabelOverride, forKey: .xLabelOverride)
        try container.encodeIfPresent(yLabelOverride, forKey: .yLabelOverride)
        try container.encodeIfPresent(baseline, forKey: .baseline)
        try container.encodeIfPresent(showColorbar, forKey: .showColorbar)
        try container.encode(stylePreset, forKey: .stylePreset)
        try container.encode(palettePreset, forKey: .palettePreset)
        try container.encodeIfPresent(useSidecar, forKey: .useSidecar)
        try container.encodeIfPresent(visualThemeID, forKey: .visualThemeID)
        try container.encodeIfPresent(customThemeID, forKey: .customThemeID)
        try container.encodeIfPresent(customThemeDraft, forKey: .customThemeDraft)
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
        try container.encodeIfPresent(seriesStyles, forKey: .seriesStyles)
        try container.encodeIfPresent(seriesOffsets, forKey: .seriesOffsets)
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
    var lower: Double?
    var upper: Double?
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

struct DataContainerColumnPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let index: Int
    let roleHints: [String]
    let unit: String?
    let comment: String?
    let profile: PlotColumnProfileResponse?
}

struct DataContainerSourcePayload: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let selectedSegmentID: String?
    let encoding: String?
    let delimiter: String?
    let offset: Int
    let limit: Int
    let transformCount: Int
    let variableCount: Int

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case selectedSegmentID = "selectedSegmentId"
        case encoding
        case delimiter
        case offset
        case limit
        case transformCount
        case variableCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputPath = try container.decode(String.self, forKey: .inputPath)
        sheet = try container.decode(SheetValue.self, forKey: .sheet)
        selectedSegmentID = try container.decodeIfPresent(String.self, forKey: .selectedSegmentID)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        delimiter = try container.decodeIfPresent(String.self, forKey: .delimiter)
        offset = try container.decode(Int.self, forKey: .offset)
        limit = try container.decode(Int.self, forKey: .limit)
        transformCount = try container.decodeIfPresent(Int.self, forKey: .transformCount) ?? 0
        variableCount = try container.decodeIfPresent(Int.self, forKey: .variableCount) ?? 0
    }
}

struct DataContainerPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let status: String
    let readonly: Bool
    let rowCount: Int
    let columnCount: Int
    let columns: [DataContainerColumnPayload]
    let source: DataContainerSourcePayload
    let dimensions: [String: JSONValue]?
    let coordinateVectors: [String: [JSONValue]]
    let missingValuePolicy: String?
    let statistics: [String: JSONValue]
    let diagnostics: [[String: JSONValue]]
    let resultTables: [[String: JSONValue]]
    let overlays: [[String: JSONValue]]
    let artifactPaths: [String]
    let containerIDs: [String]
    let sourceRunID: String?
    let help: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case status
        case readonly
        case rowCount
        case columnCount
        case columns
        case source
        case dimensions
        case coordinateVectors
        case missingValuePolicy
        case statistics
        case diagnostics
        case resultTables
        case overlays
        case artifactPaths
        case containerIDs = "containerIds"
        case sourceRunID = "sourceRunId"
        case help
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        label = try container.decode(String.self, forKey: .label)
        status = try container.decode(String.self, forKey: .status)
        readonly = try container.decode(Bool.self, forKey: .readonly)
        rowCount = try container.decode(Int.self, forKey: .rowCount)
        columnCount = try container.decode(Int.self, forKey: .columnCount)
        columns = try container.decodeIfPresent([DataContainerColumnPayload].self, forKey: .columns) ?? []
        source = try container.decode(DataContainerSourcePayload.self, forKey: .source)
        dimensions = try container.decodeIfPresent([String: JSONValue].self, forKey: .dimensions)
        coordinateVectors = try container.decodeIfPresent([String: [JSONValue]].self, forKey: .coordinateVectors) ?? [:]
        missingValuePolicy = try container.decodeIfPresent(String.self, forKey: .missingValuePolicy)
        statistics = try container.decodeIfPresent([String: JSONValue].self, forKey: .statistics) ?? [:]
        diagnostics = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .diagnostics) ?? []
        resultTables = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .resultTables) ?? []
        overlays = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .overlays) ?? []
        artifactPaths = try container.decodeIfPresent([String].self, forKey: .artifactPaths) ?? []
        containerIDs = try container.decodeIfPresent([String].self, forKey: .containerIDs) ?? []
        sourceRunID = try container.decodeIfPresent(String.self, forKey: .sourceRunID)
        help = try container.decode(String.self, forKey: .help)
    }
}

struct PlotObjectPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let module: String
    let label: String
    let status: String
    let visible: Bool
    let locked: Bool
    let graphNodeID: String
    let payload: [String: JSONValue]
    let help: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case module
        case label
        case status
        case visible
        case locked
        case graphNodeID = "graphNodeId"
        case payload
        case help
    }
}

struct PlotEditCommandPayload: Codable, Equatable, Sendable, Identifiable {
    let commandID: String
    let kind: String
    let targetObjectID: String
    let before: [String: JSONValue]?
    let after: [String: JSONValue]?
    let graphPatch: [String: JSONValue]
    let reversible: Bool
    let help: String

    var id: String { commandID }

    enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case kind
        case targetObjectID = "targetObjectId"
        case before
        case after
        case graphPatch
        case reversible
        case help
    }
}

struct AnalysisOperationResultPayload: Codable, Equatable, Sendable, Identifiable {
    let operationID: String
    let available: Bool
    let valid: Bool
    let statusCode: String
    let message: String
    let diagnostics: [[String: JSONValue]]
    let metrics: [String: JSONValue]
    let tables: [[String: JSONValue]]
    let overlays: [[String: JSONValue]]
    let dataContainers: [DataContainerPayload]

    var id: String { operationID }

    enum CodingKeys: String, CodingKey {
        case operationID = "operationId"
        case available
        case valid
        case statusCode
        case message
        case diagnostics
        case metrics
        case tables
        case overlays
        case dataContainers
    }
}

struct ImportFilterPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let status: String
    let owner: String
    let surface: String
    let optionsSchema: [String: JSONValue]
    let outputContainerKinds: [String]
    let help: String
    let testRequirements: [String]
}

struct ExportTargetPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let status: String
    let owner: String
    let surface: String
    let allowedModules: [String]
    let artifactKind: String
    let filenamePolicy: String
    let help: String
    let testRequirements: [String]
}

struct NotebookOutputPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let status: String
    let sourceRunID: String
    let artifactPaths: [String]
    let containerIDs: [String]
    let help: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case status
        case sourceRunID = "sourceRunId"
        case artifactPaths
        case containerIDs = "containerIds"
        case help
    }
}

struct AnalysisOperationRequest: Codable, Equatable, Sendable {
    let operationID: String
    let inputPath: String
    let sheet: SheetValue
    let xColumn: String?
    let yColumn: String?
    let parameters: [String: JSONValue]
    let offset: Int
    let limit: Int
    let options: RenderOptionsPayload?

    init(
        operationID: String,
        inputPath: String,
        sheet: SheetValue = .index(0),
        xColumn: String? = nil,
        yColumn: String? = nil,
        parameters: [String: JSONValue] = [:],
        offset: Int = 0,
        limit: Int = 200,
        options: RenderOptionsPayload? = nil
    ) {
        self.operationID = operationID
        self.inputPath = inputPath
        self.sheet = sheet
        self.xColumn = xColumn
        self.yColumn = yColumn
        self.parameters = parameters
        self.offset = offset
        self.limit = limit
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case operationID = "operationId"
        case inputPath
        case sheet
        case xColumn
        case yColumn
        case parameters
        case offset
        case limit
        case options
    }
}

struct AnalysisOperationResponse: Codable, Equatable, Sendable {
    let operationID: String
    let inputPath: String
    let sheet: SheetValue
    let operationResult: AnalysisOperationResultPayload

    enum CodingKeys: String, CodingKey {
        case operationID = "operationId"
        case inputPath
        case sheet
        case operationResult
    }
}

struct ImportPreviewRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let filterID: String?
    let sheet: SheetValue
    let offset: Int
    let limit: Int
    let options: [String: JSONValue]

    init(
        inputPath: String,
        filterID: String? = nil,
        sheet: SheetValue = .index(0),
        offset: Int = 0,
        limit: Int = 50,
        options: [String: JSONValue] = [:]
    ) {
        self.inputPath = inputPath
        self.filterID = filterID
        self.sheet = sheet
        self.offset = offset
        self.limit = limit
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case inputPath
        case filterID = "filterId"
        case sheet
        case offset
        case limit
        case options
    }
}

struct ImportPreviewResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let filterID: String
    let status: String
    let label: String
    let dataContainers: [DataContainerPayload]
    let diagnostics: [[String: JSONValue]]
    let optionsSchema: [String: JSONValue]
    let help: String

    enum CodingKeys: String, CodingKey {
        case inputPath
        case filterID = "filterId"
        case status
        case label
        case dataContainers
        case diagnostics
        case optionsSchema
        case help
    }
}

struct PlotEditCommandNormalizeRequest: Codable, Equatable, Sendable {
    let command: PlotEditCommandPayload
    let objects: [PlotObjectPayload]

    init(command: PlotEditCommandPayload, objects: [PlotObjectPayload] = []) {
        self.command = command
        self.objects = objects
    }
}

struct PlotEditCommandNormalizeResponse: Codable, Equatable, Sendable {
    let command: PlotEditCommandPayload
    let diagnostics: [[String: JSONValue]]
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
    let dataContainers: [DataContainerPayload]

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
        case dataContainers
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
        delimiter: String? = nil,
        dataContainers: [DataContainerPayload] = []
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
        self.dataContainers = dataContainers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputPath = try container.decode(String.self, forKey: .inputPath)
        sheet = try container.decode(SheetValue.self, forKey: .sheet)
        offset = try container.decode(Int.self, forKey: .offset)
        limit = try container.decode(Int.self, forKey: .limit)
        totalRows = try container.decode(Int.self, forKey: .totalRows)
        totalCols = try container.decode(Int.self, forKey: .totalCols)
        columnHeaders = try container.decode([String].self, forKey: .columnHeaders)
        rows = try container.decode([[JSONValue]].self, forKey: .rows)
        candidateRoles = try container.decode(PlotCandidateRolesResponse.self, forKey: .candidateRoles)
        detectedXLabel = try container.decodeIfPresent(String.self, forKey: .detectedXLabel)
        detectedYLabel = try container.decodeIfPresent(String.self, forKey: .detectedYLabel)
        columnProfiles = try container.decodeIfPresent([PlotColumnProfileResponse].self, forKey: .columnProfiles) ?? []
        segments = try container.decodeIfPresent([SourceTableSegmentResponse].self, forKey: .segments) ?? []
        selectedSegmentID = try container.decodeIfPresent(String.self, forKey: .selectedSegmentID)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        delimiter = try container.decodeIfPresent(String.self, forKey: .delimiter)
        dataContainers = try container.decodeIfPresent([DataContainerPayload].self, forKey: .dataContainers) ?? []
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
    let operationResult: AnalysisOperationResultPayload?

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
        case operationResult
    }

    init(
        inputPath: String,
        sheet: SheetValue,
        modelID: String,
        xLabel: String?,
        yLabel: String?,
        selectedSeriesID: String?,
        equationDisplay: String,
        slope: Double?,
        intercept: Double?,
        rSquared: Double,
        rmse: Double,
        pointCount: Int,
        seriesSummaries: [FitSeriesSummaryResponse],
        warnings: [String],
        totalRows: Int,
        offset: Int,
        limit: Int,
        rows: [FitDerivedRowResponse],
        operationResult: AnalysisOperationResultPayload? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.modelID = modelID
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.selectedSeriesID = selectedSeriesID
        self.equationDisplay = equationDisplay
        self.slope = slope
        self.intercept = intercept
        self.rSquared = rSquared
        self.rmse = rmse
        self.pointCount = pointCount
        self.seriesSummaries = seriesSummaries
        self.warnings = warnings
        self.totalRows = totalRows
        self.offset = offset
        self.limit = limit
        self.rows = rows
        self.operationResult = operationResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputPath = try container.decode(String.self, forKey: .inputPath)
        sheet = try container.decode(SheetValue.self, forKey: .sheet)
        modelID = try container.decode(String.self, forKey: .modelID)
        xLabel = try container.decodeIfPresent(String.self, forKey: .xLabel)
        yLabel = try container.decodeIfPresent(String.self, forKey: .yLabel)
        selectedSeriesID = try container.decodeIfPresent(String.self, forKey: .selectedSeriesID)
        equationDisplay = try container.decode(String.self, forKey: .equationDisplay)
        slope = try container.decodeIfPresent(Double.self, forKey: .slope)
        intercept = try container.decodeIfPresent(Double.self, forKey: .intercept)
        rSquared = try container.decode(Double.self, forKey: .rSquared)
        rmse = try container.decode(Double.self, forKey: .rmse)
        pointCount = try container.decode(Int.self, forKey: .pointCount)
        seriesSummaries = try container.decodeIfPresent([FitSeriesSummaryResponse].self, forKey: .seriesSummaries) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        totalRows = try container.decode(Int.self, forKey: .totalRows)
        offset = try container.decode(Int.self, forKey: .offset)
        limit = try container.decode(Int.self, forKey: .limit)
        rows = try container.decodeIfPresent([FitDerivedRowResponse].self, forKey: .rows) ?? []
        operationResult = try container.decodeIfPresent(AnalysisOperationResultPayload.self, forKey: .operationResult)
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

    private enum CodingKeys: String, CodingKey {
        case contextID = "contextId"
        case inputPath
        case sheet
        case sheetNames
        case inspection
        case dataset
        case template
        case options
        case promptText
        case starterCode
        case sourceKind
        case sourceLabel
    }
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

    private enum CodingKeys: String, CodingKey {
        case contextID = "contextId"
        case context
        case code
        case timeoutSeconds
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
    let notebookOutputs: [NotebookOutputPayload]
    let dataContainers: [DataContainerPayload]

    init(
        status: String,
        exitCode: Int?,
        durationSeconds: Double,
        stdout: String,
        stderr: String,
        runDir: String,
        outputDir: String,
        scriptPath: String,
        promptPath: String,
        contextPath: String,
        stdoutPath: String,
        stderrPath: String,
        generatedFiles: [CodeConsoleGeneratedFileResponse],
        notebookOutputs: [NotebookOutputPayload] = [],
        dataContainers: [DataContainerPayload] = []
    ) {
        self.status = status
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.stdout = stdout
        self.stderr = stderr
        self.runDir = runDir
        self.outputDir = outputDir
        self.scriptPath = scriptPath
        self.promptPath = promptPath
        self.contextPath = contextPath
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.generatedFiles = generatedFiles
        self.notebookOutputs = notebookOutputs
        self.dataContainers = dataContainers
    }

    enum CodingKeys: String, CodingKey {
        case status
        case exitCode
        case durationSeconds
        case stdout
        case stderr
        case runDir
        case outputDir
        case scriptPath
        case promptPath
        case contextPath
        case stdoutPath
        case stderrPath
        case generatedFiles
        case notebookOutputs
        case dataContainers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        stdout = try container.decodeIfPresent(String.self, forKey: .stdout) ?? ""
        stderr = try container.decodeIfPresent(String.self, forKey: .stderr) ?? ""
        runDir = try container.decode(String.self, forKey: .runDir)
        outputDir = try container.decode(String.self, forKey: .outputDir)
        scriptPath = try container.decode(String.self, forKey: .scriptPath)
        promptPath = try container.decode(String.self, forKey: .promptPath)
        contextPath = try container.decode(String.self, forKey: .contextPath)
        stdoutPath = try container.decode(String.self, forKey: .stdoutPath)
        stderrPath = try container.decode(String.self, forKey: .stderrPath)
        generatedFiles = try container.decodeIfPresent([CodeConsoleGeneratedFileResponse].self, forKey: .generatedFiles) ?? []
        notebookOutputs = try container.decodeIfPresent([NotebookOutputPayload].self, forKey: .notebookOutputs) ?? []
        dataContainers = try container.decodeIfPresent([DataContainerPayload].self, forKey: .dataContainers) ?? []
    }
}

struct PreviewRenderConfigPayload: Codable, Equatable, Hashable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
}

struct RenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let fitOptions: FitOptionsPayload
    let previewConfig: PreviewRenderConfigPayload?

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String,
        options: RenderOptionsPayload,
        fitOptions: FitOptionsPayload = FitOptionsPayload(),
        previewConfig: PreviewRenderConfigPayload? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.fitOptions = fitOptions
        self.previewConfig = previewConfig
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
        case sessionKind = "sessionKind"
        case sourceFilename = "sourceFilename"
        case sourceMediaType = "sourceMediaType"
        case embeddedSourceRelpath = "embeddedSourceRelpath"
        case sourceSHA256 = "sourceSha256"
        case sheet = "sheet"
        case selectedTemplateID = "selectedTemplateId"
        case renderOptions = "renderOptions"
        case fitOptions = "fitOptions"
        case projectDisplayName = "projectDisplayName"
        case sourceProvenance = "sourceProvenance"
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
        case workbookFilename = "workbookFilename"
        case embeddedWorkbookRelpath = "embeddedWorkbookRelpath"
        case workbookSHA256 = "workbookSha256"
        case originalWorkbookPath = "originalWorkbookPath"
        case savedWorkbookMtimeNs = "savedWorkbookMtimeNs"
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
        case sessionKind = "sessionKind"
        case version = "version"
        case selectedTemplateID = "selectedTemplateId"
        case workbookPaths = "workbookPaths"
        case selectedWorkbookID = "selectedWorkbookId"
        case primaryWorkbookID = "primaryWorkbookId"
        case selectedRecipeID = "selectedRecipeId"
        case comparisonRecipeIDs = "comparisonRecipeIds"
        case selectedFigureFamilyID = "selectedFigureFamilyId"
        case selectedFigureTemplateID = "selectedFigureTemplateId"
        case groupStates = "groupStates"
        case specimenStates = "specimenStates"
        case figurePreferences = "figurePreferences"
        case importedPaths = "importedPaths"
        case templateDraftPath = "templateDraftPath"
        case embeddedWorkbooks = "embeddedWorkbooks"
        case projectDisplayName = "projectDisplayName"
        case sourceProvenance = "sourceProvenance"
    }
}

struct ComposerProjectPanelPayload: Codable, Equatable, Sendable {
    let panelID: String
    let panelFilename: String
    let embeddedPanelRelpath: String
    let panelSHA256: String
    let originalPanelPath: String?
    let savedPanelMtimeNs: Int?

    enum CodingKeys: String, CodingKey {
        case panelID = "panelId"
        case panelFilename
        case embeddedPanelRelpath
        case panelSHA256 = "panelSha256"
        case originalPanelPath
        case savedPanelMtimeNs
    }
}

struct ComposerProjectPayload: Codable, Equatable, Sendable {
    var sessionKind: String = "composer"
    var version: Int = 2
    var project: ComposerRequestPayload = .init()
    var embeddedPanels: [ComposerProjectPanelPayload] = []
    var projectDisplayName: String?
}

struct CodeConsoleProjectManualBindingPayload: Codable, Equatable, Sendable {
    let sourceFilename: String
    let embeddedSourceRelpath: String
    let sourceSHA256: String
    let originalSourcePath: String?
    let savedSourceMtimeNs: Int?
    let sheet: SheetValue
    let templateID: String?
    let renderOptions: RenderOptionsPayload
    let title: String

    enum CodingKeys: String, CodingKey {
        case sourceFilename
        case embeddedSourceRelpath
        case sourceSHA256 = "sourceSha256"
        case originalSourcePath
        case savedSourceMtimeNs
        case sheet
        case templateID = "templateId"
        case renderOptions
        case title
    }
}

struct CodeConsoleProjectGeneratedFilePayload: Codable, Equatable, Sendable {
    let originalPath: String?
    let embeddedFileRelpath: String
    let fileSHA256: String
    let name: String
    let fileType: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case originalPath
        case embeddedFileRelpath
        case fileSHA256 = "fileSha256"
        case name
        case fileType
        case sizeBytes
    }
}

struct CodeConsoleGeneratedFileSnapshotPayload: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let fileType: String
    let sizeBytes: Int
}

struct CodeConsoleRunSnapshotPayload: Codable, Equatable, Sendable {
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
    let generatedFiles: [CodeConsoleGeneratedFileSnapshotPayload]
}

struct CodeConsoleProjectPayload: Codable, Equatable, Sendable {
    var sessionKind: String = "code_console"
    var version: Int = 2
    var selectedSourceKind: String?
    var selectedSheet: SheetValue = .index(0)
    var editorText: String = ""
    var promptText: String = ""
    var starterCode: String = ""
    var manualBinding: CodeConsoleProjectManualBindingPayload?
    var latestRun: CodeConsoleRunSnapshotPayload?
    var embeddedGeneratedFiles: [CodeConsoleProjectGeneratedFilePayload] = []
    var selectedGeneratedFilePath: String?
    var projectDisplayName: String?
}

struct DocumentGraphNodePayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let module: String
    let label: String
    let status: String
    let payload: [String: JSONValue]
}

struct DocumentGraphEdgePayload: Codable, Equatable, Sendable {
    let source: String
    let target: String
    let relationship: String
}

struct DocumentGraphPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let nodes: [DocumentGraphNodePayload]
    let edges: [DocumentGraphEdgePayload]
    let selectedNodes: [String: String]
    let moduleRoots: [String: String]
    let capabilities: [String]
    let migrationNotes: [String]
}

struct ProjectBundlePayload: Codable, Equatable, Sendable {
    let version: Int
    let selectedWorkbench: String
    let plot: PlotProjectPayload?
    let dataStudio: DataStudioProjectPayload?
    let composer: ComposerProjectPayload?
    let codeConsole: CodeConsoleProjectPayload?
    let documentGraph: DocumentGraphPayload?
    let artifacts: [String: JSONValue]

    init(
        version: Int,
        selectedWorkbench: String,
        plot: PlotProjectPayload?,
        dataStudio: DataStudioProjectPayload?,
        composer: ComposerProjectPayload?,
        codeConsole: CodeConsoleProjectPayload?,
        documentGraph: DocumentGraphPayload? = nil,
        artifacts: [String: JSONValue]
    ) {
        self.version = version
        self.selectedWorkbench = selectedWorkbench
        self.plot = plot
        self.dataStudio = dataStudio
        self.composer = composer
        self.codeConsole = codeConsole
        self.documentGraph = documentGraph
        self.artifacts = artifacts
    }
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
    let displayGroup: String
    let description: String
    let hardConstraints: Bool
    let presetNote: String
    let recommendedPalettePreset: String
    let recommendedVisualThemeID: String?

    init(
        id: String,
        label: String,
        `public`: Bool,
        displayGroup: String = "publication",
        description: String,
        hardConstraints: Bool,
        presetNote: String,
        recommendedPalettePreset: String,
        recommendedVisualThemeID: String?
    ) {
        self.id = id
        self.label = label
        self.public = `public`
        self.displayGroup = displayGroup
        self.description = description
        self.hardConstraints = hardConstraints
        self.presetNote = presetNote
        self.recommendedPalettePreset = recommendedPalettePreset
        self.recommendedVisualThemeID = recommendedVisualThemeID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case `public`
        case displayGroup
        case description
        case hardConstraints
        case presetNote
        case recommendedPalettePreset
        case recommendedVisualThemeID = "recommendedVisualThemeId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        self.public = try container.decode(Bool.self, forKey: .public)
        displayGroup = try container.decodeIfPresent(String.self, forKey: .displayGroup) ?? "publication"
        description = try container.decode(String.self, forKey: .description)
        hardConstraints = try container.decode(Bool.self, forKey: .hardConstraints)
        presetNote = try container.decode(String.self, forKey: .presetNote)
        recommendedPalettePreset = try container.decode(String.self, forKey: .recommendedPalettePreset)
        recommendedVisualThemeID = try container.decodeIfPresent(String.self, forKey: .recommendedVisualThemeID)
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

struct CapabilityCatalogEntryResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let status: String
    let owner: String
    let surface: String
    let typedPayloadSchema: [String: JSONValue]
    let help: String
    let introducedIn: String
    let testRequirements: [String]
}

struct CapabilityCatalogGroupResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
    let capabilities: [CapabilityCatalogEntryResponse]
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
    let capabilityCatalogs: [CapabilityCatalogGroupResponse]

    init(
        version: Int,
        defaults: MetaDefaultsResponse,
        sizes: [MetaSizeResponse],
        styles: [MetaStyleResponse],
        palettes: [MetaPaletteResponse],
        templates: [MetaTemplateSummary],
        templateIds: [String],
        sizeIds: [String],
        palettePresetIds: [String],
        visualThemes: [VisualThemeResponse],
        capabilityCatalogs: [CapabilityCatalogGroupResponse] = []
    ) {
        self.version = version
        self.defaults = defaults
        self.sizes = sizes
        self.styles = styles
        self.palettes = palettes
        self.templates = templates
        self.templateIds = templateIds
        self.sizeIds = sizeIds
        self.palettePresetIds = palettePresetIds
        self.visualThemes = visualThemes
        self.capabilityCatalogs = capabilityCatalogs
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case defaults
        case sizes
        case styles
        case palettes
        case templates
        case templateIds
        case sizeIds
        case palettePresetIds
        case visualThemes
        case capabilityCatalogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        defaults = try container.decode(MetaDefaultsResponse.self, forKey: .defaults)
        sizes = try container.decodeIfPresent([MetaSizeResponse].self, forKey: .sizes) ?? []
        styles = try container.decodeIfPresent([MetaStyleResponse].self, forKey: .styles) ?? []
        palettes = try container.decodeIfPresent([MetaPaletteResponse].self, forKey: .palettes) ?? []
        templates = try container.decodeIfPresent([MetaTemplateSummary].self, forKey: .templates) ?? []
        templateIds = try container.decodeIfPresent([String].self, forKey: .templateIds) ?? []
        sizeIds = try container.decodeIfPresent([String].self, forKey: .sizeIds) ?? []
        palettePresetIds = try container.decodeIfPresent([String].self, forKey: .palettePresetIds) ?? []
        visualThemes = try container.decodeIfPresent([VisualThemeResponse].self, forKey: .visualThemes) ?? []
        capabilityCatalogs = try container.decodeIfPresent(
            [CapabilityCatalogGroupResponse].self,
            forKey: .capabilityCatalogs
        ) ?? []
    }
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
