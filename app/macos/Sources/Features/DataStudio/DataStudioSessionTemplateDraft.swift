import Foundation

extension DataStudioSession {
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
            asyncCoordination.sourcePreview.cancel()
            return
        }
        let request = SourceTablePreviewRequest(
            inputPath: sourcePreview.inputPath,
            sheet: sourcePreview.sheet,
            offset: 0,
            limit: sourcePreview.limit,
            encoding: sourcePreview.encoding,
            delimiter: sourcePreview.delimiter,
            segmentID: id
        )
        asyncCoordination.sourcePreview.schedule { [weak self] revision in
            guard let self else { return }
            do {
                let response = try await client.sourceTablePreview(request)
                guard self.asyncCoordination.sourcePreview.isLatest(revision), !Task.isCancelled else {
                    return
                }
                self.sourcePreview = response
                self.configureDraftDefaults(from: response, sampleURL: URL(fileURLWithPath: response.inputPath))
            } catch {
                guard self.asyncCoordination.sourcePreview.isLatest(revision), !Task.isCancelled else {
                    return
                }
                if isUserCancellationError(error) {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setTemplateOutputKind(_ outputKind: String) {
        let previousOutputKind = templateDraftOutputKind
        templateDraftOutputKind = outputKind
        if outputKind == "curve_metrics", previousOutputKind != "curve_metrics" {
            templateDraftComparisonEnabled = false
        } else if outputKind != "curve_metrics" {
            templateDraftComparisonEnabled = true
        }
        if outputKind != "curve_metrics" || !templateDraftComparisonEnabled {
            showAdvancedCandidates = false
        }
        templatePreview = nil
    }

    func setTemplateComparisonEnabled(_ isEnabled: Bool) {
        guard templateDraftComparisonEnabled != isEnabled else {
            return
        }
        templateDraftComparisonEnabled = isEnabled
        if !isEnabled {
            showAdvancedCandidates = false
        }
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
            if templateDraftSampleNameByYColumn[columnName] == nil {
                templateDraftSampleNameByYColumn[columnName] = defaultSampleNameDraftValue()
            }
        } else {
            templateDraftYColumnNames.removeAll { $0 == columnName }
            templateDraftSampleNameByYColumn.removeValue(forKey: columnName)
        }
        templatePreview = nil
    }

    func setDraftSampleName(_ value: String, forYColumn columnName: String) {
        templateDraftSampleNameByYColumn[columnName] = value
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
            if isUserCancellationError(error) {
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
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    var renameSelectedTemplateAvailability: ActionAvailability {
        guard let selectedTemplate else {
            return .disabled("Choose a parse template before renaming.")
        }
        guard !selectedTemplate.builtin else {
            return .disabled("Built-in parse templates cannot be renamed.")
        }
        return .enabled()
    }

    var deleteSelectedTemplateAvailability: ActionAvailability {
        guard let selectedTemplate else {
            return .disabled("Choose a parse template before deleting.")
        }
        guard !selectedTemplate.builtin else {
            return .disabled("Built-in parse templates cannot be deleted.")
        }
        return .enabled()
    }

    var createTemplateSaveAvailability: ActionAvailability {
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
            if templateDraftOutputKind == "curve_metrics",
               templateDraftComparisonEnabled,
               templateDraftMetricColumnNames.isEmpty
            {
                return .disabled("Enable Comparison needs at least one metric column.")
            }
        }
        return .enabled()
    }

    var createTemplateSaveAndContinueAvailability: ActionAvailability {
        createTemplateSaveAvailability
    }

    func createTemplateFromDraft() async -> DataStudioTemplateResponse? {
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
            if isUserCancellationError(error) {
                return nil
            }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func draftTemplateRequest(label: String) -> DataStudioCreateTemplateRequest? {
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
                bindings.append(
                    fieldBinding(
                        idPrefix: "y",
                        role: "curve_y",
                        label: columnName,
                        columnName: columnName,
                        sampleName: templateDraftSampleNameByYColumn[columnName]?.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    )
                )
            }
            if templateDraftComparisonEnabled {
                for columnName in templateDraftMetricColumnNames {
                    bindings.append(
                        fieldBinding(
                            idPrefix: "metric",
                            role: "metric",
                            label: columnName,
                            columnName: columnName,
                            optional: true
                        )
                    )
                }
            }
        }
        return DataStudioCreateTemplateRequest(
            label: label,
            templateID: nil,
            description: templateDraftDescription,
            outputKind: templateDraftOutputKind,
            comparisonEnabled: templateDraftOutputKind == "curve_metrics" ? templateDraftComparisonEnabled : true,
            sourceFormat: .init(
                encoding: sourcePreview.encoding,
                delimiter: sourcePreview.delimiter,
                sheetName: sourcePreview.sheet.displayString
            ),
            segmentPolicy: segmentSelectors.isEmpty ? "single_table" : "series_per_segment",
            segmentSelectors: segmentSelectors,
            fieldBindings: bindings,
            matchConditions: draftMatchConditions(from: sourcePreview)
        )
    }

    func draftSegmentSelectors(from preview: SourceTablePreviewResponse) -> [DataStudioTemplateSegmentSelectorResponse] {
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

    func selector(from segment: SourceTableSegmentResponse) -> DataStudioTemplateSegmentSelectorResponse {
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

    func fieldBinding(
        idPrefix: String,
        role: String,
        label: String,
        columnName: String,
        sampleName: String? = nil,
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
            sampleName: {
                let trimmed = sampleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }(),
            optional: optional
        )
    }

    func defaultSampleNameDraftValue() -> String {
        if let sourcePreview {
            return URL(fileURLWithPath: sourcePreview.inputPath).deletingPathExtension().lastPathComponent
        }
        if let first = importedSourceURLs.first {
            return first.deletingPathExtension().lastPathComponent
        }
        return "Sample"
    }

    func unitHint(for columnName: String) -> String? {
        guard let profile = sourcePreview?.columnProfiles.first(where: { $0.name == columnName }) else {
            return nil
        }
        guard profile.headerPreview.count > 1 else {
            return nil
        }
        return profile.headerPreview[1]
    }

    func configureDraftDefaults(from preview: SourceTablePreviewResponse, sampleURL: URL) {
        templatePreview = nil
        templateDraftLabel = inferGroupName(from: importedSourceURLs.isEmpty ? [sampleURL] : importedSourceURLs)
        templateDraftDescription = "Template created from \(sampleURL.lastPathComponent)."
        templateDraftOutputKind = "curve_metrics"
        templateDraftComparisonEnabled = false
        showAdvancedCandidates = false
        let availableNames = preview.columnHeaders.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        templateDraftXColumnName = preview.detectedXLabel ?? preview.candidateRoles.x.first ?? availableNames.first
        let xName = templateDraftXColumnName
        let recommendedY = preview.candidateRoles.y.filter { $0 != xName }
        templateDraftYColumnNames = Array(recommendedY.prefix(3))
        if templateDraftYColumnNames.isEmpty {
            templateDraftYColumnNames = Array(availableNames.filter { $0 != xName }.prefix(1))
        }
        let defaultSampleName = sampleURL.deletingPathExtension().lastPathComponent
        templateDraftSampleNameByYColumn = Dictionary(
            uniqueKeysWithValues: templateDraftYColumnNames.map { ($0, defaultSampleName) }
        )
        templateDraftMetricColumnNames = Array(preview.candidateRoles.metric.prefix(4))
    }

    func rankedRecommendedMatches(
        _ matches: [DataStudioTemplateMatchResponse]? = nil,
        availableTemplates: [DataStudioTemplateResponse]
    ) -> [DataStudioTemplateMatchResponse] {
        let source = matches ?? recommendedTemplateMatches
        let availableTemplateIDs = Set(availableTemplates.map(\.id))
        var byTemplateID: [String: DataStudioTemplateMatchResponse] = [:]
        for match in source where availableTemplateIDs.contains(match.templateID) {
            if let current = byTemplateID[match.templateID], current.confidence >= match.confidence {
                continue
            }
            byTemplateID[match.templateID] = match
        }
        return byTemplateID.values.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    func draftMatchConditions(from preview: SourceTablePreviewResponse) -> [DataStudioTemplateConditionResponse] {
        let selectedSegment = preview.segments.first(where: { $0.id == selectedPreviewSegmentID })
        let sheetHint = selectedSegment?.sheetName ?? preview.sheet.displayString

        var textHints: [String] = []
        if let label = selectedSegment?.resultLabel, !label.isEmpty {
            textHints.append(label)
        }
        if let x = templateDraftXColumnName, !x.isEmpty {
            textHints.append(x)
        }
        textHints.append(contentsOf: templateDraftYColumnNames.prefix(2))
        if templateDraftComparisonEnabled {
            textHints.append(contentsOf: templateDraftMetricColumnNames.prefix(1))
        }

        var dedupedTextHints: [String] = []
        for hint in textHints {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let lowered = trimmed.lowercased()
            if !dedupedTextHints.contains(where: { $0.lowercased() == lowered }) {
                dedupedTextHints.append(trimmed)
            }
        }

        let fieldKinds: [String]
        let minimumScore: Double
        switch templateDraftOutputKind {
        case "metric_table":
            fieldKinds = ["metric"]
            minimumScore = 0.25
        case "matrix_heatmap":
            fieldKinds = ["metric", "curve_x", "curve_y"]
            minimumScore = 0.25
        default:
            fieldKinds = templateDraftComparisonEnabled ? ["curve_x", "curve_y", "metric"] : ["curve_x", "curve_y"]
            minimumScore = 0.3
        }

        if sheetHint.isEmpty, dedupedTextHints.isEmpty, fieldKinds.isEmpty {
            return []
        }

        return [
            DataStudioTemplateConditionResponse(
                sheetNameContains: sheetHint.isEmpty ? [] : [sheetHint],
                textContains: dedupedTextHints,
                fieldKinds: fieldKinds,
                minimumScore: minimumScore
            ),
        ]
    }
}
