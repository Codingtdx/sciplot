import Foundation

extension DataStudioSession {
    var requestGroupStates: [DataStudioGroupStatePayload] {
        orderedWorkbooks.enumerated().map { index, workbook in
            let existing = groupState(for: workbook.response.workbookPath)
            return DataStudioGroupStatePayload(
                workbookPath: workbook.response.workbookPath,
                displayName: normalizedDisplayName(for: workbook, override: existing?.displayName),
                includeInCompare: existing?.includeInCompare ?? true,
                sortOrder: index
            )
        }
    }

    var requestSpecimenStates: [DataStudioSpecimenStatePayload] {
        specimenStatesByWorkbookPath
            .keys
            .sorted()
            .flatMap { workbookPath in
                (specimenStatesByWorkbookPath[workbookPath] ?? []).sorted { lhs, rhs in
                    lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
                }
            }
    }

    var selectedExportRecipeIDs: [String] {
        figureFamilies.compactMap { family in
            recipe(forFamilyID: family.id)?.id
        }
    }

    func rebuildComparisonContext(
        refreshWorkbookPreviews: Bool = false,
        revision: Int? = nil
    ) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.comparisonRefresh.beginNow()
        cacheCurrentFigureOptions()
        guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
            return
        }
        let workbookPaths = orderedWorkbooks.map { $0.response.workbookPath }
        guard !workbookPaths.isEmpty else {
            clearComparisonContext()
            return
        }
        guard requestGroupStates.contains(where: \.includeInCompare) else {
            clearComparisonContext()
            return
        }

        currentActivity = .previewingComparison
        errorMessage = nil
        previewWarning = nil
        defer { currentActivity = .idle }
        do {
            if refreshWorkbookPreviews {
                await refreshFocusedWorkbookPreviewIfNeeded()
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
            }
            let previousComparisonSet = comparisonSet
            let previousCacheKey = comparisonContextCacheKey
            let previousMaterializedAt = comparisonContextMaterializedAt
            let previousSelectedFigureFamilyID = selectedFigureFamilyID
            let previousSelectedFigureTemplateID = selectedFigureTemplateID
            let previousSelectedRecipeID = selectedRecipeID

            let response = try await client.comparisonContextDataStudio(
                .init(
                    workbookPaths: workbookPaths,
                    groupStates: requestGroupStates,
                    specimenStates: requestSpecimenStates
                )
            )
            guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                return
            }
            comparisonSet = response.comparisonSet
            comparisonContextCacheKey = response.cacheKey
            comparisonContextMaterializedAt = response.materializedAt
            syncFigureSelection(preferredRecipeID: previousSelectedRecipeID)
            do {
                try await refreshDisplayedFigure()
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
                previewWarning = nil
                isPreviewStale = false
            } catch {
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
                comparisonSet = previousComparisonSet
                comparisonContextCacheKey = previousCacheKey
                comparisonContextMaterializedAt = previousMaterializedAt
                selectedFigureFamilyID = previousSelectedFigureFamilyID
                selectedFigureTemplateID = previousSelectedFigureTemplateID
                selectedRecipeID = previousSelectedRecipeID
                syncFigureSelection(preferredRecipeID: previousSelectedRecipeID)
                if previousComparisonSet != nil {
                    await restoreCommittedComparisonFigure()
                    previewWarning = "Refresh failed, showing last successful preview."
                    isPreviewStale = true
                } else {
                    clearComparisonContext()
                    previewWarning = error.localizedDescription
                    isPreviewStale = false
                }
            }
        } catch {
            guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                return
            }
            if comparisonSet != nil {
                previewWarning = "Refresh failed, showing last successful preview."
                isPreviewStale = true
            } else {
                previewWarning = error.localizedDescription
            }
        }
    }

    func refreshDisplayedFigure() async throws {
        guard let comparisonSet, let currentRecipe else {
            return
        }
        let preferredOptions = preferredRenderOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        let preferredFitOptions = preferredFitOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions,
            preferredFitOptions: preferredFitOptions
        )
        await plotSession.finishLoadingStagedExternalFigure(
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions,
            expectedInputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            expectedSheet: .name(currentRecipe.sheetName)
        )
        if let plotError = plotSession.errorMessage, !plotError.isEmpty {
            if shouldSuppressPlotError(plotError, comparisonWorkbookPath: comparisonSet.comparisonWorkbookPath) {
                plotSession.errorMessage = nil
            } else {
                throw NSError(
                    domain: "DataStudioPreview",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: plotError]
                )
            }
        }
        plotSession.errorMessage = nil
        errorMessage = nil
    }

    func refreshDisplayedFigureHandlingFailure() async {
        do {
            try await refreshDisplayedFigure()
            previewWarning = nil
            isPreviewStale = false
        } catch {
            if comparisonSet != nil {
                previewWarning = "Refresh failed, showing last successful preview."
                isPreviewStale = true
            } else {
                previewWarning = error.localizedDescription
            }
        }
    }

    func stageCurrentFigurePreview() {
        guard let comparisonSet, let currentRecipe else {
            plotSession.clearPreviewContext(preserveRenderOptions: true)
            return
        }
        let preferredOptions = preferredRenderOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        let preferredFitOptions = preferredFitOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions,
            preferredFitOptions: preferredFitOptions
        )
    }

    func restoreCommittedComparisonFigure() async {
        guard comparisonSet != nil else {
            return
        }
        stageCurrentFigurePreview()
        try? await refreshDisplayedFigure()
    }

    func scheduleComparisonContextRebuild() {
        asyncCoordination.comparisonRefresh.schedule(delayNanoseconds: comparisonRefreshDelayNanoseconds) { [weak self] revision in
            guard let self else {
                return
            }
            await self.rebuildComparisonContext(revision: revision)
        }
    }

    func clearComparisonContext() {
        comparisonSet = nil
        comparisonContextCacheKey = nil
        comparisonContextMaterializedAt = nil
        comparisonExportResponse = nil
        comparisonFigureItems = []
        comparisonFilteredWorkbookItems = []
        selectedComparisonFigureID = nil
        comparisonExportDestinationURL = nil
        previewWarning = nil
        isPreviewStale = false
        plotSession.clearPreviewContext(preserveRenderOptions: true)
    }

    func syncFigureSelection(preferredRecipeID: String? = nil) {
        guard !figureFamilies.isEmpty else {
            selectedFigureFamilyID = nil
            selectedFigureTemplateID = nil
            selectedRecipeID = nil
            return
        }

        let restoredFamily = figureFamilies.first(where: { $0.id == selectedFigureFamilyID })
        let recipeFromPreference = preferredRecipeID.flatMap { recipeID in
            comparisonSet?.recipes.first(where: { $0.id == recipeID })
        }
        let family = restoredFamily
            ?? recipeFromPreference.flatMap { recipe in
                familyFor(recipe: recipe)
            }
            ?? figureFamilies.first

        selectedFigureFamilyID = family?.id

        if let family {
            let selectedTemplate = selectedTemplateID(forFamilyID: family.id)
            let supportedTemplates = Set(family.recipes.filter(\.supported).map(\.templateID))
            if let selectedTemplate, supportedTemplates.contains(selectedTemplate) {
                selectedFigureTemplateID = selectedTemplate
            } else {
                let fallbackRecipe = preferredRecipe(in: family)
                selectedFigureTemplateID = fallbackRecipe?.templateID
                setFigurePreference(familyID: family.id, selectedTemplateID: fallbackRecipe?.templateID)
            }
        } else {
            selectedFigureTemplateID = nil
        }
        selectedRecipeID = currentRecipe?.id
        plotSession.selectedTemplateID = currentRecipe?.templateID ?? selectedFigureTemplateID
    }

    func familyFor(recipe: DataStudioComparisonRecipeResponse) -> DataStudioFigureFamilyItem? {
        if let metricID = recipe.metricID, !metricID.isEmpty {
            return figureFamilies.first(where: { $0.id == normalizeFigureFamilyID(metricID) })
        }
        return figureFamilies.first(where: { $0.id == "representative_curve" })
    }

    func recipe(forFamilyID familyID: String) -> DataStudioComparisonRecipeResponse? {
        guard let family = figureFamilies.first(where: { $0.id == familyID }) else {
            return nil
        }
        let selectedTemplateID = selectedTemplateID(forFamilyID: family.id)
        if let selectedTemplateID,
           let recipe = family.recipes.first(where: { $0.templateID == selectedTemplateID && $0.supported })
        {
            return recipe
        }
        return preferredRecipe(in: family)
    }

    func preferredRecipe(in family: DataStudioFigureFamilyItem) -> DataStudioComparisonRecipeResponse? {
        let preferredTemplateOrder = [
            "curve",
            "point_line",
            "scatter",
            "box_strip",
            "point_error",
            "box",
            "bar",
            "violin",
        ]
        let supported = family.recipes.filter(\.supported)
        if let matched = preferredTemplateOrder.lazy.compactMap({ templateID in
            supported.first(where: { $0.templateID == templateID })
        }).first {
            return matched
        }
        return supported.first
    }

    func selectedTemplateID(forFamilyID familyID: String) -> String? {
        if let preference = figurePreferences.first(where: { $0.familyID == familyID }),
           let selected = migrateLegacyFigureTemplateID(preference.selectedTemplateID)
        {
            return selected
        }
        if selectedFigureFamilyID == familyID {
            return migrateLegacyFigureTemplateID(selectedFigureTemplateID)
        }
        return nil
    }

    func setFigurePreference(familyID: String, selectedTemplateID: String?) {
        let migratedTemplateID = migrateLegacyFigureTemplateID(selectedTemplateID)
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            let existing = figurePreferences[index]
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: migratedTemplateID,
                optionsByTemplate: existing.optionsByTemplate,
                fitOptionsByTemplate: existing.fitOptionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: migratedTemplateID,
                    optionsByTemplate: [:],
                    fitOptionsByTemplate: [:]
                )
            )
        }
    }

    func storeCurrentFigureOptions(_ options: RenderOptionsPayload) {
        guard let familyID = currentFigureFamily?.id else {
            return
        }
        let templateID = plotSession.selectedTemplateID ?? selectedFigureTemplateID
        guard let templateID else {
            return
        }
        let existing = figurePreferences.first(where: { $0.familyID == familyID })
        var optionsByTemplate = existing?.optionsByTemplate ?? [:]
        optionsByTemplate[templateID] = options
        let fitOptionsByTemplate = existing?.fitOptionsByTemplate ?? [:]
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: templateID,
                optionsByTemplate: optionsByTemplate,
                fitOptionsByTemplate: fitOptionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: templateID,
                    optionsByTemplate: optionsByTemplate,
                    fitOptionsByTemplate: fitOptionsByTemplate
                )
            )
        }
        selectedFigureTemplateID = templateID
    }

    func storeCurrentFigureFitOptions(_ options: FitOptionsPayload) {
        guard let familyID = currentFigureFamily?.id else {
            return
        }
        let templateID = plotSession.selectedTemplateID ?? selectedFigureTemplateID
        guard let templateID else {
            return
        }
        let existing = figurePreferences.first(where: { $0.familyID == familyID })
        let optionsByTemplate = existing?.optionsByTemplate ?? [:]
        var fitOptionsByTemplate = existing?.fitOptionsByTemplate ?? [:]
        fitOptionsByTemplate[templateID] = options
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: templateID,
                optionsByTemplate: optionsByTemplate,
                fitOptionsByTemplate: fitOptionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: templateID,
                    optionsByTemplate: optionsByTemplate,
                    fitOptionsByTemplate: fitOptionsByTemplate
                )
            )
        }
        selectedFigureTemplateID = templateID
    }

    func cacheCurrentFigureOptions() {
        storeCurrentFigureOptions(plotSession.renderOptions)
        storeCurrentFigureFitOptions(plotSession.fitOptions)
    }

    func preferredRenderOptions(
        forFamilyID familyID: String?,
        templateID: String
    ) -> RenderOptionsPayload? {
        guard let familyID else {
            return nil
        }
        return figurePreferences
            .first(where: { $0.familyID == familyID })?
            .optionsByTemplate[templateID]
    }

    func preferredFitOptions(
        forFamilyID familyID: String?,
        templateID: String
    ) -> FitOptionsPayload? {
        guard let familyID else {
            return nil
        }
        return figurePreferences
            .first(where: { $0.familyID == familyID })?
            .fitOptionsByTemplate[templateID]
    }

    func exportFigureOptionsByRecipeID() -> [String: RenderOptionsPayload] {
        var result: [String: RenderOptionsPayload] = [:]
        for family in figureFamilies {
            guard let recipe = recipe(forFamilyID: family.id) else {
                continue
            }
            if let options = preferredRenderOptions(forFamilyID: family.id, templateID: recipe.templateID) {
                result[recipe.id] = options
            } else if family.id == currentFigureFamily?.id {
                result[recipe.id] = plotSession.renderOptions
            }
        }
        return result
    }

    func exportFigureFitOptionsByRecipeID() -> [String: FitOptionsPayload] {
        var result: [String: FitOptionsPayload] = [:]
        for family in figureFamilies {
            guard let recipe = recipe(forFamilyID: family.id) else {
                continue
            }
            if let options = preferredFitOptions(forFamilyID: family.id, templateID: recipe.templateID) {
                result[recipe.id] = options
            } else if family.id == currentFigureFamily?.id {
                result[recipe.id] = plotSession.fitOptions
            }
        }
        return result
    }

    func shouldSuppressPlotError(_ message: String, comparisonWorkbookPath: String) -> Bool {
        let lowered = message.lowercased()
        let comparisonName = URL(fileURLWithPath: comparisonWorkbookPath).lastPathComponent.lowercased()
        return lowered.contains(comparisonName)
            && lowered.contains("representative curve group")
            && lowered.contains("representative_curve")
    }

    func normalizeFigureFamilyID(_ metricID: String) -> String {
        metricID
            .lowercased()
            .replacingOccurrences(of: " at ", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    func figureFamilyComparator(_ lhs: String, _ rhs: String) -> Bool {
        let lhsPriority = figureFamilyPriority(lhs)
        let rhsPriority = figureFamilyPriority(rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    func figureFamilyPriority(_ familyID: String) -> Int {
        if familyID == "representative_curve" {
            return 0
        }
        if familyID.contains("strength") {
            return 1
        }
        if familyID.contains("modulus") {
            return 2
        }
        if familyID.contains("elongation") {
            return 3
        }
        return 9
    }

    func migrateLegacyFigureTemplateID(_ templateID: String?) -> String? {
        switch templateID {
        case "grouped_bar_error", "grouped_bar_compare":
            return "bar"
        default:
            return templateID
        }
    }

    func migrateLegacyComparisonRecipeID(_ recipeID: String?) -> String? {
        guard let recipeID else {
            return nil
        }
        if recipeID.hasSuffix("_grouped_bar_error") {
            return String(recipeID.dropLast("_grouped_bar_error".count)) + "_bar"
        }
        if recipeID.hasSuffix("_grouped_bar_compare") {
            return String(recipeID.dropLast("_grouped_bar_compare".count)) + "_bar"
        }
        return recipeID
    }

    func migrateLegacyFigurePreference(_ preference: DataStudioFigurePreferencePayload) -> DataStudioFigurePreferencePayload {
        var migratedOptions: [String: RenderOptionsPayload] = [:]
        for (templateID, options) in preference.optionsByTemplate {
            let migratedTemplateID = migrateLegacyFigureTemplateID(templateID) ?? templateID
            migratedOptions[migratedTemplateID] = options
        }
        var migratedFitOptions: [String: FitOptionsPayload] = [:]
        for (templateID, options) in preference.fitOptionsByTemplate {
            let migratedTemplateID = migrateLegacyFigureTemplateID(templateID) ?? templateID
            migratedFitOptions[migratedTemplateID] = options
        }
        return DataStudioFigurePreferencePayload(
            familyID: preference.familyID,
            selectedTemplateID: migrateLegacyFigureTemplateID(preference.selectedTemplateID),
            optionsByTemplate: migratedOptions,
            fitOptionsByTemplate: migratedFitOptions
        )
    }

    func jsonValue(for state: DataStudioGroupStatePayload) -> JSONValue {
        .object(
            [
                "workbook_path": .string(state.workbookPath),
                "display_name": .string(state.displayName),
                "include_in_compare": .bool(state.includeInCompare),
                "sort_order": .number(Double(state.sortOrder)),
            ]
        )
    }

    func jsonValue(for state: DataStudioSpecimenStatePayload) -> JSONValue {
        .object(
            [
                "workbook_path": .string(state.workbookPath),
                "specimen_id": .string(state.specimenId),
                "included": .bool(state.included),
                "selected_as_representative": .bool(state.selectedAsRepresentative),
            ]
        )
    }

    func jsonValue(for preference: DataStudioFigurePreferencePayload) -> JSONValue {
        .object(
            [
                "family_id": .string(preference.familyID),
                "selected_template_id": preference.selectedTemplateID.map(JSONValue.string) ?? .null,
                "options_by_template": .object(
                    preference.optionsByTemplate.mapValues { options in
                        jsonValue(for: options)
                    }
                ),
                "fit_options_by_template": .object(
                    preference.fitOptionsByTemplate.mapValues { options in
                        jsonValue(for: options)
                    }
                ),
            ]
        )
    }

    func jsonValue(for options: RenderOptionsPayload) -> JSONValue {
        .object(
            [
                "size": options.size.map(JSONValue.string) ?? .null,
                "xscale": options.xscale.map(JSONValue.string) ?? .null,
                "yscale": options.yscale.map(JSONValue.string) ?? .null,
                "reverse_x": .bool(options.reverseX),
                "x_min": options.xMin.map(JSONValue.number) ?? .null,
                "x_max": options.xMax.map(JSONValue.number) ?? .null,
                "y_min": options.yMin.map(JSONValue.number) ?? .null,
                "y_max": options.yMax.map(JSONValue.number) ?? .null,
            ]
        )
    }

    func jsonValue(for options: FitOptionsPayload) -> JSONValue {
        .object(
            [
                "enabled": .bool(options.enabled),
                "model_id": .string(options.modelID),
            ]
        )
    }
}
