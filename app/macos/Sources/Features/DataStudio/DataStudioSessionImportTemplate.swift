import Foundation

extension DataStudioSession {
    var resolverPresentation: DataStudioResolverPresentation {
        let recommendedMatches = sourceMatches.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.confidence > rhs.confidence
        }
        let matchedIDs = Set(recommendedMatches.map(\.templateID))
        let otherTemplates = templates
            .filter { !matchedIDs.contains($0.id) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        let useSelectedTemplateAvailability: ActionAvailability
        if selectedTemplateID == nil {
            useSelectedTemplateAvailability = .disabled("Choose a parse template before continuing.")
        } else {
            useSelectedTemplateAvailability = .enabled()
        }
        return DataStudioResolverPresentation(
            recommendedMatches: recommendedMatches,
            otherTemplates: otherTemplates,
            useSelectedTemplateAvailability: useSelectedTemplateAvailability
        )
    }

    var createTemplateSuggestions: [DataStudioBindingSuggestionResponse] {
        sourcePreview?.bindingSuggestions ?? []
    }

    var createTemplatePrimaryCurveSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(kind: "curve_pair")
    }

    var createTemplatePrimaryMetricSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "metric_group",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplatePrimaryMetadataSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "metadata_group",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplatePrimaryStructureSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "structure_rows",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplateSecondaryCurveSuggestions: [DataStudioBindingSuggestionResponse] {
        let primaryID = createTemplatePrimaryCurveSuggestion?.id
        return createTemplateSuggestions.filter { suggestion in
            suggestion.kind == "curve_pair" && suggestion.id != primaryID
        }
    }

    var createTemplateFocusedSuggestion: DataStudioBindingSuggestionResponse? {
        if let hoveredSuggestionID,
           let suggestion = suggestion(for: hoveredSuggestionID)
        {
            return suggestion
        }
        let preferredKinds = ["curve_pair", "metric_group", "metadata_group", "structure_rows"]
        for kind in preferredKinds {
            if let suggestion = selectedSuggestion(for: kind) {
                return suggestion
            }
        }
        return createTemplatePrimaryCurveSuggestion
            ?? createTemplatePrimaryMetricSuggestion
            ?? createTemplatePrimaryMetadataSuggestion
            ?? createTemplatePrimaryStructureSuggestion
            ?? createTemplateSuggestions.first
    }

    var createTemplatePreviewCaption: String? {
        guard let suggestion = createTemplateFocusedSuggestion else {
            return nil
        }
        switch suggestion.kind {
        case "curve_pair":
            return "Previewing Recommended Curve in \(previewLocation(for: suggestion))"
        case "metric_group":
            return "Previewing Recommended Metrics"
        case "metadata_group":
            return "Previewing Recommended Metadata"
        case "structure_rows":
            return "Previewing Detected Structure"
        default:
            return "Previewing Suggested Binding"
        }
    }

    var templateEditorPresentation: DataStudioTemplateEditorPresentation {
        let suggestedCandidateIDs = Set(createTemplateSuggestions.flatMap(\.candidateIDs))
        let advancedCandidates = (sourcePreview?.fieldCandidates ?? [])
            .filter { !suggestedCandidateIDs.contains($0.id) }
            .sorted(by: candidateComparator)

        return DataStudioTemplateEditorPresentation(
            previewCaption: createTemplatePreviewCaption,
            primaryCurveSuggestion: createTemplatePrimaryCurveSuggestion.map {
                suggestionCardPresentation(for: $0, kind: .curve)
            },
            primaryMetricSuggestion: createTemplatePrimaryMetricSuggestion.map {
                suggestionCardPresentation(for: $0, kind: .metric)
            },
            primaryMetadataSuggestion: createTemplatePrimaryMetadataSuggestion.map {
                suggestionCardPresentation(for: $0, kind: .metadata)
            },
            primaryStructureSuggestion: createTemplatePrimaryStructureSuggestion.map {
                suggestionCardPresentation(for: $0, kind: .structure)
            },
            secondaryCurveSuggestions: createTemplateSecondaryCurveSuggestions.map {
                suggestionCardPresentation(for: $0, kind: .curve)
            },
            advancedCandidates: advancedCandidates,
            selectedSummaryItems: selectedTemplateSummaryItems,
            saveTemplateAvailability: createTemplateSaveAvailability,
            saveTemplateAndContinueAvailability: createTemplateSaveAndContinueAvailability
        )
    }

    var selectedTemplateSummaryItems: [DataStudioTemplateSummaryItem] {
        var items: [DataStudioTemplateSummaryItem] = []
        if let value = selectedCurveSummary {
            items.append(.init(id: "curve", title: "Curve", value: value))
        }
        if let value = selectedMetricSummary {
            items.append(.init(id: "metrics", title: "Metrics", value: value))
        }
        if let value = selectedMetadataSummary {
            items.append(.init(id: "metadata", title: "Metadata", value: value))
        }
        if let value = selectedStructureSummary {
            items.append(.init(id: "structure", title: "Structure", value: value))
        }
        return items
    }

    var activePreviewRanges: [DataStudioPreviewRangeResponse] {
        hoveredPreviewRanges.isEmpty ? pinnedPreviewRanges : hoveredPreviewRanges
    }

    var selectedTemplate: DataStudioTemplateResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first(where: { $0.id == selectedTemplateID })
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
            let response = try await client.previewDataStudioSource(.init(inputPath: sampleURL.path))
            sourcePreview = response.preview
            sourceMatches = response.matches
            selectedSuggestionIDs = defaultSuggestionSelection(from: response.preview)
            selectedCandidateIDs = flattenedCandidateSelection(
                fromSuggestionIDs: selectedSuggestionIDs,
                preview: response.preview
            )
            templateDraftLabel = inferGroupName(from: importedSourceURLs)
            templateDraftDescription = "Template created from \(sampleURL.lastPathComponent)."
            selectInitialPreviewContext(from: response.preview)
            hoveredSuggestionID = nil
            hoveredPreviewRanges = []
            syncPinnedPreviewRanges()
            showAdvancedCandidates = false

            let directMatches = response.matches.filter(\.autoSelected)
            if directMatches.count == 1, let match = directMatches.first {
                selectedTemplateID = match.templateID
                await buildWorkbookFromPendingRawFiles(templateID: match.templateID)
            } else {
                selectedTemplateID = response.matches.first?.templateID ?? templates.first?.id
                importFlow = .wizard(step: .resolver)
            }
        } catch {
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
        guard let sourcePreview else {
            errorMessage = "Import a sample source file before creating a parse template."
            return
        }
        if selectedPreviewBlockID == nil {
            selectInitialPreviewContext(from: sourcePreview)
        }
        hoveredSuggestionID = nil
        hoveredPreviewRanges = []
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        showAdvancedCandidates = false
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
        guard let preview = sourcePreview else {
            return
        }
        selectedPreviewSheetName = name
        let blocks = preview.sheets.first(where: { $0.sheetName == name })?.blocks ?? []
        if let selectedPreviewBlockID,
           blocks.contains(where: { $0.id == selectedPreviewBlockID })
        {
            return
        }
        selectedPreviewBlockID = blocks.first?.id
    }

    func selectPreviewBlock(id: String) {
        guard let preview = sourcePreview else {
            return
        }
        for sheet in preview.sheets where sheet.blocks.contains(where: { $0.id == id }) {
            selectedPreviewSheetName = sheet.sheetName
            selectedPreviewBlockID = id
            return
        }
    }

    func setHoveredSuggestion(id: String?) {
        hoveredSuggestionID = id
        guard let id, let suggestion = suggestion(for: id) else {
            hoveredPreviewRanges = []
            return
        }
        hoveredPreviewRanges = suggestion.previewRanges
        focusPreview(onSuggestion: suggestion)
    }

    func toggleSuggestion(id: String) {
        if selectedSuggestionIDs.contains(id) {
            if let suggestion = suggestion(for: id) {
                selectedCandidateIDs.removeAll { suggestion.candidateIDs.contains($0) }
            }
            selectedSuggestionIDs.removeAll { $0 == id }
        } else {
            selectedSuggestionIDs.append(id)
            if let suggestion = suggestion(for: id) {
                for candidateID in suggestion.candidateIDs where !selectedCandidateIDs.contains(candidateID) {
                    selectedCandidateIDs.append(candidateID)
                }
            }
        }
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        if let suggestion = suggestion(for: id) {
            focusPreview(onSuggestion: suggestion)
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
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        if let candidate = sourcePreview?.fieldCandidates.first(where: { $0.id == id }) {
            focusPreview(on: candidate)
        }
    }

    func focusPreview(on candidate: DataStudioFieldCandidateResponse) {
        selectedPreviewSheetName = candidate.sheetName
        if let blockID = candidate.blockID {
            selectedPreviewBlockID = blockID
        } else if let firstBlock = sourcePreview?
            .sheets
            .first(where: { $0.sheetName == candidate.sheetName })?
            .blocks
            .first
        {
            selectedPreviewBlockID = firstBlock.id
        }
    }

    func focusPreview(onSuggestion suggestion: DataStudioBindingSuggestionResponse) {
        selectedPreviewSheetName = suggestion.sheetName
        if let blockID = suggestion.blockID {
            selectedPreviewBlockID = blockID
        }
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
            errorMessage = error.localizedDescription
        }
    }

    func renameSelectedTemplate(to newLabel: String) async {
        guard let client, let selectedTemplate = selectedTemplate else {
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
            errorMessage = error.localizedDescription
        }
    }

    private var createTemplateSaveAvailability: ActionAvailability {
        let trimmedLabel = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            return .disabled("Provide a parse template name before saving it.")
        }
        if selectedCandidateIDs.isEmpty {
            return .disabled("Select at least one suggested or manual field before saving the parse template.")
        }
        return .enabled()
    }

    private var createTemplateSaveAndContinueAvailability: ActionAvailability {
        createTemplateSaveAvailability
    }

    private func candidateComparator(_ lhs: DataStudioFieldCandidateResponse, _ rhs: DataStudioFieldCandidateResponse) -> Bool {
        if lhs.confidence == rhs.confidence {
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        return lhs.confidence > rhs.confidence
    }

    private func suggestionCardPresentation(
        for suggestion: DataStudioBindingSuggestionResponse,
        kind: DataStudioSuggestionCardKind
    ) -> DataStudioSuggestionCardPresentation {
        let values: [String]
        switch kind {
        case .curve:
            let xLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_x" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first ?? "X Column"
            let yLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_y" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first ?? "Y Column"
            values = ["X: \(xLabel)", "Y: \(yLabel)"]
        case .metric:
            values = displayValues(for: suggestion, kinds: ["metric"], includeUnits: false, limit: 4)
        case .metadata:
            values = displayValues(for: suggestion, kinds: ["metadata"], includeUnits: false, limit: 3)
        case .structure:
            values = structureValues(for: suggestion)
        }

        return DataStudioSuggestionCardPresentation(
            id: suggestion.id,
            kind: kind,
            values: values,
            location: previewLocation(for: suggestion)
        )
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
        currentActivity = .creatingTemplate
        errorMessage = nil
        defer { currentActivity = .idle }
        do {
            let template = try await client.createDataStudioTemplate(
                .init(
                    sourcePath: sourceURL.path,
                    label: label,
                    acceptedCandidateIDs: selectedCandidateIDs,
                    templateID: nil,
                    description: templateDraftDescription
                )
            )
            if let index = templates.firstIndex(where: { $0.id == template.id }) {
                templates[index] = template
            } else {
                templates.append(template)
            }
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return template
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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
        sourceMatches = []
        hoveredSuggestionID = nil
        selectedSuggestionIDs = []
        hoveredPreviewRanges = []
        pinnedPreviewRanges = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
        selectedPreviewSheetName = nil
        selectedPreviewBlockID = nil
        showAdvancedCandidates = false
        if case .wizard(step: .createTemplate) = importFlow {
            importFlow = .wizard(step: .resolver)
        }
    }

    private func selectInitialPreviewContext(from preview: DataStudioRawFilePreviewResponse) {
        if let suggestion = preview.bindingSuggestions.first(where: \.defaultSelected) ?? preview.bindingSuggestions.first {
            selectedPreviewSheetName = suggestion.sheetName
            selectedPreviewBlockID = suggestion.blockID
            return
        }
        selectedPreviewSheetName = preview.sheets.first?.sheetName
        selectedPreviewBlockID = preview.sheets.first?.blocks.first?.id
    }

    private func defaultSuggestionSelection(from preview: DataStudioRawFilePreviewResponse) -> [String] {
        let primaryCurve = preferredCreateTemplateSuggestion(in: preview.bindingSuggestions, kind: "curve_pair")
        let preferredBlockID = primaryCurve?.blockID
        var selection: [String] = []
        if let primaryCurve {
            selection.append(primaryCurve.id)
        }

        for kind in ["metric_group", "metadata_group", "structure_rows"] {
            let suggestion = preferredCreateTemplateSuggestion(
                in: preview.bindingSuggestions,
                kind: kind,
                preferredBlockID: preferredBlockID
            )
            if let suggestion, !selection.contains(suggestion.id) {
                selection.append(suggestion.id)
            }
        }

        if selection.isEmpty {
            selection = preview.bindingSuggestions
                .filter(\.defaultSelected)
                .map(\.id)
        }
        return selection
    }

    private func flattenedCandidateSelection(
        fromSuggestionIDs suggestionIDs: [String],
        preview: DataStudioRawFilePreviewResponse?
    ) -> [String] {
        guard let preview else {
            return []
        }
        let selectedSet = Set(suggestionIDs)
        var flattened: [String] = []
        for suggestion in preview.bindingSuggestions where selectedSet.contains(suggestion.id) {
            for candidateID in suggestion.candidateIDs where !flattened.contains(candidateID) {
                flattened.append(candidateID)
            }
        }
        return flattened
    }

    private func reconcileSuggestionSelection() {
        guard let preview = sourcePreview else {
            selectedSuggestionIDs = []
            return
        }
        let selectedSet = Set(selectedCandidateIDs)
        selectedSuggestionIDs = preview.bindingSuggestions
            .filter { !$0.candidateIDs.isEmpty && Set($0.candidateIDs).isSubset(of: selectedSet) }
            .map(\.id)
    }

    private func syncPinnedPreviewRanges() {
        guard let preview = sourcePreview else {
            pinnedPreviewRanges = []
            return
        }
        let selectedSet = Set(selectedSuggestionIDs)
        pinnedPreviewRanges = preview.bindingSuggestions
            .filter { selectedSet.contains($0.id) }
            .flatMap(\.previewRanges)
    }

    private func suggestion(for id: String) -> DataStudioBindingSuggestionResponse? {
        sourcePreview?.bindingSuggestions.first(where: { $0.id == id })
    }

    private func preferredCreateTemplateSuggestion(
        kind: String,
        preferredBlockID: String? = nil
    ) -> DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            in: createTemplateSuggestions,
            kind: kind,
            preferredBlockID: preferredBlockID
        )
    }

    private func preferredCreateTemplateSuggestion(
        in suggestions: [DataStudioBindingSuggestionResponse],
        kind: String,
        preferredBlockID: String? = nil
    ) -> DataStudioBindingSuggestionResponse? {
        let matching = suggestions.filter { $0.kind == kind }
        if let preferredBlockID,
           let preferred = matching.first(where: { $0.blockID == preferredBlockID })
        {
            return preferred
        }
        return matching.first
    }

    private func selectedSuggestion(for kind: String) -> DataStudioBindingSuggestionResponse? {
        let selected = createTemplateSuggestions.filter { suggestion in
            suggestion.kind == kind && selectedSuggestionIDs.contains(suggestion.id)
        }
        if let preferredBlockID = createTemplatePrimaryCurveSuggestion?.blockID,
           let preferred = selected.first(where: { $0.blockID == preferredBlockID })
        {
            return preferred
        }
        return selected.first
    }

    private func candidate(for id: String) -> DataStudioFieldCandidateResponse? {
        sourcePreview?.fieldCandidates.first(where: { $0.id == id })
    }

    private func displayLabel(
        forCandidateID id: String,
        includeUnit: Bool = false
    ) -> String? {
        guard let candidate = candidate(for: id) else {
            return nil
        }
        if includeUnit,
           let unitHint = candidate.unitHint,
           !unitHint.isEmpty,
           !candidate.label.localizedCaseInsensitiveContains(unitHint)
        {
            return "\(candidate.label) (\(unitHint))"
        }
        return candidate.label
    }

    private func selectedLabels(for kind: String, includeUnit: Bool = false) -> [String] {
        let selectedIDs = Set(selectedCandidateIDs)
        var labels: [String] = []
        for candidate in sourcePreview?.fieldCandidates ?? [] where candidate.kind == kind && selectedIDs.contains(candidate.id) {
            let label = displayLabel(forCandidateID: candidate.id, includeUnit: includeUnit) ?? candidate.label
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }

    private func displayValues(
        for suggestion: DataStudioBindingSuggestionResponse,
        kinds: Set<String>,
        includeUnits: Bool,
        limit: Int
    ) -> [String] {
        let candidateIDs = Set(suggestion.candidateIDs)
        let labels = (sourcePreview?.fieldCandidates ?? [])
            .filter { candidateIDs.contains($0.id) && kinds.contains($0.kind) }
            .map { candidate in
                if includeUnits,
                   let unitHint = candidate.unitHint,
                   !unitHint.isEmpty,
                   !candidate.label.localizedCaseInsensitiveContains(unitHint)
                {
                    return "\(candidate.label) (\(unitHint))"
                }
                return candidate.label
            }
        guard labels.count > limit else {
            return labels
        }
        return Array(labels.prefix(limit)) + ["+\(labels.count - limit) more"]
    }

    private var selectedCurveSummary: String? {
        if let suggestion = selectedSuggestion(for: "curve_pair") {
            let xLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_x" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first
            let yLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_y" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first
            if let xLabel, let yLabel {
                return "X = \(xLabel), Y = \(yLabel)"
            }
        }

        let xLabels = selectedLabels(for: "curve_x", includeUnit: true)
        let yLabels = selectedLabels(for: "curve_y", includeUnit: true)
        guard let xLabel = xLabels.first, let yLabel = yLabels.first else {
            return nil
        }
        return "X = \(xLabel), Y = \(yLabel)"
    }

    private var selectedMetricSummary: String? {
        let labels = selectedLabels(for: "metric")
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
    }

    private var selectedMetadataSummary: String? {
        let labels = selectedLabels(for: "metadata")
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
    }

    private var selectedStructureSummary: String? {
        if let suggestion = selectedSuggestion(for: "structure_rows"), !suggestion.summary.isEmpty {
            return suggestion.summary
        }
        let selectedIDs = Set(selectedCandidateIDs)
        var parts: [String] = []
        for candidate in sourcePreview?.fieldCandidates ?? [] where selectedIDs.contains(candidate.id) {
            guard let range = candidate.range else {
                continue
            }
            switch candidate.kind {
            case "header_row":
                parts.append("Header Row \(range.startRow + 1)")
            case "unit_row":
                parts.append("Unit Row \(range.startRow + 1)")
            default:
                break
            }
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: ", ")
    }

    private func structureValues(for suggestion: DataStudioBindingSuggestionResponse) -> [String] {
        let ranges = suggestion.previewRanges.sorted { lhs, rhs in
            if lhs.startRow == rhs.startRow {
                return lhs.role < rhs.role
            }
            return lhs.startRow < rhs.startRow
        }
        var values: [String] = []
        for range in ranges {
            switch range.role {
            case "header_row":
                values.append("Header Row \(range.startRow + 1)")
            case "unit_row":
                values.append("Unit Row \(range.startRow + 1)")
            default:
                continue
            }
        }
        return values
    }

    private func previewLocation(for suggestion: DataStudioBindingSuggestionResponse) -> String {
        guard let preview = sourcePreview else {
            return suggestion.sheetName
        }
        if let blockID = suggestion.blockID {
            for sheet in preview.sheets where sheet.sheetName == suggestion.sheetName {
                if let block = sheet.blocks.first(where: { $0.id == blockID }) {
                    return "\(sheet.sheetName) / \(block.label)"
                }
            }
        }
        return suggestion.sheetName
    }

    private func inferGroupName(from urls: [URL]) -> String {
        guard let first = urls.first else {
            return "DataStudio_Group"
        }
        return first.deletingPathExtension().lastPathComponent
    }
}
