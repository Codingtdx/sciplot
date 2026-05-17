import Foundation
@testable import SciPlotMac

enum TestPayloads {
    static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9oNnfdcAAAAASUVORK5CYII="
    static let pdfBase64 = "JVBERi0xLjEKMSAwIG9iajw8Pj5lbmRvYmoKMiAwIG9iajw8IC9UeXBlIC9DYXRhbG9nIC9QYWdlcyAzIDAgUiA+PmVuZG9iagozIDAgb2JqPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFs0IDAgUl0gL0NvdW50IDEgPj5lbmRvYmoKNCAwIG9iajw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMyAwIFIgL01lZGlhQm94IFswIDAgNzIgNzJdID4+ZW5kb2JqCnhyZWYKMCA1CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxMCAwMDAwMCBuIAowMDAwMDAwMDMwIDAwMDAwIG4gCjAwMDAwMDAwODEgMDAwMDAgbiAKMDAwMDAwMDEzOCAwMDAwMCBuIAp0cmFpbGVyPDwgL1NpemUgNSAvUm9vdCAyIDAgUiA+PgpzdGFydHhyZWYKMjA5CiUlRU9GCg=="
    static let compatibleOpenAPIRoutes: [SidecarRouteSignature] = [
        .init(method: "GET", path: "/health"),
        .init(method: "GET", path: "/meta"),
        .init(method: "GET", path: "/plot-contract"),
        .init(method: "GET", path: "/plot-themes"),
        .init(method: "POST", path: "/plot-themes/preview"),
        .init(method: "POST", path: "/plot-themes"),
        .init(method: "PUT", path: "/plot-themes/{theme_id}"),
        .init(method: "DELETE", path: "/plot-themes/{theme_id}"),
        .init(method: "GET", path: "/scientific-text/rules"),
        .init(method: "POST", path: "/scientific-text/rules/preview"),
        .init(method: "POST", path: "/scientific-text/rules"),
        .init(method: "PUT", path: "/scientific-text/rules/{rule_id}"),
        .init(method: "DELETE", path: "/scientific-text/rules/{rule_id}"),
        .init(method: "POST", path: "/inspect-file"),
        .init(method: "POST", path: "/source-table-preview"),
        .init(method: "POST", path: "/fit-analysis"),
        .init(method: "POST", path: "/analysis-operation"),
        .init(method: "POST", path: "/import-preview"),
        .init(method: "POST", path: "/plot-edit-command/normalize"),
        .init(method: "POST", path: "/save-project"),
        .init(method: "POST", path: "/open-project"),
        .init(method: "POST", path: "/preflight-render"),
        .init(method: "POST", path: "/render-preview"),
        .init(method: "POST", path: "/export-render"),
        .init(method: "POST", path: "/code-console/context"),
        .init(method: "POST", path: "/code-console/run"),
        .init(method: "POST", path: "/compose-preview"),
        .init(method: "POST", path: "/compose-export"),
        .init(method: "GET", path: "/data-studio/templates"),
        .init(method: "POST", path: "/data-studio/template-preview"),
        .init(method: "POST", path: "/data-studio/template-recommendations"),
        .init(method: "POST", path: "/data-studio/build-workbook"),
        .init(method: "POST", path: "/data-studio/import-workbook"),
        .init(method: "POST", path: "/data-studio/workbook-preview"),
        .init(method: "POST", path: "/data-studio/comparison-context"),
        .init(method: "POST", path: "/data-studio/comparison-preview"),
        .init(method: "POST", path: "/data-studio/comparison-export"),
        .init(method: "POST", path: "/data-studio/session/normalize"),
    ]

    static func compatibleOpenAPIJSON(excluding excludedRoutes: Set<SidecarRouteSignature> = []) -> String {
        var paths: [String: [String: [String: String]]] = [:]
        for route in compatibleOpenAPIRoutes where !excludedRoutes.contains(route) {
            var methods = paths[route.path] ?? [:]
            methods[route.method.lowercased()] = [:]
            paths[route.path] = methods
        }
        let payload = ["paths": paths]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func compatibleOpenAPIData(excluding excludedRoutes: Set<SidecarRouteSignature> = []) -> Data {
        Data(compatibleOpenAPIJSON(excluding: excludedRoutes).utf8)
    }

    static let sharedAvailablePalettes = [
        "colorblind_safe",
        "deep",
        "muted",
        "mono",
        "infographic",
        "roma",
        "macarons",
        "shine",
        "vintage",
        "okabe_ito",
        "tol_muted",
        "tableau_10",
        "seaborn_pastel",
        "seaborn_dark",
        "primer_accessible",
        "viridis_discrete",
    ]

    static let sharedAvailableStyles = [
        "nature",
        "acs",
        "science",
        "wiley",
        "elsevier",
    ]

    static func styleCatalog() -> [MetaStyleResponse] {
        [
            .init(
                id: "nature",
                label: "Nature",
                public: true,
                displayGroup: "publication",
                description: "Default publication style.",
                hardConstraints: true,
                presetNote: "Repo default",
                recommendedPalettePreset: "colorblind_safe",
                recommendedVisualThemeID: "clean_light"
            ),
            .init(
                id: "acs",
                label: "ACS",
                public: true,
                displayGroup: "publication",
                description: "ACS-inspired publication style.",
                hardConstraints: false,
                presetNote: "Publisher-inspired preset",
                recommendedPalettePreset: "okabe_ito",
                recommendedVisualThemeID: "clean_light"
            ),
            .init(
                id: "science",
                label: "Science",
                public: true,
                displayGroup: "publication",
                description: "Science-inspired publication style.",
                hardConstraints: false,
                presetNote: "Publisher-inspired preset",
                recommendedPalettePreset: "colorblind_safe",
                recommendedVisualThemeID: "clean_light"
            ),
            .init(
                id: "wiley",
                label: "Wiley",
                public: true,
                displayGroup: "publication",
                description: "Wiley-inspired publication style.",
                hardConstraints: false,
                presetNote: "Publisher-inspired preset",
                recommendedPalettePreset: "tol_muted",
                recommendedVisualThemeID: "clean_light"
            ),
            .init(
                id: "elsevier",
                label: "Elsevier",
                public: true,
                displayGroup: "publication",
                description: "Elsevier-inspired publication style.",
                hardConstraints: false,
                presetNote: "Publisher-inspired preset",
                recommendedPalettePreset: "muted",
                recommendedVisualThemeID: "clean_light"
            ),
        ]
    }

    static func paletteCatalog() -> [MetaPaletteResponse] {
        [
            .init(id: "colorblind_safe", label: "Colorblind Safe", public: true, description: "Default palette.", swatches: ["#112233", "#445566"]),
            .init(id: "deep", label: "Deep", public: true, description: "Balanced palette.", swatches: ["#4c72b0", "#dd8452"]),
            .init(id: "muted", label: "Muted", public: true, description: "Restrained palette.", swatches: ["#4878d0", "#ee854a"]),
            .init(id: "mono", label: "Mono", public: true, description: "Monochrome palette.", swatches: ["#111827", "#6b7280"]),
            .init(id: "infographic", label: "Infographic", public: true, description: "Brighter ECharts-inspired palette.", swatches: ["#5470c6", "#91cc75"]),
            .init(id: "roma", label: "Roma", public: true, description: "Warm-cool ECharts-inspired palette.", swatches: ["#e01f54", "#001852"]),
            .init(id: "macarons", label: "Macarons", public: true, description: "Pastel ECharts-inspired palette.", swatches: ["#2ec7c9", "#b6a2de"]),
            .init(id: "shine", label: "Shine", public: true, description: "Official ECharts Shine palette.", swatches: ["#c12e34", "#e6b600"]),
            .init(id: "vintage", label: "Vintage", public: true, description: "Official ECharts Vintage palette.", swatches: ["#d87c7c", "#919e8b"]),
            .init(id: "okabe_ito", label: "Okabe-Ito", public: true, description: "Colorblind-friendly scientific palette.", swatches: ["#000000", "#e69f00"]),
            .init(id: "tol_muted", label: "Tol Muted", public: true, description: "Muted scientific palette.", swatches: ["#332288", "#88ccee"]),
            .init(id: "tableau_10", label: "Tableau 10", public: true, description: "Matplotlib Tableau palette.", swatches: ["#1f77b4", "#ff7f0e"]),
            .init(id: "seaborn_pastel", label: "Seaborn Pastel", public: true, description: "Soft Seaborn palette.", swatches: ["#a1c9f4", "#ffb482"]),
            .init(id: "seaborn_dark", label: "Seaborn Dark", public: true, description: "Darker Seaborn palette.", swatches: ["#001c7f", "#b1400d"]),
            .init(id: "primer_accessible", label: "Primer Accessible", public: true, description: "Primer-inspired accessible palette.", swatches: ["#0969da", "#1a7f37"]),
            .init(id: "viridis_discrete", label: "Viridis Discrete", public: true, description: "Discrete viridis samples.", swatches: ["#440154", "#482878"]),
        ]
    }

    static func visualThemeCatalog() -> [VisualThemeResponse] {
        [
            .init(id: "clean_light", label: "Clean Light", description: "A minimal publication surface"),
            .init(id: "soft_grid", label: "Soft Grid", description: "A quiet grid-forward theme"),
            .init(id: "presentation_like", label: "Presentation Like", description: "A slide-friendly mint surface"),
            .init(id: "infographic", label: "Infographic", description: "A brighter editorial theme"),
            .init(id: "roma", label: "Roma", description: "A warm editorial surface"),
            .init(id: "macarons", label: "Macarons", description: "A cooler pastel theme"),
            .init(id: "shine", label: "Shine", description: "A crisp display surface"),
            .init(id: "vintage", label: "Vintage", description: "A warm paper-tone theme"),
        ]
    }

    static func meta() -> SidecarMetaResponse {
        SidecarMetaResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizes: [
                .init(id: "60x55", label: "Single 60 x 55 mm", widthMm: 60, heightMm: 55),
                .init(id: "120x55", label: "Wide 120 x 55 mm", widthMm: 120, heightMm: 55),
                .init(id: "180x55", label: "Full row 180 x 55 mm", widthMm: 180, heightMm: 55),
                .init(id: "60x110", label: "Tall 60 x 110 mm", widthMm: 60, heightMm: 110),
                .init(id: "120x110", label: "Large 120 x 110 mm", widthMm: 120, heightMm: 110),
                .init(id: "180x110", label: "Full tall 180 x 110 mm", widthMm: 180, heightMm: 110),
            ],
            styles: styleCatalog(),
            palettes: paletteCatalog(),
            templates: [
                .init(
                    id: "curve",
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    presentationKind: "curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "series_order",
                        "legend_position",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "curve"
                ),
                .init(
                    id: "area_curve",
                    label: "Area Curve",
                    description: "Curve template with translucent area fill.",
                    category: "curve",
                    presentationKind: "area_curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "area_curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "area_curve"
                ),
                .init(
                    id: "step_line",
                    label: "Step Line",
                    description: "Curve template with stepped interpolation.",
                    category: "curve",
                    presentationKind: "step_line",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "step_line",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "step_line"
                ),
                .init(
                    id: "function_curve",
                    label: "Function Curve",
                    description: "Bounded function-layer curve template.",
                    category: "curve",
                    presentationKind: "function_curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "analytical_layers",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "function_curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "function_curve"
                ),
                .init(
                    id: "stacked_area",
                    label: "Stacked Area",
                    description: "Stacked curve template with translucent filled bands.",
                    category: "curve",
                    presentationKind: "stacked_area",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "reverse_x",
                        "baseline",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "stacked_area",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "stacked_area"
                ),
                .init(
                    id: "bar",
                    label: "Bar",
                    description: "Bar comparison template.",
                    category: "stats",
                    presentationKind: "bar",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
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
                    presentationKind: "box",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
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
                    presentationKind: "box_strip",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "box_strip",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "box_strip"
                ),
                .init(
                    id: "density_area",
                    label: "Density Area",
                    description: "Smoothed density areas with outline overlays.",
                    category: "stats",
                    presentationKind: "density_area",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "x_min",
                        "x_max",
                        "y_min",
                        "y_max",
                        "x_tick_density",
                        "x_tick_edge_labels",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "series_order",
                        "legend_position",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "density_area",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "density_area"
                ),
            ],
            templateIds: ["curve", "area_curve", "step_line", "function_curve", "stacked_area", "bar", "box", "box_strip", "density_area"],
            sizeIds: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
            palettePresetIds: sharedAvailablePalettes,
            visualThemes: visualThemeCatalog()
        )
    }

    static func multiSeriesMeta() -> SidecarMetaResponse {
        SidecarMetaResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizes: [
                .init(id: "60x55", label: "Single 60 x 55 mm", widthMm: 60, heightMm: 55),
                .init(id: "120x55", label: "Wide 120 x 55 mm", widthMm: 120, heightMm: 55),
                .init(id: "180x55", label: "Full row 180 x 55 mm", widthMm: 180, heightMm: 55),
                .init(id: "60x110", label: "Tall 60 x 110 mm", widthMm: 60, heightMm: 110),
                .init(id: "120x110", label: "Large 120 x 110 mm", widthMm: 120, heightMm: 110),
                .init(id: "180x110", label: "Full tall 180 x 110 mm", widthMm: 180, heightMm: 110),
            ],
            styles: styleCatalog(),
            palettes: paletteCatalog(),
            templates: [
                .init(
                    id: "curve",
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    presentationKind: "curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    canonicalID: "curve",
                    role: "plot",
                    lifecyclePolicy: "stable",
                    implementationID: "curve"
                ),
            ],
            templateIds: ["curve"],
            sizeIds: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
            palettePresetIds: sharedAvailablePalettes,
            visualThemes: visualThemeCatalog()
        )
    }

    static func contract() -> PlotContractResponse {
        PlotContractResponse(
            version: 1,
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizePresets: [
                "60x55": .init(label: "Single 60 x 55 mm", widthMm: 60, heightMm: 55),
                "120x55": .init(label: "Wide 120 x 55 mm", widthMm: 120, heightMm: 55),
                "180x55": .init(label: "Full row 180 x 55 mm", widthMm: 180, heightMm: 55),
                "60x110": .init(label: "Tall 60 x 110 mm", widthMm: 60, heightMm: 110),
                "120x110": .init(label: "Large 120 x 110 mm", widthMm: 120, heightMm: 110),
                "180x110": .init(label: "Full tall 180 x 110 mm", widthMm: 180, heightMm: 110),
            ],
            styles: [
                "nature": .string("Nature"),
                "acs": .string("ACS"),
                "science": .string("Science"),
                "wiley": .string("Wiley"),
                "elsevier": .string("Elsevier"),
            ],
            palettes: [
                "colorblind_safe": .string("Colorblind Safe"),
                "deep": .string("Deep"),
                "muted": .string("Muted"),
                "mono": .string("Mono"),
                "infographic": .string("Infographic"),
                "roma": .string("Roma"),
                "macarons": .string("Macarons"),
                "shine": .string("Shine"),
                "vintage": .string("Vintage"),
            ],
            templates: [
                "curve": .init(
                    label: "Curve",
                    description: "Continuous curve template.",
                    category: "curve",
                    presentationKind: "curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "series_order",
                        "legend_position",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Use the shared axis frame."],
                    softRules: ["Keep labels minimal."]
                ),
                "area_curve": .init(
                    label: "Area Curve",
                    description: "Curve template with translucent area fill.",
                    category: "curve",
                    presentationKind: "area_curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Use the shared axis frame."],
                    softRules: ["Keep labels minimal."]
                ),
                "step_line": .init(
                    label: "Step Line",
                    description: "Curve template with stepped interpolation.",
                    category: "curve",
                    presentationKind: "step_line",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Use the shared axis frame."],
                    softRules: ["Keep labels minimal."]
                ),
                "function_curve": .init(
                    label: "Function Curve",
                    description: "Bounded function-layer curve template.",
                    category: "curve",
                    presentationKind: "function_curve",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                        "extra_x_axis",
                        "extra_y_axis",
                        "x_axis_breaks",
                        "y_axis_breaks",
                        "analytical_layers",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Keep the function layer backend-owned."],
                    softRules: ["Use the shared curve axis semantics." ]
                ),
                "stacked_area": .init(
                    label: "Stacked Area",
                    description: "Stacked curve template with translucent filled bands.",
                    category: "curve",
                    presentationKind: "stacked_area",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "reverse_x",
                        "baseline",
                        "series_order",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Preserve stacked spectral readability."],
                    softRules: ["Keep filled bands translucent."]
                ),
                "bar": .init(
                    label: "Bar",
                    description: "Bar comparison template.",
                    category: "stats",
                    presentationKind: "bar",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable outlier spacing."]
                ),
                "box": .init(
                    label: "Box",
                    description: "Box comparison template.",
                    category: "stats",
                    presentationKind: "box",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
                        "y_min",
                        "y_max",
                        "y_tick_density",
                        "y_tick_edge_labels",
                        "style_preset",
                        "palette_preset",
                    ],
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable outlier spacing."]
                ),
                "box_strip": .init(
                    label: "Box + Strip",
                    description: "Box comparison template with strip overlay.",
                    category: "stats",
                    presentationKind: "box_strip",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
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
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable outlier spacing."]
                ),
                "density_area": .init(
                    label: "Density Area",
                    description: "Smoothed density areas with outline overlays.",
                    category: "stats",
                    presentationKind: "density_area",
                    defaultSize: "60x55",
                    allowedSizes: ["60x55", "120x55", "180x55", "60x110", "120x110", "180x110"],
                    editableOptions: [
                        "size",
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
                    defaultOptions: [
                        "style_preset": .string("nature"),
                        "palette_preset": .string("colorblind_safe"),
                        "visual_theme_id": .string("clean_light"),
                    ],
                    availableStyles: sharedAvailableStyles,
                    availablePalettes: sharedAvailablePalettes,
                    hardRules: ["Keep the shared axis frame."],
                    softRules: ["Preserve readable density overlap."]
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
                size: "60x55",
                stylePreset: "nature",
                palettePreset: "colorblind_safe",
                visualThemeID: "clean_light"
            ),
            promptText: """
            Write one Python script for the SciPlot Code Console.
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

    static func analysisOperation() -> AnalysisOperationResponse {
        AnalysisOperationResponse(
            operationID: "analysis.smoothing",
            inputPath: "/tmp/curve.csv",
            sheet: .index(0),
            operationResult: AnalysisOperationResultPayload(
                operationID: "analysis.smoothing",
                available: true,
                valid: true,
                statusCode: "ok",
                message: "Smoothing complete.",
                diagnostics: [],
                metrics: ["point_count": .number(3)],
                tables: [],
                overlays: [],
                dataContainers: []
            )
        )
    }

    static func importPreview() -> ImportPreviewResponse {
        ImportPreviewResponse(
            inputPath: "/tmp/records.json",
            filterID: "import.json",
            status: "experimental",
            label: "JSON",
            dataContainers: [],
            diagnostics: [],
            optionsSchema: ["type": .string("object")],
            help: "JSON records preview is experimental."
        )
    }

    static func plotEditCommandNormalize() -> PlotEditCommandNormalizeResponse {
        PlotEditCommandNormalizeResponse(
            command: PlotEditCommandPayload(
                commandID: "cmd-visible",
                kind: "visibility",
                targetObjectID: "plot:guide:target",
                before: ["visible": .bool(true)],
                after: ["visible": .bool(false)],
                graphPatch: ["target_object_id": .string("plot:guide:target")],
                reversible: true,
                help: "Undoable typed plot edit command."
            ),
            diagnostics: []
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
            options: RenderOptionsPayload(size: "60x55", xscale: "linear", yscale: "linear"),
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
                .init(filename: "sample_curve.pdf", pdfBase64: pdfBase64, pngBase64: pngBase64, qa: nil),
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

    static func sourceTablePreview(
        path: String = "/tmp/sample.csv",
        offset: Int = 0,
        selectedSegmentID: String? = nil
    ) -> SourceTablePreviewResponse {
        SourceTablePreviewResponse(
            inputPath: path,
            sheet: .name("Representative_Curve"),
            offset: offset,
            limit: 50,
            totalRows: 3,
            totalCols: 2,
            columnHeaders: ["Strain", "Stress"],
            rows: [
                [.number(0.0), .number(0.0)],
                [.number(0.1), .number(6.2)],
                [.number(0.2), .number(12.0)],
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
            detectedXLabel: "Strain",
            detectedYLabel: "Stress",
            columnProfiles: [
                .init(
                    name: "Strain",
                    headerPreview: ["Strain", "%"],
                    inferredType: "numeric",
                    nonEmptyCount: 3,
                    missingCount: 0,
                    minValue: 0.0,
                    maxValue: 0.2
                ),
                .init(
                    name: "Stress",
                    headerPreview: ["Stress", "MPa"],
                    inferredType: "numeric",
                    nonEmptyCount: 3,
                    missingCount: 0,
                    minValue: 0.0,
                    maxValue: 12.0
                ),
            ],
            segments: [],
            selectedSegmentID: selectedSegmentID,
            encoding: "utf-8",
            delimiter: ","
        )
    }

    static func fitAnalysis(
        path: String = "/tmp/sample.csv",
        offset: Int = 0
    ) -> FitAnalysisResponse {
        FitAnalysisResponse(
            inputPath: path,
            sheet: .name("Representative_Curve"),
            modelID: "linear",
            xLabel: "Strain",
            yLabel: "Stress",
            selectedSeriesID: "series-1",
            equationDisplay: "y = 60x + 0.0333",
            slope: 60.0,
            intercept: 0.0333,
            rSquared: 0.999,
            rmse: 0.109,
            pointCount: 3,
            seriesSummaries: [
                .init(
                    seriesID: "series-1",
                    seriesLabel: "Series 1",
                    equationDisplay: "y = 60x + 0.0333",
                    rSquared: 0.999,
                    rmse: 0.109,
                    pointCount: 3,
                    slope: 60.0,
                    intercept: 0.0333,
                    warnings: []
                ),
            ],
            warnings: [],
            totalRows: 3,
            offset: offset,
            limit: 50,
            rows: [
                .init(rowIndex: 0, x: 0.0, y: 0.0, yFit: 0.0333, residual: -0.0333),
                .init(rowIndex: 1, x: 0.1, y: 6.2, yFit: 6.0333, residual: 0.1667),
                .init(rowIndex: 2, x: 0.2, y: 12.0, yFit: 12.0333, residual: -0.0333),
            ]
        )
    }

    static func plotProjectPayload(
        sourcePath: String = "/tmp/sample.csv",
        projectName: String = "sample-project",
        templateID: String = "curve",
        sheet: SheetValue = .name("Representative_Curve"),
        fitOptions: FitOptionsPayload = FitOptionsPayload(),
        renderOptions: RenderOptionsPayload = RenderOptionsPayload(
            size: "60x55",
            stylePreset: "nature",
            palettePreset: "colorblind_safe",
            visualThemeID: "clean_light"
        )
    ) -> ProjectBundlePayload {
        ProjectBundlePayload(
            version: 1,
            selectedWorkbench: "plot",
            plot: PlotProjectPayload(
                sessionKind: "plot",
                sourceFilename: URL(fileURLWithPath: sourcePath).lastPathComponent,
                sourceMediaType: "text/csv",
                embeddedSourceRelpath: "sources/plot/primary/\(URL(fileURLWithPath: sourcePath).lastPathComponent)",
                sourceSHA256: "abc123",
                sheet: sheet,
                selectedTemplateID: templateID,
                renderOptions: renderOptions,
                fitOptions: fitOptions,
                projectDisplayName: projectName,
                sourceProvenance: .init(
                    originalInputPath: sourcePath,
                    savedInputMtimeNs: 123,
                    savedAt: "2026-04-21T10:00:00Z"
                )
            ),
            dataStudio: nil,
            composer: nil,
            codeConsole: nil,
            artifacts: ["manifest_relpath": .string("artifacts/manifest.json")]
        )
    }

    static func saveProjectResponse(
        projectPath: String = "/tmp/sample.sciplot",
        payload: ProjectBundlePayload? = nil
    ) -> SaveProjectResponse {
        SaveProjectResponse(
            projectPath: projectPath,
            payload: payload ?? plotProjectPayload()
        )
    }

    static func openProjectResponse(
        projectPath: String = "/tmp/sample.sciplot",
        restoredSourcePath: String = "/tmp/restored/sample.csv",
        payload: ProjectBundlePayload? = nil
    ) -> OpenProjectResponse {
        OpenProjectResponse(
            projectPath: projectPath,
            restoredSourcePath: restoredSourcePath,
            restoredWorkbookPaths: [],
            payload: payload ?? plotProjectPayload(sourcePath: restoredSourcePath)
        )
    }

    static func dataStudioTemplate(
        id: String = "builtin/tensile",
        label: String = "Tensile",
        comparisonEnabled: Bool = true
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
            outputKind: "curve_metrics",
            comparisonEnabled: comparisonEnabled,
            sourceFormat: .init(encoding: nil, delimiter: nil, sheetName: nil),
            segmentPolicy: "single_table",
            segmentSelectors: [],
            metadata: ["builtin_family": .string("tensile")]
        )
    }

    static func dataStudioTemplatePreview() -> DataStudioTemplatePreviewResponse {
        DataStudioTemplatePreviewResponse(
            templateID: "user/new_template",
            outputKind: "curve_metrics",
            parsedSampleCount: 1,
            failedSampleCount: 0,
            seriesCount: 1,
            metricCount: 0,
            matrixRowCount: 0,
            missingRoles: [],
            warnings: [],
            errors: [],
            segments: [
                .init(
                    id: "Sheet1::table",
                    label: "Sheet1",
                    curveCount: 1,
                    metricCount: 0,
                    rowCount: 3
                ),
            ]
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

    static func dataStudioTemplateRecommendations(
        matches: [DataStudioTemplateMatchResponse] = [
            DataStudioTemplateMatchResponse(
                templateID: "builtin/tensile",
                label: "Tensile",
                family: "tensile",
                confidence: 0.98,
                reasons: ["Matched by fixture hints."],
                warnings: [],
                matchedSheetNames: ["Sheet1"],
                autoSelected: true
            ),
        ]
    ) -> DataStudioTemplateRecommendationsResponse {
        DataStudioTemplateRecommendationsResponse(matches: matches)
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
        excludedSpecimenIDs: Set<String> = [],
        selectedRepresentativeSpecimenID: String? = nil
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
        let representative = includedSpecimens.first(where: { $0.id == selectedRepresentativeSpecimenID })
            ?? includedSpecimens.sorted { abs($0.strength - 100) < abs($1.strength - 100) }.first
            ?? specimens[3]

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
            ],
            filteredWorkbooks: [
                .init(
                    path: "/tmp/data_studio_exports/primary-vs-second/filtered_workbooks/Primary.xlsx",
                    label: "Primary",
                    sourceWorkbookPath: "/tmp/prepared.xlsx",
                    representativeFilename: "sample_2.csv"
                ),
                .init(
                    path: "/tmp/data_studio_exports/primary-vs-second/filtered_workbooks/Second.xlsx",
                    label: "Second",
                    sourceWorkbookPath: "/tmp/second.xlsx",
                    representativeFilename: "sample_3.csv"
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
                .init(
                    workbookPath: "/tmp/prepared.xlsx",
                    specimenId: "sample-a",
                    included: true,
                    selectedAsRepresentative: true
                ),
                .init(workbookPath: "/tmp/prepared.xlsx", specimenId: "sample-b", included: false),
            ],
            figurePreferences: [
                .init(
                    familyID: "representative_curve",
                    selectedTemplateID: "curve",
                    optionsByTemplate: [
                        "curve": RenderOptionsPayload(
                            size: "60x55",
                            stylePreset: "nature",
                            palettePreset: "colorblind_safe",
                            visualThemeID: "clean_light"
                        ),
                    ],
                    fitOptionsByTemplate: [:]
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
