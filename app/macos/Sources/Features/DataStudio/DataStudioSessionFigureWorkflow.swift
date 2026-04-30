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
                return "\(includedGroups.count) groups · \(currentRecipeLabel) · last preview: \(workbookName)"
            }
            return "\(includedGroups.count) groups · \(currentRecipeLabel) · \(workbookName)"
        }
        if !workbooks.isEmpty {
            return "\(includedGroups.count) groups in compare"
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

    var currentFigureFitOptions: FitOptionsPayload {
        if let currentRecipe,
           let options = preferredFitOptions(
               forFamilyID: currentFigureFamily?.id,
               templateID: currentRecipe.templateID
           )
        {
            return options
        }
        return plotSession.fitOptions
    }

    var currentFigureFitAvailability: ActionAvailability {
        guard let recipe = currentRecipe else {
            return .disabled("Choose a figure before fitting.")
        }
        let supportedTemplates = Set(["curve", "point_line", "scatter"])
        guard supportedTemplates.contains(recipe.templateID) else {
            return .disabled("Fit is only available for curve-like figures in this release.")
        }
        return .enabled()
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
        openInPlotHandler?(inputURL, currentFigureSheet, templateID, currentFigureRenderOptions, currentFigureFitOptions)
    }

    func updateCurrentFigureFitEnabled(_ enabled: Bool) {
        var options = currentFigureFitOptions
        options.enabled = enabled
        plotSession.fitOptions = options
        plotSession.notifyFitOptionsDidChange()
        Task { await refreshDisplayedFigureHandlingFailure() }
    }

    func updateCurrentFigureFitModel(_ modelID: String) {
        var options = currentFigureFitOptions
        options.enabled = true
        options.modelID = modelID
        plotSession.fitOptions = options
        plotSession.notifyFitOptionsDidChange()
        Task { await refreshDisplayedFigureHandlingFailure() }
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
}
