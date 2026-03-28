import Foundation
@testable import SciPlotGodMac

enum TestPayloads {
    static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9oNnfdcAAAAASUVORK5CYII="

    static func meta() -> SidecarMetaResponse {
        SidecarMetaResponse(
            version: 1,
            defaults: .init(stylePreset: "journal_calm", palettePreset: "aqua_graphite"),
            sizes: [
                .init(id: "single_panel", label: "Single Panel", widthMm: 60, heightMm: 55),
                .init(id: "double_panel", label: "Double Panel", widthMm: 120, heightMm: 55),
            ],
            styles: [
                .init(
                    id: "journal_calm",
                    label: "Journal Calm",
                    public: true,
                    description: "Default publication style.",
                    hardConstraints: true,
                    presetNote: "Repo default"
                ),
            ],
            palettes: [
                .init(
                    id: "aqua_graphite",
                    label: "Aqua Graphite",
                    public: true,
                    description: "Default palette.",
                    swatches: ["#112233", "#445566"]
                ),
            ],
            templates: [
                .init(
                    id: "curve",
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel", "double_panel"],
                    editableOptions: ["size", "xscale", "yscale", "style_preset", "palette_preset"],
                    defaultOptions: [:],
                    availableStyles: ["journal_calm"],
                    availablePalettes: ["aqua_graphite"],
                    canonicalID: "curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "curve"
                ),
                .init(
                    id: "bar",
                    label: "Bar",
                    description: "Bar comparison template.",
                    category: "stats",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: ["size", "style_preset", "palette_preset"],
                    defaultOptions: [:],
                    availableStyles: ["journal_calm"],
                    availablePalettes: ["aqua_graphite"],
                    canonicalID: "bar",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "bar"
                ),
            ],
            templateIDs: ["curve", "bar"],
            sizeIDs: ["single_panel", "double_panel"],
            palettePresetIDs: ["aqua_graphite"],
            visualThemes: [
                .init(id: "paper", label: "Paper", description: "Paper preview"),
            ]
        )
    }

    static func contract() -> PlotContractResponse {
        PlotContractResponse(
            version: 1,
            defaults: .init(stylePreset: "journal_calm", palettePreset: "aqua_graphite"),
            sizePresets: [
                "single_panel": .init(id: "single_panel", label: "Single Panel", widthMm: 60, heightMm: 55),
            ],
            styles: [
                "journal_calm": .string("Journal Calm"),
            ],
            palettes: [
                "aqua_graphite": .string("Aqua Graphite"),
            ],
            templates: [
                "curve": .init(
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: ["size", "style_preset", "palette_preset"],
                    defaultOptions: [:],
                    availableStyles: ["journal_calm"],
                    availablePalettes: ["aqua_graphite"],
                    hardRules: ["Use the shared axis frame."],
                    softRules: ["Keep labels minimal."]
                ),
            ]
        )
    }

    static func inspectFile(path: String = "/tmp/sample.csv") -> InspectFileResponse {
        InspectFileResponse(
            inputPath: path,
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: .init(
                model: "tensile_curve",
                modelLabel: "Tensile Curve",
                recommendation: .init(
                    template: "curve",
                    reason: "Compatible with the tensile curve data model.",
                    size: "single_panel",
                    xscale: "linear",
                    yscale: "linear",
                    reverseX: false,
                    baseline: nil,
                    showColorbar: nil,
                    stylePreset: "journal_calm",
                    palettePreset: "aqua_graphite",
                    useSidecar: true
                ),
                recommendations: [
                    .init(
                        templateID: "curve",
                        canonicalID: "curve",
                        role: "plot",
                        lifecyclePolicy: "stable",
                        implementationID: "curve",
                        score: 0.98,
                        rank: 1,
                        reason: "Best fit for this tensile curve.",
                        suitabilityHint: "Recommended",
                        scoreGapToTop: 0,
                        whyHardMatch: ["Detected tensile curve columns."],
                        whySoftPrior: ["Shared axis frame."],
                        inferredMapping: ["x": "Strain", "y": "Stress"],
                        optionalEnhancements: [],
                        previewConfigSummary: [:]
                    ),
                ],
                primaryRecommendation: [
                    .init(
                        templateID: "curve",
                        canonicalID: "curve",
                        role: "plot",
                        lifecyclePolicy: "stable",
                        implementationID: "curve",
                        score: 0.98,
                        rank: 1,
                        reason: "Best fit for this tensile curve.",
                        suitabilityHint: "Recommended",
                        scoreGapToTop: 0,
                        whyHardMatch: ["Detected tensile curve columns."],
                        whySoftPrior: ["Shared axis frame."],
                        inferredMapping: ["x": "Strain", "y": "Stress"],
                        optionalEnhancements: [],
                        previewConfigSummary: [:]
                    ),
                ],
                alternativeRecommendations: [],
                advancedTemplates: [],
                recommendationConfidence: 0.93,
                recommendationSummary: "Curve is the recommended plot template.",
                warnings: [],
                signals: ["tensile_curve"]
            ),
            dataset: .init(
                datasetID: "dataset-1",
                sourcePath: path,
                sheet: .name("Representative_Curve"),
                model: "tensile_curve",
                rawRows: 3,
                rawCols: 2,
                columnProfiles: [
                    .init(
                        name: "Strain",
                        headerPreview: ["Strain"],
                        inferredType: "numeric",
                        nonEmptyCount: 3,
                        missingCount: 0,
                        minValue: 0,
                        maxValue: 0.2
                    ),
                    .init(
                        name: "Stress",
                        headerPreview: ["Stress"],
                        inferredType: "numeric",
                        nonEmptyCount: 3,
                        missingCount: 0,
                        minValue: 0,
                        maxValue: 12
                    ),
                ],
                candidateRoles: .init(
                    x: ["Strain"],
                    y: ["Stress"],
                    z: [],
                    group: [],
                    sample: [],
                    value: [],
                    metric: [],
                    label: [],
                    series: []
                ),
                dataShapes: ["curve_table"],
                semanticSignals: ["tensile_curve"],
                qualityFlags: [],
                sampleRows: [
                    [.number(0.0), .number(0.0)],
                    [.number(0.1), .number(6.2)],
                    [.number(0.2), .number(12.0)],
                ]
            )
        )
    }

    static func preflight() -> PreflightRenderResponse {
        PreflightRenderResponse(
            inputPath: "/tmp/sample.csv",
            template: "curve",
            requestedTemplateID: "curve",
            canonicalID: "curve",
            role: "plot",
            lifecyclePolicy: "stable",
            implementationID: "curve",
            sheet: .name("Representative_Curve"),
            options: RenderOptionsPayload(size: "single_panel", xscale: "linear", yscale: "linear"),
            preflight: .init(
                template: "curve",
                requestedTemplateID: "curve",
                canonicalID: "curve",
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: "curve",
                warnings: ["Label density is within range."],
                errors: [],
                outputFilenames: ["sample_curve.pdf"],
                submissionReport: submissionReport()
            )
        )
    }

    static func renderPreview() -> RenderPreviewResponse {
        RenderPreviewResponse(
            template: "curve",
            requestedTemplateID: "curve",
            canonicalID: "curve",
            role: "plot",
            lifecyclePolicy: "stable",
            implementationID: "curve",
            sheet: .name("Representative_Curve"),
            previews: [
                .init(filename: "sample_curve.png", pngBase64: pngBase64, qa: nil),
            ],
            submissionReport: submissionReport()
        )
    }

    static func exportRender() -> ExportRenderResponse {
        ExportRenderResponse(
            requestedTemplateID: "curve",
            canonicalID: "curve",
            role: "plot",
            lifecyclePolicy: "stable",
            implementationID: "curve",
            outputs: ["/tmp/plot_exports/sample_curve.pdf"],
            outputDir: "/tmp/plot_exports",
            previewOutputs: ["/tmp/plot_exports/sample_curve.png"],
            artifactPaths: ["/tmp/plot_exports/manifest.json"],
            manifestPath: "/tmp/plot_exports/manifest.json",
            submissionReport: submissionReport()
        )
    }

    static func tensilePreprocess() -> TensileReplicateResponseModel {
        TensileReplicateResponseModel(
            outputPath: "/tmp/prepared.xlsx",
            groupName: "Primary Group",
            preferredSheet: "Representative_Curve",
            sheetNames: ["Representative_Curve", "Strength_Box"],
            sampleCount: 3,
            representativeFilename: "sample_a.csv",
            metrics: [
                .init(label: "Strength", unit: "MPa", mean: 12.4, std: 0.4),
            ],
            warnings: []
        )
    }

    static func tensileWorkbookSummary(path: String, label: String) -> TensileWorkbookSummaryResponse {
        TensileWorkbookSummaryResponse(
            workbookPath: path,
            label: label,
            sheetNames: ["Representative_Curve", "Strength_Box"],
            sampleCount: 4,
            representativeFilename: "sample_b.csv",
            metrics: [
                .init(label: "Modulus", unit: "MPa", mean: 2.1, std: 0.1),
            ]
        )
    }

    static func tensileComparison() -> TensileComparisonExportResponse {
        TensileComparisonExportResponse(
            bundleDir: "/tmp/cleanup_bundle",
            comparisonWorkbookPath: "/tmp/cleanup_bundle/comparison.xlsx",
            labels: ["Primary Group", "Second Group"],
            outputs: ["/tmp/cleanup_bundle/strength_box.pdf", "/tmp/cleanup_bundle/modulus_bar.pdf"]
        )
    }

    static func composerProject() -> ComposerProjectResponse {
        ComposerProjectResponse(
            version: 2,
            mode: "composer",
            canvasWidthMm: 180,
            canvasHeightMm: 170,
            gridMm: 0.5,
            layoutGrid: .init(),
            regions: [
                .init(id: "region-1", kind: "graph", col: 0, row: 0, colSpan: 1, rowSpan: 1, label: "A", locked: false, slotKind: nil),
            ],
            panels: [
                .init(
                    id: "panel-1",
                    filePath: "/tmp/panel.pdf",
                    pageIndex: 0,
                    xMm: 10,
                    yMm: 10,
                    wMm: 60,
                    hMm: 55,
                    locked: false,
                    hidden: false,
                    label: "A",
                    kind: "graph",
                    zIndex: 1,
                    groupID: nil,
                    regionID: "region-1",
                    slotID: nil,
                    cropRect: .init()
                ),
            ],
            texts: [
                .init(id: "text-1", text: "Figure 1", xMm: 5, yMm: 5),
            ],
            autoLabels: true
        )
    }

    static func composerPreview() -> ComposerPreviewResponse {
        ComposerPreviewResponse(
            valid: true,
            validationError: nil,
            pngBase64: pngBase64,
            qa: nil,
            submissionReport: submissionReport(),
            suggestedProjectPatch: []
        )
    }

    static func submissionReport() -> SubmissionReportResponse {
        SubmissionReportResponse(
            context: "plot",
            readiness: "ready",
            summary: "Ready for export.",
            template: "curve",
            stylePreset: "journal_calm",
            palettePreset: "aqua_graphite",
            outputCount: 1,
            outputFilenames: ["sample_curve.pdf"],
            blockers: [],
            checks: [
                .init(
                    id: "bounds",
                    status: "pass",
                    message: "Axis bounds follow contract.",
                    metricValue: nil,
                    target: nil,
                    source: "preflight"
                ),
            ]
        )
    }
}
