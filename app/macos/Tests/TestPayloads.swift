import Foundation
@testable import SciPlotGodMac

enum TestPayloads {
    static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9oNnfdcAAAAASUVORK5CYII="
    static let pdfBase64 = "JVBERi0xLjEKMSAwIG9iajw8Pj5lbmRvYmoKMiAwIG9iajw8IC9UeXBlIC9DYXRhbG9nIC9QYWdlcyAzIDAgUiA+PmVuZG9iagozIDAgb2JqPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFs0IDAgUl0gL0NvdW50IDEgPj5lbmRvYmoKNCAwIG9iajw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMyAwIFIgL01lZGlhQm94IFswIDAgNzIgNzJdID4+ZW5kb2JqCnhyZWYKMCA1CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxMCAwMDAwMCBuIAowMDAwMDAwMDMwIDAwMDAwIG4gCjAwMDAwMDAwODEgMDAwMDAgbiAKMDAwMDAwMDEzOCAwMDAwMCBuIAp0cmFpbGVyPDwgL1NpemUgNSAvUm9vdCAyIDAgUiA+PgpzdGFydHhyZWYKMjA5CiUlRU9GCg=="

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
            templateIds: ["curve", "bar"],
            sizeIds: ["single_panel", "double_panel"],
            palettePresetIds: ["aqua_graphite"],
            visualThemes: [
                .init(id: "paper", label: "Paper", description: "Paper preview"),
            ]
        )
    }

    static func multiSeriesMeta() -> SidecarMetaResponse {
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
                    editableOptions: ["size", "xscale", "yscale", "series_order", "style_preset", "palette_preset"],
                    defaultOptions: [:],
                    availableStyles: ["journal_calm"],
                    availablePalettes: ["aqua_graphite"],
                    canonicalID: "curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "curve"
                ),
            ],
            templateIds: ["curve"],
            sizeIds: ["single_panel", "double_panel"],
            palettePresetIds: ["aqua_graphite"],
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
                "single_panel": .init(label: "Single Panel", widthMm: 60, heightMm: 55),
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

    static func codeConsoleContext(path: String = "/tmp/sample.csv") -> CodeConsoleContextResponse {
        CodeConsoleContextResponse(
            inputPath: path,
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: inspectFile(path: path).inspection,
            dataset: inspectFile(path: path).dataset,
            template: "curve",
            options: .init(
                size: "single_panel",
                stylePreset: "journal_calm",
                palettePreset: "aqua_graphite",
                visualThemeID: "paper"
            ),
            promptText: """
            Write one Python script for the SciPlot God Code Console.
            Use: from src.code_console_runtime import console
            """,
            starterCode: """
            from src.code_console_runtime import console

            fig, ax = console.new_figure()
            console.save_figure(fig, "sample")
            """,
            sourceKind: "plot",
            sourceLabel: "Current Plot session"
        )
    }

    static func codeConsoleRun() -> CodeConsoleRunResponse {
        CodeConsoleRunResponse(
            status: "succeeded",
            exitCode: 0,
            durationSeconds: 0.42,
            stdout: "Generated outputs",
            stderr: "",
            runDir: "/tmp/code_console/run-1",
            outputDir: "/tmp/code_console/run-1/outputs",
            scriptPath: "/tmp/code_console/run-1/user_code.py",
            promptPath: "/tmp/code_console/run-1/external_ai_prompt.txt",
            contextPath: "/tmp/code_console/run-1/context.json",
            stdoutPath: "/tmp/code_console/run-1/stdout.txt",
            stderrPath: "/tmp/code_console/run-1/stderr.txt",
            generatedFiles: [
                .init(
                    path: "/tmp/code_console/run-1/outputs/sample.pdf",
                    name: "sample.pdf",
                    fileType: "pdf",
                    sizeBytes: 1024
                ),
                .init(
                    path: "/tmp/code_console/run-1/outputs/fit_table.csv",
                    name: "fit_table.csv",
                    fileType: "csv",
                    sizeBytes: 256
                ),
            ]
        )
    }

    static func multiSeriesInspectFile(path: String = "/tmp/sample.csv") -> InspectFileResponse {
        InspectFileResponse(
            inputPath: path,
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: .init(
                model: "frequency_sweep",
                modelLabel: "Frequency Sweep",
                recommendation: .init(
                    template: "curve",
                    reason: "Compatible with the multi-series curve data model.",
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
                        reason: "Best fit for this multi-series curve.",
                        suitabilityHint: "Recommended",
                        scoreGapToTop: 0,
                        whyHardMatch: ["Detected curve series labels."],
                        whySoftPrior: ["Shared axis frame."],
                        inferredMapping: ["x": "Frequency", "y": "Modulus"],
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
                        reason: "Best fit for this multi-series curve.",
                        suitabilityHint: "Recommended",
                        scoreGapToTop: 0,
                        whyHardMatch: ["Detected curve series labels."],
                        whySoftPrior: ["Shared axis frame."],
                        inferredMapping: ["x": "Frequency", "y": "Modulus"],
                        optionalEnhancements: [],
                        previewConfigSummary: [:]
                    ),
                ],
                alternativeRecommendations: [],
                advancedTemplates: [],
                recommendationConfidence: 0.95,
                recommendationSummary: "Curve is the recommended plot template.",
                warnings: [],
                signals: ["frequency_sweep"]
            ),
            dataset: .init(
                datasetID: "dataset-2",
                sourcePath: path,
                sheet: .name("Representative_Curve"),
                model: "frequency_sweep",
                rawRows: 4,
                rawCols: 2,
                columnProfiles: [
                    .init(
                        name: "Frequency",
                        headerPreview: ["Frequency"],
                        inferredType: "numeric",
                        nonEmptyCount: 4,
                        missingCount: 0,
                        minValue: 0.1,
                        maxValue: 100.0
                    ),
                    .init(
                        name: "Modulus",
                        headerPreview: ["Modulus"],
                        inferredType: "numeric",
                        nonEmptyCount: 4,
                        missingCount: 0,
                        minValue: 1.0,
                        maxValue: 30.0
                    ),
                ],
                candidateRoles: .init(
                    x: ["Frequency"],
                    y: ["Modulus"],
                    z: [],
                    group: [],
                    sample: [],
                    value: [],
                    metric: [],
                    label: [],
                    series: ["Series A", "Series B"]
                ),
                dataShapes: ["curve_table"],
                semanticSignals: ["frequency_sweep"],
                qualityFlags: [],
                sampleRows: [
                    [.number(0.1), .number(1.0)],
                    [.number(1.0), .number(5.5)],
                    [.number(10.0), .number(17.0)],
                    [.number(100.0), .number(28.0)],
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
                .init(filename: "sample_curve.pdf", pdfBase64: pdfBase64, qa: nil),
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

    static func dataStudioTemplate(
        id: String = "builtin/tensile",
        label: String = "Tensile"
    ) -> DataStudioTemplateResponse {
        DataStudioTemplateResponse(
            version: 1,
            id: id,
            label: label,
            family: "tensile",
            builtin: id == "builtin/tensile",
            description: "Built-in tensile import template.",
            fileTypes: ["csv", "txt", "tsv", "xls", "xlsx", "xlsm"],
            parseStrategy: "builtin:tensile",
            matchConditions: [
                .init(
                    sheetNameContains: ["Representative"],
                    textContains: ["strain", "stress"],
                    fieldKinds: ["curve_x", "curve_y", "metric"],
                    minimumScore: 0.8
                ),
            ],
            fieldBindings: [
                .init(
                    id: "strain",
                    role: "curve_x",
                    label: "Strain",
                    sheetName: nil,
                    blockID: nil,
                    columnName: "Strain",
                    columnIndex: 0,
                    rowLabelContains: nil,
                    cellValueContains: [],
                    unitHint: "%",
                    optional: false
                ),
                .init(
                    id: "stress",
                    role: "curve_y",
                    label: "Stress",
                    sheetName: nil,
                    blockID: nil,
                    columnName: "Stress",
                    columnIndex: 1,
                    rowLabelContains: nil,
                    cellValueContains: [],
                    unitHint: "MPa",
                    optional: false
                ),
            ],
            workbookMetricIDs: ["Strength", "Modulus", "Elongation"],
            defaultGroupNameStrategy: "common_prefix",
            preferredSheetName: "Representative_Curve",
            metadata: ["builtin_family": .string("tensile")]
        )
    }

    static func dataStudioTemplateList() -> DataStudioTemplateListResponse {
        DataStudioTemplateListResponse(
            templates: [
                dataStudioTemplate(),
                dataStudioTemplate(id: "user/custom_curve", label: "Custom Curve Template"),
            ]
        )
    }

    static func dataStudioSourcePreview(path: String = "/tmp/raw_a.csv") -> DataStudioSourcePreviewResponse {
        DataStudioSourcePreviewResponse(
            preview: .init(
                sourcePath: path,
                fileType: "csv",
                encoding: "utf-8",
                delimiter: ",",
                sheetNames: ["Sheet1"],
                sheets: [
                    .init(
                        sheetName: "Sheet1",
                        rowCount: 8,
                        colCount: 4,
                        sampleRows: [
                            [.string("Strain"), .string("Stress"), .string("Strength"), .string("Modulus")],
                            [.string("%"), .string("MPa"), .string("MPa"), .string("MPa")],
                        ],
                        blocks: [
                            .init(
                                id: "sheet1:block0",
                                sheetName: "Sheet1",
                                label: "Primary Data Block",
                                rowCount: 6,
                                colCount: 4,
                                range: .init(sheetName: "Sheet1", startRow: 1, endRow: 6, startCol: 1, endCol: 4),
                                headerRowIndex: 0,
                                unitRowIndex: 1,
                                dataStartRowIndex: 2,
                                sampleRows: [
                                    [.string("Strain"), .string("Stress"), .string("Strength"), .string("Modulus")],
                                    [.string("%"), .string("MPa"), .string("MPa"), .string("MPa")],
                                    [.number(0), .number(0), .number(12.4), .number(2.1)],
                                ]
                            ),
                        ]
                    ),
                ],
                fieldCandidates: [
                    .init(
                        id: "candidate:strain",
                        kind: "curve_x",
                        label: "Strain",
                        confidence: 0.98,
                        rationale: "Detected percentage strain values with tensile-style headers.",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        range: .init(sheetName: "Sheet1", startRow: 1, endRow: 6, startCol: 1, endCol: 1),
                        sampleValues: ["0", "0.1", "0.2"],
                        unitHint: "%"
                    ),
                    .init(
                        id: "candidate:stress",
                        kind: "curve_y",
                        label: "Stress",
                        confidence: 0.97,
                        rationale: "Detected stress column adjacent to strain with MPa units.",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        range: .init(sheetName: "Sheet1", startRow: 1, endRow: 6, startCol: 2, endCol: 2),
                        sampleValues: ["0", "5.1", "12.4"],
                        unitHint: "MPa"
                    ),
                    .init(
                        id: "candidate:strength",
                        kind: "metric",
                        label: "Strength",
                        confidence: 0.92,
                        rationale: "Summary metric column detected in the same block.",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        range: .init(sheetName: "Sheet1", startRow: 1, endRow: 6, startCol: 3, endCol: 3),
                        sampleValues: ["12.4", "12.7"],
                        unitHint: "MPa"
                    ),
                ],
                recommendedTemplateIDs: ["builtin/tensile"],
                warnings: []
            ),
            matches: [
                .init(
                    templateID: "builtin/tensile",
                    label: "Tensile",
                    family: "tensile",
                    confidence: 0.99,
                    reasons: ["Tensile headers and metrics matched the built-in template family."],
                    warnings: [],
                    matchedSheetNames: ["Sheet1"],
                    autoSelected: true
                ),
            ]
        )
    }

    static func dataStudioWorkbook(
        id: String = "workbook-1",
        path: String = "/tmp/prepared.xlsx",
        label: String = "Primary Group"
    ) -> DataStudioWorkbookResponse {
        DataStudioWorkbookResponse(
            workbookID: id,
            workbookPath: path,
            label: label,
            templateMatch: .init(
                templateID: "builtin/tensile",
                label: "Tensile",
                family: "tensile",
                confidence: 0.98,
                reasons: ["Built with the selected Data Studio template."],
                warnings: [],
                matchedSheetNames: ["Representative_Curve"],
                autoSelected: true
            ),
            sourceFiles: ["/tmp/raw_a.csv", "/tmp/raw_b.csv"],
            sheetNames: ["Representative_Curve", "Strength_Replicates", "Modulus_Replicates", "Elongation_Replicates"],
            preferredSheet: "Representative_Curve",
            parsedSampleCount: 2,
            failedSampleCount: 0,
            representativeFilename: "raw_a.csv",
            metrics: [
                .init(id: "strength", label: "Strength", unit: "MPa", mean: 12.4, std: 0.4),
                .init(id: "modulus", label: "Modulus", unit: "MPa", mean: 2.1, std: 0.1),
            ],
            warnings: [],
            exclusions: [],
            samples: [
                .init(
                    id: "sample-a",
                    sourcePath: "/tmp/raw_a.csv",
                    filename: "raw_a.csv",
                    parsed: true,
                    warnings: [],
                    exclusions: [],
                    metrics: ["Strength": 12.4, "Modulus": 2.0]
                ),
                .init(
                    id: "sample-b",
                    sourcePath: "/tmp/raw_b.csv",
                    filename: "raw_b.csv",
                    parsed: true,
                    warnings: [],
                    exclusions: [],
                    metrics: ["Strength": 12.8, "Modulus": 2.2]
                ),
            ]
        )
    }

    static func dataStudioComparisonSet() -> DataStudioComparisonSetResponse {
        DataStudioComparisonSetResponse(
            id: "primary-vs-second",
            label: "Primary Group vs Second Group",
            workbookPaths: ["/tmp/prepared.xlsx", "/tmp/second.xlsx"],
            workbookLabels: ["Primary Group", "Second Group"],
            comparisonWorkbookPath: "/tmp/data_studio_exports/primary-vs-second/primary-vs-second.xlsx",
            recipes: [
                .init(
                    id: "representative_curve",
                    label: "Representative Curve Compare",
                    category: "curve",
                    templateID: "curve",
                    sheetName: "Representative_Curve",
                    metricID: nil,
                    enabledByDefault: true,
                    supported: true,
                    supportReason: ""
                ),
                .init(
                    id: "strength_box",
                    label: "Strength Box Compare",
                    category: "metric",
                    templateID: "box",
                    sheetName: "Strength_Replicates",
                    metricID: "Strength",
                    enabledByDefault: true,
                    supported: true,
                    supportReason: ""
                ),
            ]
        )
    }

    static func dataStudioComparisonPreview() -> DataStudioComparisonPreviewResponse {
        DataStudioComparisonPreviewResponse(
            comparisonSet: dataStudioComparisonSet(),
            recipe: dataStudioComparisonSet().recipes[0],
            preview: .init(filename: "representative_curve.pdf", pdfBase64: pdfBase64, qa: nil)
        )
    }

    static func dataStudioComparisonExport() -> DataStudioComparisonExportResponse {
        DataStudioComparisonExportResponse(
            comparisonSet: dataStudioComparisonSet(),
            figureOutputs: [
                .init(
                    path: "/tmp/data_studio_exports/primary-vs-second/representative_curve.pdf",
                    label: "Representative Curve Compare",
                    category: "curve",
                    templateID: "curve",
                    sheetName: "Representative_Curve",
                    metricID: nil,
                    recipeID: "representative_curve"
                ),
                .init(
                    path: "/tmp/data_studio_exports/primary-vs-second/strength_box.pdf",
                    label: "Strength Box Compare",
                    category: "metric",
                    templateID: "box",
                    sheetName: "Strength_Replicates",
                    metricID: "Strength",
                    recipeID: "strength_box"
                ),
            ]
        )
    }

    static func dataStudioSession() -> DataStudioSessionResponse {
        DataStudioSessionResponse(
            version: 1,
            selectedTemplateID: "builtin/tensile",
            selectedWorkbookID: "workbook-1",
            primaryWorkbookID: "workbook-1",
            selectedRecipeID: "representative_curve",
            workbookPaths: ["/tmp/prepared.xlsx"],
            comparisonRecipeIDs: ["representative_curve", "strength_box"],
            importedPaths: ["/tmp/raw_a.csv"],
            templateDraftPath: "/tmp/raw_a.csv"
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
            preferredSheet: "Representative_Curve",
            sheetNames: ["Representative_Curve", "Strength_Box"],
            sampleCount: 4,
            representativeFilename: "sample_b.csv",
            metrics: [
                .init(label: "Modulus", unit: "MPa", mean: 2.1, std: 0.1),
            ],
            warnings: ["Workbook summary loaded from prepared workbook."]
        )
    }

    static func tensileComparison() -> TensileComparisonExportResponse {
        TensileComparisonExportResponse(
            bundleDir: "/tmp/cleanup_bundle",
            comparisonWorkbookPath: "/tmp/cleanup_bundle/comparison.xlsx",
            labels: ["Primary Group", "Second Group"],
            outputs: ["/tmp/cleanup_bundle/strength_box.pdf", "/tmp/cleanup_bundle/modulus_bar.pdf"],
            figureOutputs: [
                .init(
                    path: "/tmp/cleanup_bundle/strength_box.pdf",
                    category: "metric",
                    kind: "box_compare",
                    metric: "Strength",
                    label: "Strength Box Compare"
                ),
                .init(
                    path: "/tmp/cleanup_bundle/modulus_bar.pdf",
                    category: "metric",
                    kind: "bar_compare",
                    metric: "Modulus",
                    label: "Modulus Bar Compare"
                ),
            ]
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
