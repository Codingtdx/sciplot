import SwiftUI

struct PlotInspectorView: View {
    @Bindable var session: PlotSession
    @State private var diagnosticsExpanded = false

    var body: some View {
        Form {
            sourceSection
            optionsSection
            readinessAndExportSection
            diagnosticsSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            if let selectedSourcePath = session.selectedSourcePath {
                LabeledContent("Path", value: selectedSourcePath)
                    .textSelection(.enabled)
                LabeledContent("Sheet", value: session.selectedSheet.displayName)

                if session.isInspecting {
                    Label("Inspecting source…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                if let modelLabel = session.inspectionResponse?.inspection.modelLabel {
                    LabeledContent("Model", value: modelLabel)
                }
            } else {
                Text("Import a Plot source to begin.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section("Options") {
            if let template = session.selectedTemplateSummary {
                if session.editableOptionIDs.contains("size") {
                    Picker("Canvas size", selection: $session.renderOptions.size.replacingNil(with: template.defaultSize)) {
                        ForEach(session.allowedSizes) { size in
                            Text(size.label).tag(Optional(size.id))
                        }
                    }
                }

                if session.editableOptionIDs.contains("xscale") {
                    Picker("X scale", selection: $session.renderOptions.xscale.replacingNil(with: "linear")) {
                        Text("Linear").tag(Optional("linear"))
                        Text("Log").tag(Optional("log"))
                    }
                }

                if session.editableOptionIDs.contains("yscale") {
                    Picker("Y scale", selection: $session.renderOptions.yscale.replacingNil(with: "linear")) {
                        Text("Linear").tag(Optional("linear"))
                        Text("Log").tag(Optional("log"))
                    }
                }

                if session.editableOptionIDs.contains("reverse_x") {
                    Toggle("Reverse X", isOn: $session.renderOptions.reverseX)
                }

                if session.editableOptionIDs.contains("baseline") {
                    TextField(
                        "Baseline",
                        text: Binding(
                            get: { session.renderOptions.baseline ?? "" },
                            set: { session.renderOptions.baseline = $0.isEmpty ? nil : $0 }
                        )
                    )
                }

                if session.editableOptionIDs.contains("show_colorbar") {
                    Toggle(
                        "Show colorbar",
                        isOn: Binding(
                            get: { session.renderOptions.showColorbar ?? false },
                            set: { session.renderOptions.showColorbar = $0 }
                        )
                    )
                }

                Picker("Style", selection: $session.renderOptions.stylePreset) {
                    ForEach(session.availableStyles) { style in
                        Text(style.label).tag(style.id)
                    }
                }

                Picker("Palette", selection: $session.renderOptions.palettePreset) {
                    ForEach(session.availablePalettes) { palette in
                        Text(palette.label).tag(palette.id)
                    }
                }

                if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                    Picker(
                        "Visual theme",
                        selection: Binding(
                            get: { session.renderOptions.visualThemeID ?? themes.first?.id ?? "" },
                            set: { session.renderOptions.visualThemeID = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        ForEach(themes) { theme in
                            Text(theme.label).tag(theme.id)
                        }
                    }
                }
            } else {
                Text("Choose a compatible template to edit render options.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var readinessAndExportSection: some View {
        Section("Readiness & Export") {
            Button("Run Preflight") {
                Task { await session.runPreflight() }
            }
            .disabled(!session.hasRenderableSelection || session.isRunningPreflight)

            if session.isRunningPreflight {
                Label("Running preflight…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            if let preflight = session.preflightResponse {
                LabeledContent(
                    "Readiness",
                    value: preflight.preflight.errors.isEmpty ? "Ready" : "Blocked"
                )
                if !preflight.preflight.warnings.isEmpty {
                    ForEach(preflight.preflight.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                if !preflight.preflight.errors.isEmpty {
                    ForEach(preflight.preflight.errors, id: \.self) { error in
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }

            Button("Export") {
                Task { await session.exportCurrentSelection() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.hasRenderableSelection || session.isExporting)

            if session.isExporting {
                Label("Exporting Plot…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            if let exportResponse = session.exportResponse {
                LabeledContent("Outputs", value: "\(exportResponse.outputs.count)")
                if let latestExportDestinationDescription = session.latestExportDestinationDescription {
                    LabeledContent("Destination", value: latestExportDestinationDescription)
                }
                Button("Reveal Latest Export") {
                    session.revealLatestExport()
                }
                .disabled(session.userExportURLs.isEmpty)
            }
            if let report = session.previewResponse?.submissionReport {
                LabeledContent("Submission", value: report.readiness)
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            let entries = diagnosticEntries

            if entries.isEmpty {
                Text("No active diagnostics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Show Diagnostics", isExpanded: $diagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            Label(entry.message, systemImage: entry.systemImage)
                                .foregroundStyle(entry.style)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private extension Binding where Value == String? {
    func replacingNil(with defaultValue: String) -> Binding<String?> {
        Binding<String?>(
            get: { wrappedValue ?? defaultValue },
            set: { wrappedValue = $0 }
        )
    }
}

private struct PlotDiagnosticEntry: Identifiable {
    let id = UUID()
    let message: String
    let systemImage: String
    let style: Color
}

private extension PlotInspectorView {
    var diagnosticEntries: [PlotDiagnosticEntry] {
        var entries: [PlotDiagnosticEntry] = []
        if let errorMessage = session.errorMessage {
            entries.append(
                PlotDiagnosticEntry(
                    message: errorMessage,
                    systemImage: "xmark.circle.fill",
                    style: .orange
                )
            )
        }

        if let inspection = session.inspectionResponse {
            entries.append(contentsOf: inspection.inspection.warnings.map {
                PlotDiagnosticEntry(message: $0, systemImage: "exclamationmark.triangle.fill", style: .orange)
            })
            entries.append(contentsOf: inspection.inspection.signals.map {
                PlotDiagnosticEntry(message: $0, systemImage: "info.circle", style: .secondary)
            })
        }

        return entries
    }
}
