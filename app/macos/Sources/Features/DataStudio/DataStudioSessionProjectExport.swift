import Foundation

extension DataStudioSession {
    func exportComparisonBundle() async {
        guard let client, comparisonSet != nil else {
            errorMessage = "Import at least one workbook group before export."
            return
        }
        let recipeIDs = selectedExportRecipeIDs
        guard !recipeIDs.isEmpty else {
            errorMessage = "Choose at least one figure family before export."
            return
        }
        guard let directoryURL = chooseDirectory(
            "Export Data Studio Bundle",
            "Choose an output folder."
        ) else {
            return
        }
        guard let figureFormat = chooseComparisonFigureFormat(
            "Comparison Figure Format",
            "Export figures as PDF or 300 dpi TIFF."
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
                    figureOptionsByRecipeID: exportFigureOptionsByRecipeID(),
                    figureFitOptionsByRecipeID: exportFigureFitOptionsByRecipeID()
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
        runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
    }

    func restoreProject(from response: OpenProjectResponse) async {
        guard let projectPayload = response.payload.dataStudio else {
            errorMessage = "Opened project is missing its Data Studio payload."
            return
        }
        await restoreSession(from: sessionResponse(from: projectPayload))
        projectURL = URL(fileURLWithPath: response.projectPath)
        runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
    }

    func saveProject() async {
        if let projectURL {
            await saveProject(to: projectURL)
            return
        }
        await saveProjectAs()
    }

    func saveProjectAs() async {
        guard let destinationURL = chooseProjectSaveLocation(suggestedProjectFilename) else {
            return
        }
        await saveProject(to: destinationURL)
    }

    func saveProject(to destinationURL: URL) async {
        guard let client else {
            errorMessage = "The sidecar is not ready yet."
            return
        }
        guard let normalizedSession = await normalizeSessionPayload() else {
            if errorMessage == nil {
                errorMessage = "Could not normalize the current Data Studio session."
            }
            return
        }
        isSavingProject = true
        errorMessage = nil
        defer { isSavingProject = false }
        do {
            let response = try await client.saveProject(
                .init(
                    projectPath: destinationURL.path,
                    sourcePath: nil,
                    payload: buildProjectPayload(from: normalizedSession)
                )
            )
            if let projectPayload = response.payload.dataStudio {
                projectURL = URL(fileURLWithPath: response.projectPath)
                runtimeState.lastSavedProjectSnapshot = projectSnapshot(from: projectPayload)
            } else {
                projectURL = URL(fileURLWithPath: response.projectPath)
                runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildProjectPayload(from session: DataStudioSessionResponse) -> ProjectBundlePayload {
        ProjectBundlePayload(
            version: 1,
            selectedWorkbench: "data_studio",
            plot: nil,
            dataStudio: DataStudioProjectPayload(
                sessionKind: "data_studio",
                version: session.version,
                selectedTemplateID: session.selectedTemplateID,
                workbookPaths: session.workbookPaths,
                selectedWorkbookID: session.selectedWorkbookID,
                primaryWorkbookID: session.primaryWorkbookID,
                selectedRecipeID: session.selectedRecipeID,
                comparisonRecipeIDs: session.comparisonRecipeIDs,
                selectedFigureFamilyID: session.selectedFigureFamilyID,
                selectedFigureTemplateID: session.selectedFigureTemplateID,
                groupStates: session.groupStates,
                specimenStates: session.specimenStates,
                figurePreferences: session.figurePreferences,
                importedPaths: session.importedPaths,
                templateDraftPath: session.templateDraftPath,
                embeddedWorkbooks: [],
                projectDisplayName: projectURL?.deletingPathExtension().lastPathComponent
                    ?? focusedWorkbook?.workbookURL.deletingPathExtension().lastPathComponent,
                sourceProvenance: [
                    "imported_paths": .array(importedSourceURLs.map { .string($0.path) }),
                ]
            ),
            composer: nil,
            codeConsole: nil,
            artifacts: ["manifest_relpath": .string("artifacts/manifest.json")]
        )
    }

    func sessionResponse(from projectPayload: DataStudioProjectPayload) -> DataStudioSessionResponse {
        DataStudioSessionResponse(
            version: projectPayload.version,
            selectedTemplateID: projectPayload.selectedTemplateID,
            selectedWorkbookID: projectPayload.selectedWorkbookID,
            primaryWorkbookID: projectPayload.primaryWorkbookID,
            selectedRecipeID: projectPayload.selectedRecipeID,
            workbookPaths: projectPayload.workbookPaths,
            comparisonRecipeIDs: projectPayload.comparisonRecipeIDs,
            selectedFigureFamilyID: projectPayload.selectedFigureFamilyID,
            selectedFigureTemplateID: projectPayload.selectedFigureTemplateID,
            groupStates: projectPayload.groupStates,
            specimenStates: projectPayload.specimenStates,
            figurePreferences: projectPayload.figurePreferences,
            importedPaths: projectPayload.importedPaths,
            templateDraftPath: projectPayload.templateDraftPath
        )
    }

    func projectSnapshot(from projectPayload: DataStudioProjectPayload) -> ProjectSnapshot {
        ProjectSnapshot(
            selectedTemplateID: projectPayload.selectedTemplateID,
            selectedWorkbookID: projectPayload.selectedWorkbookID,
            primaryWorkbookID: projectPayload.primaryWorkbookID,
            selectedRecipeID: projectPayload.selectedRecipeID,
            workbookPaths: projectPayload.workbookPaths,
            comparisonRecipeIDs: projectPayload.comparisonRecipeIDs,
            selectedFigureFamilyID: projectPayload.selectedFigureFamilyID,
            selectedFigureTemplateID: projectPayload.selectedFigureTemplateID,
            groupStates: projectPayload.groupStates,
            specimenStates: projectPayload.specimenStates,
            figurePreferences: projectPayload.figurePreferences,
            importedPaths: projectPayload.importedPaths,
            templateDraftPath: projectPayload.templateDraftPath
        )
    }
}
