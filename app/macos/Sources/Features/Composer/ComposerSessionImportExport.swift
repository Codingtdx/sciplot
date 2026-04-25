import Foundation

extension ComposerSession {
    func handleImportedAssets(_ urls: [URL]) async {
        guard let client else {
            return
        }

        do {
            let previous = project
            let previousPanelIDs = Set(previous.panels.map(\.id))
            let response = try await client.importComposerPanels(
                .init(
                    project: project,
                    filePaths: urls.map(\.path),
                    kind: pendingImportKind.rawValue
                )
            )

            var candidate = response
            let importedPanelIDs = Set(candidate.panels.map(\.id)).subtracting(previousPanelIDs)
            let reflowed = reflowVisiblePanels(in: &candidate)
            if !reflowed {
                hidePanels(withIDs: importedPanelIDs, in: &candidate)
                _ = reflowVisiblePanels(in: &candidate)
                errorMessage = importedPanelIDs.isEmpty
                    ? "Current layout cannot fit this panel sequence."
                    : "Some imported panels did not fit and were kept off-board."
            } else {
                errorMessage = nil
            }

            syncPanelZIndices(in: &candidate)
            project = candidate
            exportURL = nil
            clearTargetSelection()
            focusedPanelID = candidate.panels.last?.id
            registerUndo(previousProject: previous, actionName: "Import Panels")
            schedulePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportComposition() async {
        guard let client else {
            return
        }

        guard let exportFormat = chooseExportFormat() else {
            return
        }
        guard let destinationURL = chooseExportDestination(
            suggestedComposerExportFilename(format: exportFormat),
            exportFormat
        ) else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.composeExport(project)
            let intermediateURL = URL(fileURLWithPath: response.outputPath)
            try materializeExport(intermediateURL, destinationURL)
            exportURL = destinationURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        guard let exportURL else {
            return
        }
        do {
            try WorkspaceBridge.reveal([exportURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLatestExport(id: String) {
        guard let item = latestExportItems.first(where: { $0.id == id }) else {
            return
        }
        do {
            try WorkspaceBridge.open(item.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func suggestedComposerExportFilename(format: ExportGraphicFormat) -> String {
        if let exportURL {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: exportURL.lastPathComponent,
                format: format
            )
        }
        return NativeExportCoordinator.suggestedGraphicFilename(
            from: "composer-composition",
            format: format
        )
    }
}
