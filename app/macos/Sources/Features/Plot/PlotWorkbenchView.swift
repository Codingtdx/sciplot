import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.selectedSourceFilename != nil {
                topSourceBar
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                PlotTemplateView(session: session)
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)

                PlotRefineView(session: session)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.importFile(first)
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: bindingForGuide) {
            PlotGuideSheet(session: session)
        }
        .sheet(isPresented: bindingForSourceInspector) {
            PlotSourceInspectorSheet(session: session)
        }
    }

    private var topSourceBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(session.selectedSourceFilename ?? "")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            if session.selectedFileURL != nil {
                Picker("Sheet", selection: selectedSheetBinding) {
                    ForEach(session.availableSheets, id: \.self) { sheet in
                        Text(sheet.displayName).tag(sheet)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
            }

            Image(systemName: session.liveStatusSymbol)
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating,
                    value: session.isInspecting || session.isPreviewing
                )
                .font(.headline)
                .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange)
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var bindingForGuide: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }

    private var bindingForSourceInspector: Binding<Bool> {
        Binding(
            get: { session.isSourceInspectorPresented },
            set: { session.isSourceInspectorPresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}

private struct PlotGuideSheet: View {
    let session: PlotSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideSection(
                        title: "Live Canvas",
                        text: "Plot is state-driven. Importing a source immediately kicks off inspect, template recommendation, and preview rendering."
                    )
                    guideSection(
                        title: "Sheets",
                        text: "Switching sheets re-runs inspect and refreshes the preview automatically. The last successful preview stays visible until the new one is ready."
                    )
                    guideSection(
                        title: "Templates",
                        text: "Use the left rail to switch between the top compatible templates. Template changes immediately refresh the preview."
                    )
                    guideSection(
                        title: "Inspector",
                        text: "Use the inspector for compact plot options, axis controls, and legend ordering. Keep the canvas dominant and move secondary helpers into lightweight surfaces."
                    )
                    axisLabelOverridesSection
                    dataTemplatesSection
                    guideSection(
                        title: "Export",
                        text: "Export is available from both the toolbar and inspector Actions section. Choose PDF or 300 dpi TIFF first, then choose the destination for the current plot state."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Plot Guide")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        session.dismissGuide()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var axisLabelOverridesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Axis Label Overrides")
                .font(.headline)

            Text("Auto normalization currently includes replacements like frequency -> ω, storage modulus -> G', shear strain -> γ, stress -> σ, and 2theta -> 2θ. Use overrides below when you want exact wording for the current Plot session.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("X label")
                        .foregroundStyle(.secondary)
                    TextField(
                        session.recommendedXAxisLabel ?? "Use recommended label",
                        text: axisLabelBinding(
                            get: { session.renderOptions.xLabelOverride },
                            set: { newValue in
                                session.updateRenderOptions(policy: .debounced) { $0.xLabelOverride = newValue }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Y label")
                        .foregroundStyle(.secondary)
                    TextField(
                        session.recommendedYAxisLabel ?? "Use recommended label",
                        text: axisLabelBinding(
                            get: { session.renderOptions.yLabelOverride },
                            set: { newValue in
                                session.updateRenderOptions(policy: .debounced) { $0.yLabelOverride = newValue }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            if session.recommendedXAxisLabel != nil || session.recommendedYAxisLabel != nil {
                Text(
                    "Recommended: X = \(session.recommendedXAxisLabel ?? "Auto"), Y = \(session.recommendedYAxisLabel ?? "Auto")"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Reset Overrides") {
                    session.updateRenderOptions(policy: .immediate) {
                        $0.xLabelOverride = nil
                        $0.yLabelOverride = nil
                    }
                }
                .buttonStyle(.bordered)

                Text("Session-only. Preview and export both use these overrides.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private var dataTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data File Templates")
                .font(.headline)

            Text("Open the built-in example tables when you need a quick reference for supported input structure.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open Curve Table") {
                    session.openExampleDataTemplate(named: "curve_table.csv")
                }
                .buttonStyle(.borderedProminent)

                Button("Open Replicate Table") {
                    session.openExampleDataTemplate(named: "replicate_table.csv")
                }
                .buttonStyle(.bordered)

                Button("Reveal in Finder") {
                    session.revealExampleDataTemplates()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private func guideSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private func axisLabelBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String> {
        Binding(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }
}

private struct PlotSourceInspectorSheet: View {
    let session: PlotSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSummaryCard
                    inspectSummaryCard
                    candidateRolesCard
                    rawDataCard
                }
                .padding(24)
            }
            .navigationTitle("Source Inspector")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        session.dismissSourceInspector()
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var sourceSummaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("File", value: session.selectedSourceFilename ?? "Unknown")
                if let path = session.selectedSourcePath {
                    LabeledContent("Path", value: path)
                        .textSelection(.enabled)
                }
                LabeledContent("Sheet", value: session.selectedSheet.displayName)
                if let template = session.selectedTemplateSummary?.label {
                    LabeledContent("Template", value: template)
                }

                HStack(spacing: 10) {
                    Button("Open Source") {
                        session.openCurrentSource()
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal Source") {
                        session.revealCurrentSource()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var inspectSummaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let inspection = session.inspectionResponse {
                    LabeledContent("Model", value: inspection.inspection.modelLabel)
                    LabeledContent("Confidence", value: inspection.inspection.recommendationConfidence.formatted(.percent.precision(.fractionLength(0...0))))
                    if let dataset = inspection.dataset {
                        LabeledContent("Rows", value: "\(dataset.rawRows)")
                        LabeledContent("Columns", value: "\(dataset.rawCols)")
                        if !dataset.dataShapes.isEmpty {
                            LabeledContent("Shapes", value: dataset.dataShapes.joined(separator: ", "))
                        }
                        if !dataset.semanticSignals.isEmpty {
                            LabeledContent("Signals", value: dataset.semanticSignals.joined(separator: ", "))
                        }
                        if !dataset.qualityFlags.isEmpty {
                            LabeledContent("Flags", value: dataset.qualityFlags.joined(separator: ", "))
                        }
                    }
                    if !inspection.inspection.warnings.isEmpty {
                        ForEach(inspection.inspection.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    }
                    if !inspection.inspection.signals.isEmpty {
                        ForEach(inspection.inspection.signals, id: \.self) { signal in
                            Label(signal, systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                } else {
                    Text("No inspect payload")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Inspect")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var candidateRolesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if session.candidateRoleRows.isEmpty {
                    Text("No candidate roles")
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(session.candidateRoleRows, id: \.0) { role, values in
                            GridRow {
                                Text(role)
                                    .foregroundStyle(.secondary)
                                Text(values)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Candidate Roles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var rawDataCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if session.sampleColumns.isEmpty || session.sampleRows.isEmpty {
                    Text("No raw sample rows")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                Text("#")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(session.sampleColumns) { column in
                                    Text(column.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ForEach(session.sampleRows) { row in
                                GridRow {
                                    Text("\(row.id + 1)")
                                        .foregroundStyle(.secondary)
                                    ForEach(session.sampleColumns) { column in
                                        Text(row.value(at: column.id).displayString)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Raw Data")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
