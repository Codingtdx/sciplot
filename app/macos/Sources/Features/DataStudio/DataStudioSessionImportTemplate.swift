import Foundation

extension DataStudioSession {
    var resolverPresentation: DataStudioResolverPresentation {
        let sortedTemplates = templates.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        let useSelectedTemplateAvailability: ActionAvailability = selectedTemplateID == nil
            ? .disabled("Choose a parse template before continuing.")
            : .enabled()
        return DataStudioResolverPresentation(
            recommendedMatches: [],
            otherTemplates: sortedTemplates,
            useSelectedTemplateAvailability: useSelectedTemplateAvailability
        )
    }

    var createTemplateSuggestions: [DataStudioBindingSuggestionResponse] { [] }
    var createTemplatePrimaryCurveSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryMetricSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryMetadataSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryStructureSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplateSecondaryCurveSuggestions: [DataStudioBindingSuggestionResponse] { [] }
    var createTemplateFocusedSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePreviewCaption: String? { nil }
    var activePreviewRanges: [DataStudioPreviewRangeResponse] { [] }

    var templateEditorPresentation: DataStudioTemplateEditorPresentation {
        DataStudioTemplateEditorPresentation(
            previewCaption: templatePreviewSummary,
            primaryCurveSuggestion: nil,
            primaryMetricSuggestion: nil,
            primaryMetadataSuggestion: nil,
            primaryStructureSuggestion: nil,
            secondaryCurveSuggestions: [],
            advancedCandidates: [],
            selectedSummaryItems: selectedTemplateSummaryItems,
            saveTemplateAvailability: createTemplateSaveAvailability,
            saveTemplateAndContinueAvailability: createTemplateSaveAndContinueAvailability
        )
    }

    var selectedTemplateSummaryItems: [DataStudioTemplateSummaryItem] {
        var items: [DataStudioTemplateSummaryItem] = []
        if let sourcePreview {
            items.append(
                .init(
                    id: "source",
                    title: "Source",
                    value: URL(fileURLWithPath: sourcePreview.inputPath).lastPathComponent
                )
            )
            if let encoding = sourcePreview.encoding, !encoding.isEmpty {
                items.append(.init(id: "encoding", title: "Encoding", value: encoding))
            }
            if let delimiter = sourcePreview.delimiter, !delimiter.isEmpty {
                let label = delimiter == "\t" ? "Tab" : delimiter
                items.append(.init(id: "delimiter", title: "Delimiter", value: label))
            }
        }
        if let selectedSegment {
            items.append(.init(id: "segment", title: "Segment", value: selectedSegment.label))
        }
        if let x = templateDraftXColumnName, !x.isEmpty {
            items.append(.init(id: "x", title: "X", value: x))
        }
        if !templateDraftYColumnNames.isEmpty {
            items.append(.init(id: "y", title: "Y", value: templateDraftYColumnNames.joined(separator: ", ")))
        }
        if !templateDraftMetricColumnNames.isEmpty {
            items.append(
                .init(
                    id: "metrics",
                    title: "Metrics",
                    value: templateDraftMetricColumnNames.joined(separator: ", ")
                )
            )
        }
        return items
    }

    var selectedTemplate: DataStudioTemplateResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first(where: { $0.id == selectedTemplateID })
    }

    var selectedSegment: SourceTableSegmentResponse? {
        guard let selectedPreviewSegmentID else {
            return nil
        }
        return sourcePreview?.segments.first(where: { $0.id == selectedPreviewSegmentID })
    }

    var templatePreviewSummary: String? {
        guard let templatePreview else {
            return nil
        }
        if !templatePreview.errors.isEmpty {
            return templatePreview.errors.joined(separator: " ")
        }
        if !templatePreview.missingRoles.isEmpty {
            return "Missing roles: \(templatePreview.missingRoles.joined(separator: ", "))."
        }
        switch templatePreview.outputKind {
        case "metric_table":
            return "\(templatePreview.metricCount) metric fields resolved."
        case "matrix_heatmap":
            return "\(templatePreview.matrixRowCount) matrix rows resolved."
        default:
            return "\(templatePreview.seriesCount) curves resolved."
        }
    }

    var canGoBackInImportWizard: Bool {
        switch importWizardStep {
        case .scope:
            return false
        case .kind:
            return hasSessionContent
        case .resolver, .createTemplate:
            return true
        }
    }

    func beginImportFlow() {
        clearImportFlowError()
        if hasSessionContent {
            pendingImportDisposition = .addToCurrentSession
            importFlow = .wizard(step: .scope)
        } else {
            pendingImportDisposition = .addToCurrentSession
            importFlow = .wizard(step: .kind)
        }
    }

    func chooseImportDisposition(_ disposition: DataStudioImportDisposition) {
        clearImportFlowError()
        pendingImportDisposition = disposition
        importFlow = .wizard(step: .kind)
    }

    func chooseImportKind(_ kind: DataStudioImportKind) {
        clearImportFlowError()
        pendingImportKind = kind
        importFlow = .idle
        scheduleImportPanelPresentation()
    }

    func dismissImportScope() {
        clearImportFlowError()
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
    }

    func dismissImportChooser() {
        clearImportFlowError()
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    func goBackInImportWizard() {
        switch importWizardStep {
        case .scope:
            break
        case .kind:
            if hasSessionContent {
                importFlow = .wizard(step: .scope)
            }
        case .resolver:
            importFlow = .wizard(step: .kind)
        case .createTemplate:
            returnToImportResolver()
        }
    }

    func dismissImportWizard() {
        clearImportFlowError()
        resetImportPresentationState()
        discardPendingSourcePreview()
    }

    func handleImportPanelResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            Task { await handleImportedFiles(urls) }
        case let .failure(error):
            handleImportPanelFailure(error)
        }
    }

    func handleImportPanelFailure(_ error: Error) {
        resetImportPresentationState()
        if isUserCancelled(error) {
            clearImportFlowError()
            return
        }
        errorMessage = error.localizedDescription
    }

    func handleImportedFiles(_ urls: [URL]) async {
        if let projectURL = urls.first(where: { $0.pathExtension.lowercased() == "sciplotgod" }) {
            await openProject(projectURL)
            return
        }
        switch pendingImportKind {
        case .rawFiles:
            await handleImportedRawFiles(urls)
        case .existingWorkbook:
            await handleImportedWorkbooks(urls)
        }
    }

    func openProject(_ url: URL) async {
        guard let client else {
            errorMessage = "The sidecar is not ready yet."
            return
        }
        do {
            let response = try await client.openProject(.init(projectPath: url.path))
            await restoreProject(from: response)
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedRawFiles(_ urls: [URL]) async {
        guard let sampleURL = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first, let client else {
            return
        }
        if pendingImportDisposition == .startNewSession {
            resetContentState()
        }
        importedSourceURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        currentActivity = .previewingSource
        errorMessage = nil
        defer {
            currentActivity = .idle
            pendingImportDisposition = .addToCurrentSession
        }
        do {
            if templates.isEmpty {
                let response = try await client.fetchDataStudioTemplates()
                templates = response.templates.sorted {
                    $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
            }
            let basePreview = try await client.sourceTablePreview(
                .init(inputPath: sampleURL.path, sheet: .index(0), offset: 0, limit: 50)
            )
            let resolvedPreview: SourceTablePreviewResponse
            if let firstSegment = basePreview.segments.first {
                resolvedPreview = try await client.sourceTablePreview(
                    .init(
                        inputPath: sampleURL.path,
                        sheet: basePreview.sheet,
                        offset: 0,
                        limit: 50,
                        encoding: basePreview.encoding,
                        delimiter: basePreview.delimiter,
                        segmentID: firstSegment.id
                    )
                )
            } else {
                resolvedPreview = basePreview
            }
            sourcePreview = resolvedPreview
            selectedPreviewSegmentID = resolvedPreview.selectedSegmentID ?? resolvedPreview.segments.first?.id
            selectedPreviewSheetName = resolvedPreview.sheet.displayString
            selectedPreviewBlockID = selectedPreviewSegmentID
            configureDraftDefaults(from: resolvedPreview, sampleURL: sampleURL)
            selectedTemplateID = templates.first(where: \.builtin)?.id ?? templates.first?.id
            importFlow = .wizard(step: .resolver)
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func importWithSelectedTemplate() async {
        guard let selectedTemplateID else {
            errorMessage = "Choose a parse template before importing the current raw files."
            return
        }
        importFlow = .idle
        await Task.yield()
        await buildWorkbookFromPendingRawFiles(templateID: selectedTemplateID)
    }

    func beginCreateTemplateEditor() {
        guard sourcePreview != nil else {
            errorMessage = "Import a sample source file before creating a parse template."
            return
        }
        templatePreview = nil
        importFlow = .wizard(step: .createTemplate)
    }

    func dismissCreateTemplateEditor() {
        clearImportFlowError()
        returnToImportResolver()
    }

    func returnToImportResolver() {
        importFlow = .wizard(step: .resolver)
    }

    func saveTemplateDraft() async {
        guard let template = await createTemplateFromDraft() else {
            return
        }
        selectedTemplateID = template.id
        importFlow = .wizard(step: .resolver)
    }

    func saveTemplateAndContinueImport() async {
        guard let template = await createTemplateFromDraft() else {
            return
        }
        selectedTemplateID = template.id
        importFlow = .idle
        await Task.yield()
        await buildWorkbookFromPendingRawFiles(templateID: template.id)
    }

    func dismissImportResolver() {
        clearImportFlowError()
        resetImportPresentationState()
        discardPendingSourcePreview()
    }

    func selectPreviewSheet(name: String) {
        selectedPreviewSheetName = name
    }

    func selectPreviewBlock(id: String) {
        selectedPreviewBlockID = id
        selectPreviewSegment(id: id)
    }

    func selectPreviewSegment(id: String?) {
        guard selectedPreviewSegmentID != id else {
            return
        }
        selectedPreviewSegmentID = id
        selectedPreviewBlockID = id
        guard let sourcePreview, let client else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await client.sourceTablePreview(
                    .init(
                        inputPath: sourcePreview.inputPath,
                        sheet: sourcePreview.sheet,
                        offset: 0,
                        limit: sourcePreview.limit,
                        encoding: sourcePreview.encoding,
                        delimiter: sourcePreview.delimiter,
                        segmentID: id
                    )
                )
                self.sourcePreview = response
                self.configureDraftDefaults(from: response, sampleURL: URL(fileURLWithPath: response.inputPath))
            } catch {
                if isUserCancelled(error) {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setTemplateOutputKind(_ outputKind: String) {
        templateDraftOutputKind = outputKind
        templatePreview = nil
    }

    func setDraftXColumn(_ columnName: String?) {
        templateDraftXColumnName = columnName
        templatePreview = nil
    }

    func setDraftYColumn(_ columnName: String, isSelected: Bool) {
        if isSelected {
            if !templateDraftYColumnNames.contains(columnName) {
                templateDraftYColumnNames.append(columnName)
            }
        } else {
            templateDraftYColumnNames.removeAll { $0 == columnName }
        }
        templatePreview = nil
    }

    func setDraftMetricColumn(_ columnName: String, isSelected: Bool) {
        if isSelected {
            if !templateDraftMetricColumnNames.contains(columnName) {
                templateDraftMetricColumnNames.append(columnName)
            }
        } else {
            templateDraftMetricColumnNames.removeAll { $0 == columnName }
        }
        templatePreview = nil
    }

    func setHoveredSuggestion(id: String?) {
        hoveredSuggestionID = id
        hoveredPreviewRanges = []
    }

    func toggleSuggestion(id: String) {
        if selectedSuggestionIDs.contains(id) {
            selectedSuggestionIDs.removeAll { $0 == id }
        } else {
            selectedSuggestionIDs.append(id)
        }
    }

    func setCandidateSelection(id: String, isSelected: Bool) {
        if isSelected {
            if !selectedCandidateIDs.contains(id) {
                selectedCandidateIDs.append(id)
            }
        } else {
            selectedCandidateIDs.removeAll { $0 == id }
        }
    }

    func focusPreview(on candidate: DataStudioFieldCandidateResponse) {
        selectedPreviewSheetName = candidate.sheetName
        selectedPreviewBlockID = candidate.blockID
    }

    func focusPreview(onSuggestion suggestion: DataStudioBindingSuggestionResponse) {
        selectedPreviewSheetName = suggestion.sheetName
        selectedPreviewBlockID = suggestion.blockID
    }

    func handleImportedWorkbooks(_ urls: [URL], refreshContext: Bool = true) async {
        guard let client else {
            return
        }
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sorted.isEmpty else {
            return
        }
        if pendingImportDisposition == .startNewSession {
            resetContentState()
        }
        isBusy = true
        currentActivity = .importingWorkbooks
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
            pendingImportDisposition = .addToCurrentSession
        }
        do {
            for url in sorted {
                let imported = try await client.importDataStudioWorkbook(.init(workbookPath: url.path))
                if imported.workbooks.isEmpty {
                    throw NSError(
                        domain: "DataStudioImport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) did not resolve to any importable workbook groups."]
                    )
                }
                for workbook in imported.workbooks {
                    upsertWorkbook(workbook, shouldFocus: true)
                }
            }
            if refreshContext {
                await rebuildComparisonContext(refreshWorkbookPreviews: true)
            }
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func renameSelectedTemplate(to newLabel: String) async {
        guard let client, let selectedTemplate else {
            return
        }
        guard !selectedTemplate.builtin else {
            errorMessage = "Built-in parse templates cannot be renamed."
            return
        }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Parse template name cannot be empty."
            return
        }
        errorMessage = nil
        do {
            let response = try await client.updateDataStudioTemplate(
                templateID: selectedTemplate.id,
                request: .init(newID: nil, newLabel: trimmed)
            )
            if let index = templates.firstIndex(where: { $0.id == selectedTemplate.id }) {
                templates[index] = response
            }
            selectedTemplateID = response.id
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedTemplate() async {
        guard let client, let selectedTemplate else {
            return
        }
        guard !selectedTemplate.builtin else {
            errorMessage = "Built-in parse templates cannot be deleted."
            return
        }
        errorMessage = nil
        do {
            try await client.deleteDataStudioTemplate(templateID: selectedTemplate.id)
            templates.removeAll { $0.id == selectedTemplate.id }
            if selectedTemplateID == selectedTemplate.id {
                selectedTemplateID = templates.first?.id
            }
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private var createTemplateSaveAvailability: ActionAvailability {
        let trimmedLabel = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            return .disabled("Provide a parse template name before saving it.")
        }
        guard sourcePreview != nil else {
            return .disabled("Import a source file before saving the parse template.")
        }
        switch templateDraftOutputKind {
        case "metric_table":
            if templateDraftMetricColumnNames.isEmpty {
                return .disabled("Choose at least one metric column.")
            }
        case "matrix_heatmap":
            if templateDraftXColumnName == nil || templateDraftYColumnNames.isEmpty || templateDraftMetricColumnNames.isEmpty {
                return .disabled("Choose X, Y, and value columns.")
            }
        default:
            if templateDraftXColumnName == nil {
                return .disabled("Choose an X column.")
            }
            if templateDraftYColumnNames.isEmpty {
                return .disabled("Choose at least one Y column.")
            }
        }
        return .enabled()
    }

    private var createTemplateSaveAndContinueAvailability: ActionAvailability {
        createTemplateSaveAvailability
    }

    private func createTemplateFromDraft() async -> DataStudioTemplateResponse? {
        guard let sourceURL = importedSourceURLs.first, let client else {
            errorMessage = "Import a sample source file before saving a new parse template."
            return nil
        }
        let label = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            errorMessage = "Provide a parse template name before saving it."
            return nil
        }
        guard let request = draftTemplateRequest(label: label) else {
            return nil
        }
        currentActivity = .creatingTemplate
        errorMessage = nil
        defer { currentActivity = .idle }
        do {
            let preview = try await client.previewDataStudioTemplate(
                .init(sourcePath: sourceURL.path, template: request)
            )
            templatePreview = preview
            if !preview.errors.isEmpty {
                errorMessage = preview.errors.joined(separator: " ")
                return nil
            }
            if !preview.missingRoles.isEmpty {
                errorMessage = "Missing required roles: \(preview.missingRoles.joined(separator: ", "))."
                return nil
            }
            let template = try await client.createDataStudioTemplate(request)
            if let index = templates.firstIndex(where: { $0.id == template.id }) {
                templates[index] = template
            } else {
                templates.append(template)
            }
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return template
        } catch {
            if isUserCancelled(error) {
                return nil
            }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func draftTemplateRequest(label: String) -> DataStudioCreateTemplateRequest? {
        guard let sourcePreview else {
            errorMessage = "Import a source file before saving the parse template."
            return nil
        }
        var bindings: [DataStudioTemplateFieldBindingResponse] = []
        let segmentSelectors = draftSegmentSelectors(from: sourcePreview)
        switch templateDraftOutputKind {
        case "metric_table":
            for columnName in templateDraftMetricColumnNames {
                bindings.append(fieldBinding(idPrefix: "metric", role: "metric", label: columnName, columnName: columnName))
            }
        case "matrix_heatmap":
            guard let xColumn = templateDraftXColumnName,
                  let yColumn = templateDraftYColumnNames.first,
                  let zColumn = templateDraftMetricColumnNames.first
            else {
                errorMessage = "Choose X, Y, and value columns."
                return nil
            }
            bindings.append(fieldBinding(idPrefix: "matrix_x", role: "matrix_x", label: xColumn, columnName: xColumn))
            bindings.append(fieldBinding(idPrefix: "matrix_y", role: "matrix_y", label: yColumn, columnName: yColumn))
            bindings.append(fieldBinding(idPrefix: "matrix_z", role: "matrix_z", label: zColumn, columnName: zColumn))
        default:
            guard let xColumn = templateDraftXColumnName else {
                errorMessage = "Choose an X column."
                return nil
            }
            bindings.append(fieldBinding(idPrefix: "x", role: "curve_x", label: xColumn, columnName: xColumn))
            for columnName in templateDraftYColumnNames {
                bindings.append(fieldBinding(idPrefix: "y", role: "curve_y", label: columnName, columnName: columnName))
            }
            for columnName in templateDraftMetricColumnNames {
                bindings.append(fieldBinding(idPrefix: "metric", role: "metric", label: columnName, columnName: columnName, optional: true))
            }
        }
        return DataStudioCreateTemplateRequest(
            label: label,
            templateID: nil,
            description: templateDraftDescription,
            outputKind: templateDraftOutputKind,
            sourceFormat: .init(
                encoding: sourcePreview.encoding,
                delimiter: sourcePreview.delimiter,
                sheetName: sourcePreview.sheet.displayString
            ),
            segmentPolicy: segmentSelectors.isEmpty ? "single_table" : "series_per_segment",
            segmentSelectors: segmentSelectors,
            fieldBindings: bindings,
            matchConditions: []
        )
    }

    private func draftSegmentSelectors(from preview: SourceTablePreviewResponse) -> [DataStudioTemplateSegmentSelectorResponse] {
        if let selectedPreviewSegmentID,
           let segment = preview.segments.first(where: { $0.id == selectedPreviewSegmentID })
        {
            return [selector(from: segment)]
        }
        if preview.segments.isEmpty {
            return []
        }
        return preview.segments.map(selector(from:))
    }

    private func selector(from segment: SourceTableSegmentResponse) -> DataStudioTemplateSegmentSelectorResponse {
        DataStudioTemplateSegmentSelectorResponse(
            id: segment.id,
            label: segment.label,
            resultLabel: segment.resultLabel,
            intervalIndex: segment.intervalIndex,
            headerRowIndex: segment.headerRowIndex,
            unitRowIndex: segment.unitRowIndex,
            dataStartRowIndex: segment.dataStartRowIndex,
            startRow: segment.startRow,
            endRow: segment.endRow
        )
    }

    private func fieldBinding(
        idPrefix: String,
        role: String,
        label: String,
        columnName: String,
        optional: Bool = false
    ) -> DataStudioTemplateFieldBindingResponse {
        DataStudioTemplateFieldBindingResponse(
            id: "\(idPrefix)_\(stableColumnToken(columnName))",
            role: role,
            label: label,
            sheetName: sourcePreview?.sheet.displayString,
            blockID: selectedPreviewSegmentID,
            columnName: columnName,
            columnIndex: nil,
            rowLabelContains: nil,
            cellValueContains: [],
            unitHint: unitHint(for: columnName),
            optional: optional
        )
    }

    private func unitHint(for columnName: String) -> String? {
        guard let profile = sourcePreview?.columnProfiles.first(where: { $0.name == columnName }) else {
            return nil
        }
        guard profile.headerPreview.count > 1 else {
            return nil
        }
        return profile.headerPreview[1]
    }

    private func configureDraftDefaults(from preview: SourceTablePreviewResponse, sampleURL: URL) {
        templatePreview = nil
        templateDraftLabel = inferGroupName(from: importedSourceURLs.isEmpty ? [sampleURL] : importedSourceURLs)
        templateDraftDescription = "Template created from \(sampleURL.lastPathComponent)."
        templateDraftOutputKind = "curve_metrics"
        let availableNames = preview.columnHeaders.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        templateDraftXColumnName = preview.detectedXLabel ?? preview.candidateRoles.x.first ?? availableNames.first
        let xName = templateDraftXColumnName
        let recommendedY = preview.candidateRoles.y.filter { $0 != xName }
        templateDraftYColumnNames = Array(recommendedY.prefix(3))
        if templateDraftYColumnNames.isEmpty {
            templateDraftYColumnNames = Array(availableNames.filter { $0 != xName }.prefix(1))
        }
        templateDraftMetricColumnNames = Array(preview.candidateRoles.metric.prefix(4))
    }

    private func buildWorkbookFromPendingRawFiles(templateID: String) async {
        guard let client else {
            return
        }
        let sourceURLs = importedSourceURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sourceURLs.isEmpty else {
            errorMessage = "Import raw files before building a workbook."
            return
        }
        let inferredGroupName = inferGroupName(from: sourceURLs)
        let suggestedName = "\(inferredGroupName).xlsx"
        guard let outputURL = chooseWorkbookSaveLocation(suggestedName) else {
            return
        }
        let chosenGroupName = outputURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = chosenGroupName.isEmpty ? inferredGroupName : chosenGroupName
        isBusy = true
        currentActivity = .buildingWorkbook
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
        }
        do {
            let workbook = try await client.buildDataStudioWorkbook(
                .init(
                    filePaths: sourceURLs.map(\.path),
                    outputPath: outputURL.path,
                    templateID: templateID,
                    groupName: groupName
                )
            )
            upsertWorkbook(workbook, shouldFocus: true)
            await rebuildComparisonContext(refreshWorkbookPreviews: true)
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleImportPanelPresentation() {
        importPanelPresentationRevision += 1
        let revision = importPanelPresentationRevision
        importFlow = .idle
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.importPanelPresentationRevision == revision else {
                return
            }
            self.importFlow = .importer(kind: self.pendingImportKind)
        }
    }

    private func clearImportFlowError() {
        errorMessage = nil
    }

    private func resetImportPresentationState() {
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    private func discardPendingSourcePreview() {
        importedSourceURLs = []
        sourcePreview = nil
        templatePreview = nil
        hoveredSuggestionID = nil
        selectedSuggestionIDs = []
        hoveredPreviewRanges = []
        pinnedPreviewRanges = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
        templateDraftOutputKind = "curve_metrics"
        templateDraftXColumnName = nil
        templateDraftYColumnNames = []
        templateDraftMetricColumnNames = []
        selectedPreviewSheetName = nil
        selectedPreviewBlockID = nil
        selectedPreviewSegmentID = nil
        showAdvancedCandidates = false
        if case .wizard(step: .createTemplate) = importFlow {
            importFlow = .wizard(step: .resolver)
        }
    }

    private func stableColumnToken(_ value: String) -> String {
        let pieces = value.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }
        let token = pieces.joined().split(separator: "_").joined(separator: "_")
        return token.isEmpty ? UUID().uuidString : token
    }

    private func inferGroupName(from urls: [URL]) -> String {
        guard let first = urls.first else {
            return "DataStudio_Group"
        }
        return first.deletingPathExtension().lastPathComponent
    }
}

private extension SheetValue {
    var displayString: String {
        switch self {
        case let .index(value):
            return String(value)
        case let .name(value):
            return value
        }
    }
}
