import SwiftUI

extension PlotInspectorView {
    var figureAdjustmentContent: some View {
        Group {
            if session.selectedTemplateSummary == nil {
                InspectorSection(title: "Figure") {
                    InspectorEmptyState(message: "Import data")
                }
            } else {
                plotOptionsSection
            }
        }
    }

    var axesAdjustmentContent: some View {
        InspectorSection(title: "Axis") {
            if !shouldShowPrimaryAxesControls {
                InspectorEmptyState(message: "No axis controls")
            } else {
                axisScaleControls
                axisRangeControls
                if showsTickLabelControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tick Labels")
                            .font(.subheadline.weight(.semibold))

                        if supportsTickLabelControls(for: .x) {
                            axisTickLabelControls(title: "X axis", axis: .x)
                        }

                        if supportsTickLabelControls(for: .y) {
                            axisTickLabelControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    var legendAdjustmentContent: some View {
        Group {
            if session.shouldShowSeriesLegendControls {
                seriesSection
            } else {
                InspectorSection(title: "Legend") {
                    InspectorEmptyState(message: "No reorderable legend entries")
                }
            }
        }
    }

    var guidesAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Guides") {
                HStack(spacing: 8) {
                    Button("Add Line") {
                        session.addReferenceGuide(kind: "line")
                        if let id = session.selectedReferenceGuideID {
                            session.selectPlotLayer(.referenceGuide(id))
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference line.")

                    Button("Add Region") {
                        session.addReferenceGuide(kind: "band")
                        if let id = session.selectedReferenceGuideID {
                            session.selectPlotLayer(.referenceGuide(id))
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference region.")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                objectList(
                    emptyMessage: "No guides",
                    rows: session.referenceGuides.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: referenceGuideTitle($0),
                            detail: $0.kind == "band" ? "Region" : "Line",
                            systemImage: $0.kind == "band" ? "rectangle.dashed" : "ruler",
                            selection: .referenceGuide($0.id)
                        )
                    }
                )
            }

            selectedGuideEditor
        }
    }

    var fitAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            fitOverlaySection
            InspectorSection(title: "Analysis") {
                Button {
                    session.showDataWorkbook(tab: .fit)
                } label: {
                    Label("Open Fit Table", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.fitAnalysisAvailability.isEnabled)
                .help(session.fitAnalysisAvailability.reason ?? "Open fit analysis results.")
            }
        }
    }

    var functionsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Functions") {
                Button("Add Function") {
                    session.addAnalyticalFunctionLayer()
                    if let layer = session.analyticalLayers.last {
                        session.selectPlotLayer(.function(layer.id))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.analyticalLayerAvailability.isEnabled)
                .help(session.analyticalLayerAvailability.reason ?? "Add a backend-rendered function layer.")

                objectList(
                    emptyMessage: "No function layers",
                    rows: session.analyticalLayers.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: functionTitle($0),
                            detail: "Function",
                            systemImage: "function",
                            selection: .function($0.id)
                        )
                    }
                )
            }

            selectedFunctionEditor
        }
    }

    var annotationsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Annotations") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Add Text") {
                            session.addTextAnnotation()
                            if let id = session.selectedTextAnnotationID {
                                session.selectPlotLayer(.textAnnotation(id))
                            }
                        }
                        .disabled(!session.textAnnotationAvailability.isEnabled)
                        .help(session.textAnnotationAvailability.reason ?? "Add text.")

                        Button("Add Callout") {
                            session.addTextAnnotation(displayStyle: "callout", connectorEnabled: true)
                            if let id = session.selectedTextAnnotationID {
                                session.selectPlotLayer(.textAnnotation(id))
                            }
                        }
                        .disabled(!session.textAnnotationAvailability.isEnabled)
                        .help(session.textAnnotationAvailability.reason ?? "Add a callout.")
                    }

                    HStack(spacing: 8) {
                        Button("Rectangle") {
                            addShape(kind: "rectangle")
                        }
                        Button("Ellipse") {
                            addShape(kind: "ellipse")
                        }
                        Button("Bracket") {
                            addShape(kind: "bracket")
                        }
                    }
                    .disabled(!session.shapeAnnotationAvailability.isEnabled)
                    .help(session.shapeAnnotationAvailability.reason ?? "Add a shape annotation.")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                objectList(emptyMessage: "No annotations", rows: annotationRows)
            }

            selectedAnnotationEditor
        }
    }

    var advancedAxesAdjustmentContent: some View {
        InspectorSection(title: "Advanced Axes") {
            if !showsExtraAxesControls && !showsAxisBreakControls {
                InspectorEmptyState(message: "No advanced axis controls")
            } else {
                if showsExtraAxesControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Extra Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsExtraXAxisControls {
                            extraAxisControls(title: "X axis", axis: .x)
                        }

                        if supportsExtraYAxisControls {
                            extraAxisControls(title: "Y axis", axis: .y)
                        }
                    }
                }

                if showsAxisBreakControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Broken Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsXAxisBreakControls {
                            axisBreakControls(title: "X axis", axis: .x)
                        }

                        if supportsYAxisBreakControls {
                            axisBreakControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
