import Foundation

extension DataStudioSession {
    var exportAvailability: ActionAvailability {
        if currentActivity == .exportingComparison {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard comparisonSet != nil else {
            return .disabled("Import workbook groups before exporting.")
        }
        guard !selectedExportRecipeIDs.isEmpty else {
            return .disabled("Choose at least one figure family before exporting.")
        }
        return .enabled()
    }

    var revealOutputAvailability: ActionAvailability {
        guard focusedWorkbook != nil || comparisonExportDestinationURL != nil else {
            return .disabled("Export or focus a workbook first.")
        }
        return .enabled()
    }

    var selectedComparisonFigure: DataStudioExportFigureItem? {
        guard let selectedComparisonFigureID else {
            return comparisonFigureItems.first
        }
        return comparisonFigureItems.first(where: { $0.id == selectedComparisonFigureID }) ?? comparisonFigureItems.first
    }

    var latestComparisonWorkbookURL: URL? {
        guard let path = comparisonExportResponse?.comparisonSet.comparisonWorkbookPath else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    var figureFamilies: [DataStudioFigureFamilyItem] {
        guard let comparisonSet else {
            return []
        }
        var grouped: [String: [DataStudioComparisonRecipeResponse]] = [:]
        var titles: [String: String] = [:]
        var metricIDs: [String: String?] = [:]
        for recipe in comparisonSet.recipes {
            let familyID: String
            let title: String
            if let metricID = recipe.metricID, !metricID.isEmpty {
                familyID = normalizeFigureFamilyID(metricID)
                title = metricID
                metricIDs[familyID] = metricID
            } else {
                familyID = "representative_curve"
                title = "Representative Curve"
                metricIDs[familyID] = nil
            }
            grouped[familyID, default: []].append(recipe)
            titles[familyID] = title
        }
        return grouped.keys.sorted(by: figureFamilyComparator).map { familyID in
            DataStudioFigureFamilyItem(
                id: familyID,
                title: titles[familyID] ?? familyID,
                metricID: metricIDs[familyID] ?? nil,
                recipes: grouped[familyID, default: []]
            )
        }
    }

    var currentFigureFamily: DataStudioFigureFamilyItem? {
        guard !figureFamilies.isEmpty else {
            return nil
        }
        if let selectedFigureFamilyID,
           let match = figureFamilies.first(where: { $0.id == selectedFigureFamilyID })
        {
            return match
        }
        return figureFamilies.first
    }

    var availableFigureTemplates: [DataStudioFigureTemplateItem] {
        guard let family = currentFigureFamily else {
            return []
        }
        var seen: Set<String> = []
        return family.recipes
            .filter(\.supported)
            .compactMap { recipe in
                guard seen.insert(recipe.templateID).inserted else {
                    return nil
                }
                return DataStudioFigureTemplateItem(
                    id: recipe.templateID,
                    label: plotSession.templateLabel(for: recipe.templateID),
                    recipeID: recipe.id
                )
            }
    }

    var currentFigureTemplateID: String? {
        currentRecipe?.templateID
    }

    var currentRecipe: DataStudioComparisonRecipeResponse? {
        guard let family = currentFigureFamily else {
            return nil
        }
        let selectedTemplateID = selectedTemplateID(forFamilyID: family.id)
        if let selectedTemplateID,
           let exact = family.recipes.first(where: { $0.templateID == selectedTemplateID && $0.supported })
        {
            return exact
        }
        return preferredRecipe(in: family)
    }

    var currentRecipeLabel: String {
        currentRecipe?.label ?? "No figure"
    }

    var comparisonStatusText: String {
        if let comparisonSet {
            let workbookName = URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath).lastPathComponent
            if isPreviewStale {
                return "\(includedGroups.count) group(s) · \(currentRecipeLabel) · showing last successful preview from \(workbookName)"
            }
            return "\(includedGroups.count) group(s) · \(currentRecipeLabel) · \(workbookName)"
        }
        if !workbooks.isEmpty {
            return "\(includedGroups.count) group(s) in compare"
        }
        return "No workbook groups loaded"
    }

    var previewStatusSymbol: String {
        if currentActivity == .previewingComparison {
            return "arrow.triangle.2.circlepath"
        }
        if isPreviewStale {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle"
    }

    var focusTitle: String {
        if let focusedWorkbook {
            return displayName(for: focusedWorkbook)
        }
        return "Data Studio"
    }

    var selectedSourceFilename: String? {
        focusedWorkbook?.workbookURL.lastPathComponent
    }

    var canExportComparison: Bool {
        comparisonSet != nil && !selectedExportRecipeIDs.isEmpty
    }

    var showsCompactEmptyInspector: Bool {
        orderedGroups.isEmpty
    }

    var showsInspectorActions: Bool {
        !showsCompactEmptyInspector
    }

    var canOpenCurrentFigureInPlot: Bool {
        currentFigureSourceURL != nil && currentFigureTemplateID != nil
    }

    var currentFigureSourceURL: URL? {
        if let comparisonSet, currentRecipe != nil {
            return URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath)
        }
        return plotSession.selectedFileURL ?? focusedWorkbook?.workbookURL
    }

    var currentFigureSheet: SheetValue {
        if let currentRecipe {
            return .name(currentRecipe.sheetName)
        }
        if plotSession.selectedFileURL != nil {
            return plotSession.selectedSheet
        }
        return .name(focusedWorkbook?.response.preferredSheet ?? "Representative_Curve")
    }

    var currentFigureRenderOptions: RenderOptionsPayload {
        if let currentRecipe,
           let options = preferredRenderOptions(
               forFamilyID: currentFigureFamily?.id,
               templateID: currentRecipe.templateID
           )
        {
            return options
        }
        return plotSession.renderOptions
    }

    func selectFigureFamily(id: String) {
        let previousSnapshot = undoSnapshot()
        cacheCurrentFigureOptions()
        selectedFigureFamilyID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigureHandlingFailure() }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Figure Family")
    }

    func selectFigureTemplate(id: String) {
        guard let family = currentFigureFamily else {
            return
        }
        let previousSnapshot = undoSnapshot()
        cacheCurrentFigureOptions()
        setFigurePreference(familyID: family.id, selectedTemplateID: id)
        selectedFigureTemplateID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigureHandlingFailure() }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Figure Template")
    }

    func openCurrentFigureInPlot() {
        guard
            let inputURL = currentFigureSourceURL,
            let templateID = currentFigureTemplateID
        else {
            return
        }
        openInPlotHandler?(inputURL, currentFigureSheet, templateID, currentFigureRenderOptions)
    }

    func revealFocusedWorkbook() {
        guard let focusedWorkbook else {
            return
        }
        do {
            try WorkspaceBridge.reveal([focusedWorkbook.workbookURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFocusedWorkbook() {
        guard let focusedWorkbook else {
            return
        }
        do {
            try WorkspaceBridge.open(focusedWorkbook.workbookURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        do {
            if let comparisonExportDestinationURL {
                try WorkspaceBridge.reveal([comparisonExportDestinationURL])
            } else if let focusedWorkbook {
                try WorkspaceBridge.reveal([focusedWorkbook.workbookURL])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLatestComparisonWorkbook() {
        guard let latestComparisonWorkbookURL else {
            return
        }
        do {
            try WorkspaceBridge.open(latestComparisonWorkbookURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSelectedComparisonFigure() {
        guard let selectedComparisonFigure else {
            return
        }
        do {
            try WorkspaceBridge.open(selectedComparisonFigure.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFilteredWorkbook(id: String) {
        guard let item = comparisonFilteredWorkbookItems.first(where: { $0.id == id }) else {
            return
        }
        do {
            try WorkspaceBridge.open(item.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectComparisonFigure(id: String) {
        selectedComparisonFigureID = id
    }

    func exportComparisonBundle() async {
        guard let client, comparisonSet != nil else {
            errorMessage = "Import at least one workbook group before exporting a Data Studio figure bundle."
            return
        }
        let recipeIDs = selectedExportRecipeIDs
        guard !recipeIDs.isEmpty else {
            errorMessage = "Choose at least one figure family before exporting the Data Studio bundle."
            return
        }
        guard let directoryURL = chooseDirectory(
            "Export Data Studio Bundle",
            "Choose a destination folder for the comparison workbook, filtered workbooks, and figure outputs."
        ) else {
            return
        }
        guard let figureFormat = chooseComparisonFigureFormat(
            "Comparison Figure Format",
            "Choose whether the exported Data Studio figures should stay as editable PDF or convert to 300 dpi TIFF."
        ) else {
            return
        }

        cacheCurrentFigureOptions()
        isBusy = true
        currentActivity = .exportingComparison
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
        }

        do {
            let response = try await client.exportDataStudioComparison(
                .init(
                    workbookPaths: orderedWorkbooks.map { $0.response.workbookPath },
                    outputDir: directoryURL.path,
                    groupStates: requestGroupStates,
                    specimenStates: requestSpecimenStates,
                    selectedRecipeIDs: recipeIDs,
                    figureOptionsByRecipeID: exportFigureOptionsByRecipeID()
                )
            )
            comparisonExportResponse = response
            comparisonSet = response.comparisonSet
            comparisonFilteredWorkbookItems = response.filteredWorkbooks.map { output in
                DataStudioExportFilteredWorkbookItem(
                    id: output.path,
                    response: output,
                    url: URL(fileURLWithPath: output.path)
                )
            }
            let sourceURLs = response.figureOutputs.map { URL(fileURLWithPath: $0.path) }
            let materialized = try materializeComparisonOutputs(sourceURLs, figureFormat)
            comparisonFigureItems = zip(response.figureOutputs, materialized).map { output, url in
                DataStudioExportFigureItem(id: output.path, response: output, url: url)
            }
            selectedComparisonFigureID = comparisonFigureItems.first?.id
            comparisonExportDestinationURL = directoryURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func normalizeSessionPayload() async -> DataStudioSessionResponse? {
        guard let client else {
            return nil
        }
        cacheCurrentFigureOptions()
        let payload: [String: JSONValue] = [
            "version": .number(1),
            "selected_template_id": selectedTemplateID.map(JSONValue.string) ?? .null,
            "selected_workbook_id": focusedWorkbook.map { .string($0.response.workbookID) } ?? .null,
            "primary_workbook_id": focusedWorkbook.map { .string($0.response.workbookID) } ?? .null,
            "selected_recipe_id": currentRecipe.map { .string($0.id) } ?? .null,
            "workbook_paths": .array(orderedWorkbooks.map { .string($0.response.workbookPath) }),
            "comparison_recipe_ids": .array(selectedExportRecipeIDs.map(JSONValue.string)),
            "selected_figure_family_id": selectedFigureFamilyID.map(JSONValue.string) ?? .null,
            "selected_figure_template_id": selectedFigureTemplateID.map(JSONValue.string) ?? .null,
            "group_states": .array(requestGroupStates.map(jsonValue(for:))),
            "specimen_states": .array(requestSpecimenStates.map(jsonValue(for:))),
            "figure_preferences": .array(
                figurePreferences
                    .sorted { $0.familyID.localizedCaseInsensitiveCompare($1.familyID) == .orderedAscending }
                    .map(jsonValue(for:))
            ),
            "imported_paths": .array(importedSourceURLs.map { .string($0.path) }),
            "template_draft_path": importedSourceURLs.first.map { .string($0.path) } ?? .null,
        ]
        do {
            return try await client.normalizeDataStudioSession(.init(payload: payload))
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func restoreSession(from payload: DataStudioSessionResponse) async {
        resetContentState()
        selectedTemplateID = payload.selectedTemplateID
        selectedFigureFamilyID = payload.selectedFigureFamilyID
        selectedFigureTemplateID = migrateLegacyFigureTemplateID(payload.selectedFigureTemplateID)
        selectedRecipeID = migrateLegacyComparisonRecipeID(payload.selectedRecipeID)
        importedSourceURLs = payload.importedPaths.map(URL.init(fileURLWithPath:))
        figurePreferences = payload.figurePreferences.map(migrateLegacyFigurePreference(_:))

        if !payload.workbookPaths.isEmpty {
            pendingImportDisposition = .addToCurrentSession
            await handleImportedWorkbooks(payload.workbookPaths.map(URL.init(fileURLWithPath:)), refreshContext: false)
        }

        if !payload.groupStates.isEmpty {
            applyRestoredGroupStates(payload.groupStates)
        } else {
            reindexGroupStates()
        }
        applyRestoredSpecimenStates(payload.specimenStates)

        focusedWorkbookPath = resolveRestoredWorkbookPath(
            selectedWorkbookID: payload.selectedWorkbookID,
            primaryWorkbookID: payload.primaryWorkbookID
        )

        await rebuildComparisonContext(refreshWorkbookPreviews: true)
    }

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
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions
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
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions
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
                optionsByTemplate: existing.optionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: migratedTemplateID,
                    optionsByTemplate: [:]
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
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: templateID,
                optionsByTemplate: optionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: templateID,
                    optionsByTemplate: optionsByTemplate
                )
            )
        }
        selectedFigureTemplateID = templateID
    }

    func cacheCurrentFigureOptions() {
        storeCurrentFigureOptions(plotSession.renderOptions)
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
        return DataStudioFigurePreferencePayload(
            familyID: preference.familyID,
            selectedTemplateID: migrateLegacyFigureTemplateID(preference.selectedTemplateID),
            optionsByTemplate: migratedOptions
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
}
