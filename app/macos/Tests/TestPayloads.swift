import Foundation
@testable import SciPlotGodMac

enum TestPayloads {
    static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9oNnfdcAAAAASUVORK5CYII="
    static let pdfBase64 = "JVBERi0xLjEKMSAwIG9iajw8Pj5lbmRvYmoKMiAwIG9iajw8IC9UeXBlIC9DYXRhbG9nIC9QYWdlcyAzIDAgUiA+PmVuZG9iagozIDAgb2JqPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFs0IDAgUl0gL0NvdW50IDEgPj5lbmRvYmoKNCAwIG9iajw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMyAwIFIgL01lZGlhQm94IFswIDAgNzIgNzJdID4+ZW5kb2JqCnhyZWYKMCA1CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxMCAwMDAwMCBuIAowMDAwMDAwMDMwIDAwMDAwIG4gCjAwMDAwMDAwODEgMDAwMDAgbiAKMDAwMDAwMDEzOCAwMDAwMCBuIAp0cmFpbGVyPDwgL1NpemUgNSAvUm9vdCAyIDAgUiA+PgpzdGFydHhyZWYKMjA5CiUlRU9GCg=="

    static func meta() -> SidecarMetaResponse {
        SidecarMetaResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizes: [
                .init(id: "single_panel", label: "Single Panel", widthMm: 60, heightMm: 55),
                .init(id: "double_panel", label: "Double Panel", widthMm: 120, heightMm: 55),
            ],
            styles: [
                .init(
                    id: "nature",
                    label: "Nature",
                    public: true,
                    description: "Default publication style.",
                    hardConstraints: true,
                    presetNote: "Repo default"
                ),
            ],
            palettes: [
                .init(
                    id: "colorblind_safe",
                    label: "Colorblind Safe",
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
                    editableOptions: [
                        "size",
                        "xscale",
                        "yscale",
                        "x_min",
                        "x_max",
                        "y_min",
                        "y_max",
                        "x_tick_density",
                        "x_tick_edge_labels",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
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
                    editableOptions: [
                        "size",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    canonicalID: "bar",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "bar"
                ),
                .init(
                    id: "box",
                    label: "Box",
                    description: "Box comparison template.",
                    category: "stats",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    canonicalID: "box",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "box"
                ),
                .init(
                    id: "box_strip",
                    label: "Box + Strip",
                    description: "Box comparison template with strip overlay.",
                    category: "stats",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    canonicalID: "box_strip",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "box_strip"
                ),
            ],
            templateIds: ["curve", "bar", "box", "box_strip"],
            sizeIds: ["single_panel", "double_panel"],
            palettePresetIds: ["colorblind_safe"],
            visualThemes: [
                .init(id: "paper", label: "Paper", description: "Paper preview"),
            ]
        )
    }

    static func multiSeriesMeta() -> SidecarMetaResponse {
        SidecarMetaResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizes: [
                .init(id: "single_panel", label: "Single Panel", widthMm: 60, heightMm: 55),
                .init(id: "double_panel", label: "Double Panel", widthMm: 120, heightMm: 55),
            ],
            styles: [
                .init(
                    id: "nature",
                    label: "Nature",
                    public: true,
                    description: "Default publication style.",
                    hardConstraints: true,
                    presetNote: "Repo default"
                ),
            ],
            palettes: [
                .init(
                    id: "colorblind_safe",
                    label: "Colorblind Safe",
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
                    editableOptions: [
                        "size",
                        "xscale",
                        "yscale",
                        "x_min",
                        "x_max",
                        "y_min",
                        "y_max",
                        "x_tick_density",
                        "x_tick_edge_labels",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    canonicalID: "curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "curve"
                ),
            ],
            templateIds: ["curve"],
            sizeIds: ["single_panel", "double_panel"],
            palettePresetIds: ["colorblind_safe"],
            visualThemes: [
                .init(id: "paper", label: "Paper", description: "Paper preview"),
            ]
        )
    }

    static func contract() -> PlotContractResponse {
        PlotContractResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizePresets: [
                "single_panel": .init(label: "Single Panel", widthMm: 60, heightMm: 55),
            ],
            styles: [
                "nature": .string("Nature"),
            ],
            palettes: [
                "colorblind_safe": .string("Colorblind Safe"),
            ],
            templates: [
                "curve": .init(
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: [
                        "size",
                        "xscale",
                        "yscale",
                        "x_min",
                        "x_max",
                        "y_min",
                        "y_max",
                        "x_tick_density",
                        "x_tick_edge_labels",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    hardRules: ["Use the shared axis frame."],
                    softRules: ["Keep labels minimal."]
                ),
                "box": .init(
                    label: "Box",
                    description: "Box comparison template.",
                    category: "stats",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable outlier spacing."]
                ),
                "box_strip": .init(
                    label: "Box + Strip",
                    description: "Box comparison template with strip overlay.",
                    category: "stats",
                    defaultSize: "single_panel",
                    allowedSizes: ["single_panel"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [:],
                    availableStyles: ["nature"],
                    availablePalettes: ["colorblind_safe"],
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable outlier spacing."]
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
            contextID: "ctx_test_payload",
            inputPath: path,
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: inspectFile(path: path).inspection,
            dataset: inspectFile(path: path).dataset,
            template: "curve",
            options: .init(
                size: "single_panel",
                stylePreset: "nature",
                palettePreset: "colorblind_safe",
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
                                    [.number(0.1), .number(5.1), .number(12.7), .number(2.2)],
                                    [.number(0.2), .number(12.4), .number(12.8), .number(2.3)],
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
                    .init(
                        id: "candidate:header_row",
                        kind: "header_row",
                        label: "Sheet1 header row",
                        confidence: 0.7,
                        rationale: "Likely header row for this data block.",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        range: .init(sheetName: "Sheet1", startRow: 1, endRow: 1, startCol: 1, endCol: 4),
                        sampleValues: [],
                        unitHint: nil
                    ),
                    .init(
                        id: "candidate:unit_row",
                        kind: "unit_row",
                        label: "Sheet1 unit row",
                        confidence: 0.64,
                        rationale: "Likely unit row for this data block.",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        range: .init(sheetName: "Sheet1", startRow: 2, endRow: 2, startCol: 1, endCol: 4),
                        sampleValues: [],
                        unitHint: nil
                    ),
                ],
                bindingSuggestions: [
                    .init(
                        id: "sheet1:block0::curve_pair",
                        kind: "curve_pair",
                        title: "Recommended Curve",
                        summary: "X: Strain (%) · Y: Stress (MPa)",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        candidateIDs: ["candidate:strain", "candidate:stress"],
                        previewRanges: [
                            .init(sheetName: "Sheet1", blockID: "sheet1:block0", startRow: 1, endRow: 6, startCol: 1, endCol: 1, role: "x"),
                            .init(sheetName: "Sheet1", blockID: "sheet1:block0", startRow: 1, endRow: 6, startCol: 2, endCol: 2, role: "y"),
                        ],
                        defaultSelected: true,
                        rationale: "Recommended X/Y pair comes from the same numeric block.",
                        confidence: 0.96
                    ),
                    .init(
                        id: "sheet1:block0::metric_group",
                        kind: "metric_group",
                        title: "Recommended Metrics",
                        summary: "Strength (MPa)",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        candidateIDs: ["candidate:strength"],
                        previewRanges: [
                            .init(sheetName: "Sheet1", blockID: "sheet1:block0", startRow: 1, endRow: 6, startCol: 3, endCol: 3, role: "metric"),
                        ],
                        defaultSelected: true,
                        rationale: "Metric column detected in the same block.",
                        confidence: 0.92
                    ),
                    .init(
                        id: "sheet1:block0::structure_rows",
                        kind: "structure_rows",
                        title: "Detected Structure",
                        summary: "Header Row 2 · Unit Row 3",
                        sheetName: "Sheet1",
                        blockID: "sheet1:block0",
                        candidateIDs: ["candidate:header_row", "candidate:unit_row"],
                        previewRanges: [
                            .init(sheetName: "Sheet1", blockID: "sheet1:block0", startRow: 1, endRow: 1, startCol: 1, endCol: 4, role: "header_row"),
                            .init(sheetName: "Sheet1", blockID: "sheet1:block0", startRow: 2, endRow: 2, startCol: 1, endCol: 4, role: "unit_row"),
                        ],
                        defaultSelected: true,
                        rationale: "Detected header and unit rows for this block.",
                        confidence: 0.8
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

    static func dataStudioImportWorkbook(
        workbooks: [DataStudioWorkbookResponse] = [dataStudioWorkbook()]
    ) -> DataStudioImportWorkbookResponse {
        DataStudioImportWorkbookResponse(workbooks: workbooks)
    }

    static func dataStudioWorkbookPreview(
        path: String = "/tmp/prepared.xlsx",
        label: String = "Prepared Group"
    ) -> DataStudioWorkbookPreviewResponse {
        DataStudioWorkbookPreviewResponse(
            workbookPath: path,
            label: label,
            supported: true,
            unsupportedReason: "",
            totalSpecimenCount: 2,
            includedSpecimenCount: 2,
            excludedSpecimenCount: 0,
            representativeSpecimenId: "sample-a",
            representativeFilename: "raw_a.csv",
            metrics: [
                .init(id: "strength", label: "Strength", unit: "MPa", mean: 12.4, std: 0.4),
                .init(id: "modulus", label: "Modulus", unit: "MPa", mean: 2.1, std: 0.1),
            ],
            specimens: [
                .init(
                    specimenId: "sample-a",
                    label: "raw_a.csv",
                    filename: "raw_a.csv",
                    sourcePath: "/tmp/raw_a.csv",
                    included: true,
                    metrics: ["Strength": 12.4, "Modulus": 2.0, "Elongation": 9.8],
                    warnings: [],
                    exclusions: [],
                    miniCurvePoints: [
                        .init(x: 0, y: 0),
                        .init(x: 5, y: 6),
                        .init(x: 10, y: 12),
                    ],
                    triadComplete: true,
                    suggestedExclusion: false,
                    compositeSignedScore: nil,
                    distanceFromMeanScore: nil,
                    scoreSide: "ineligible",
                    autoRuleRole: "ineligible",
                    eligibleForAutoFilter: false
                ),
                .init(
                    specimenId: "sample-b",
                    label: "raw_b.csv",
                    filename: "raw_b.csv",
                    sourcePath: "/tmp/raw_b.csv",
                    included: true,
                    metrics: ["Strength": 12.8, "Modulus": 2.2, "Elongation": 10.1],
                    warnings: [],
                    exclusions: [],
                    miniCurvePoints: [
                        .init(x: 0, y: 0),
                        .init(x: 5, y: 5.5),
                        .init(x: 10, y: 11),
                    ],
                    triadComplete: true,
                    suggestedExclusion: false,
                    compositeSignedScore: nil,
                    distanceFromMeanScore: nil,
                    scoreSide: "ineligible",
                    autoRuleRole: "ineligible",
                    eligibleForAutoFilter: false
                ),
            ],
            warnings: [],
            suggestedExclusionIds: [],
            suggestionSupported: false,
            suggestionSupportReason: "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation."
        )
    }

    static func dataStudioWorkbookPreviewWithSuggestedExclusions(
        path: String = "/tmp/prepared.xlsx",
        label: String = "Prepared Group",
        excludedSpecimenIDs: Set<String> = []
    ) -> DataStudioWorkbookPreviewResponse {
        let specimens: [(id: String, filename: String, strength: Double, modulus: Double, elongation: Double)] = [
            ("sample-1", "sample_1.csv", 98, 1990, 9.8),
            ("sample-2", "sample_2.csv", 99, 1995, 9.9),
            ("sample-3", "sample_3.csv", 100, 2000, 10.0),
            ("sample-4", "sample_4.csv", 101, 2005, 10.1),
            ("sample-5", "sample_5.csv", 102, 2010, 10.2),
            ("sample-6", "sample_6.csv", 103, 2015, 10.3),
            ("sample-7", "sample_7.csv", 130, 2200, 12.0),
        ]
        let includedSpecimens = specimens.filter { !excludedSpecimenIDs.contains($0.id) }
        let representative = includedSpecimens.sorted { abs($0.strength - 100) < abs($1.strength - 100) }.first ?? specimens[3]

        func mean(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }

        func std(_ values: [Double]) -> Double {
            guard values.count > 1 else { return 0 }
            let average = mean(values)
            let variance = values.reduce(0) { partial, value in
                partial + pow(value - average, 2)
            } / Double(values.count - 1)
            return sqrt(variance)
        }

        let baselineStrengthMean = mean(specimens.map(\.strength))
        let baselineModulusMean = mean(specimens.map(\.modulus))
        let baselineElongationMean = mean(specimens.map(\.elongation))
        let baselineStrengthStd = std(specimens.map(\.strength))
        let baselineModulusStd = std(specimens.map(\.modulus))
        let baselineElongationStd = std(specimens.map(\.elongation))
        let baselineScores: [String: Double] = Dictionary(
            uniqueKeysWithValues: specimens.map { specimen in
                let signedScore = (
                    (specimen.strength - baselineStrengthMean) / max(baselineStrengthStd, 0.0001) +
                    (specimen.modulus - baselineModulusMean) / max(baselineModulusStd, 0.0001) +
                    (specimen.elongation - baselineElongationMean) / max(baselineElongationStd, 0.0001)
                ) / 3
                return (specimen.id, signedScore)
            }
        )
        let baselineKeepIDs = Set(
            specimens
                .sorted { lhs, rhs in
                    let left = abs(baselineScores[lhs.id] ?? .infinity)
                    let right = abs(baselineScores[rhs.id] ?? .infinity)
                    if left != right {
                        return left < right
                    }
                    return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
                }
                .prefix(5)
                .map(\.id)
        )
        let suggestionIDs = excludedSpecimenIDs.isEmpty
            ? specimens.compactMap { baselineKeepIDs.contains($0.id) ? nil : $0.id }
            : []
        let canSuggest = includedSpecimens.count >= 5

        return DataStudioWorkbookPreviewResponse(
            workbookPath: path,
            label: label,
            supported: true,
            unsupportedReason: "",
            totalSpecimenCount: specimens.count,
            includedSpecimenCount: includedSpecimens.count,
            excludedSpecimenCount: excludedSpecimenIDs.count,
            representativeSpecimenId: representative.id,
            representativeFilename: representative.filename,
            metrics: [
                .init(
                    id: "strength",
                    label: "Strength",
                    unit: "MPa",
                    mean: mean(includedSpecimens.map(\.strength)),
                    std: std(includedSpecimens.map(\.strength))
                ),
                .init(
                    id: "modulus",
                    label: "Modulus",
                    unit: "MPa",
                    mean: mean(includedSpecimens.map(\.modulus)),
                    std: std(includedSpecimens.map(\.modulus))
                ),
                .init(
                    id: "elongation",
                    label: "Elongation",
                    unit: "%",
                    mean: mean(includedSpecimens.map(\.elongation)),
                    std: std(includedSpecimens.map(\.elongation))
                ),
            ],
            specimens: specimens.map { specimen in
                let included = !excludedSpecimenIDs.contains(specimen.id)
                let signedScore = baselineScores[specimen.id] ?? 0
                return .init(
                    specimenId: specimen.id,
                    label: specimen.filename,
                    filename: specimen.filename,
                    sourcePath: "/tmp/\(specimen.filename)",
                    included: included,
                    metrics: [
                        "Strength": specimen.strength,
                        "Modulus": specimen.modulus,
                        "Elongation": specimen.elongation,
                    ],
                    warnings: [],
                    exclusions: included ? [] : ["Excluded from compare"],
                    miniCurvePoints: [
                        .init(x: 0, y: 0),
                        .init(x: 5, y: specimen.strength / 10),
                        .init(x: 10, y: specimen.strength / 5),
                    ],
                    triadComplete: true,
                    suggestedExclusion: suggestionIDs.contains(specimen.id),
                    compositeSignedScore: signedScore,
                    distanceFromMeanScore: abs(signedScore),
                    scoreSide: signedScore == 0 ? "neutral" : (signedScore < 0 ? "low" : "high"),
                    autoRuleRole: canSuggest
                        ? (baselineKeepIDs.contains(specimen.id) ? "keep" : "exclude")
                        : "ineligible",
                    eligibleForAutoFilter: true
                )
            },
            warnings: [],
            suggestedExclusionIds: suggestionIDs,
            suggestionSupported: canSuggest,
            suggestionSupportReason: canSuggest
                ? ""
                : "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation."
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

    static func dataStudioComparisonContext() -> DataStudioComparisonContextResponse {
        DataStudioComparisonContextResponse(
            comparisonSet: dataStudioComparisonSet(),
            cacheKey: "preview-cache-key",
            materializedAt: "2026-04-07T12:00:00Z"
        )
    }

    static func dataStudioComparisonSetSharedMetricTemplate() -> DataStudioComparisonSetResponse {
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
                    id: "strength_box_strip",
                    label: "Strength Box + Strip Compare",
                    category: "metric",
                    templateID: "box_strip",
                    sheetName: "Strength_Replicates",
                    metricID: "Strength",
                    enabledByDefault: true,
                    supported: true,
                    supportReason: ""
                ),
                .init(
                    id: "elongation_box_strip",
                    label: "Elongation Box + Strip Compare",
                    category: "metric",
                    templateID: "box_strip",
                    sheetName: "Elongation_Replicates",
                    metricID: "Elongation",
                    enabledByDefault: true,
                    supported: true,
                    supportReason: ""
                ),
            ]
        )
    }

    static func dataStudioComparisonContextSharedMetricTemplate() -> DataStudioComparisonContextResponse {
        DataStudioComparisonContextResponse(
            comparisonSet: dataStudioComparisonSetSharedMetricTemplate(),
            cacheKey: "preview-cache-key-shared-template",
            materializedAt: "2026-04-09T12:00:00Z"
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
            selectedFigureFamilyID: "representative_curve",
            selectedFigureTemplateID: "curve",
            groupStates: [
                .init(
                    workbookPath: "/tmp/prepared.xlsx",
                    displayName: "Prepared Group",
                    includeInCompare: true,
                    sortOrder: 0
                ),
            ],
            specimenStates: [
                .init(workbookPath: "/tmp/prepared.xlsx", specimenId: "sample-a", included: true),
                .init(workbookPath: "/tmp/prepared.xlsx", specimenId: "sample-b", included: false),
            ],
            figurePreferences: [
                .init(
                    familyID: "representative_curve",
                    selectedTemplateID: "curve",
                    optionsByTemplate: [
                        "curve": RenderOptionsPayload(
                            size: "single_panel",
                            stylePreset: "nature",
                            palettePreset: "colorblind_safe",
                            visualThemeID: "paper"
                        ),
                    ]
                ),
            ],
            importedPaths: ["/tmp/raw_a.csv"],
            templateDraftPath: "/tmp/raw_a.csv"
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
            stylePreset: "nature",
            palettePreset: "colorblind_safe",
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
