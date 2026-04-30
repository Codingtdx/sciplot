import Foundation

extension DataStudioSession {
    func newSession() {
        resetContentState()
    }

    func clearCurrentSession() {
        resetContentState()
    }

    func focusWorkbook(path: String?) {
        let resolvedPath = path ?? orderedWorkbooks.first?.response.workbookPath
        focusedWorkbookPath = resolvedPath
        guard let resolvedPath else {
            closeSpecimenFilter()
            return
        }
        ensureSpecimenFilterDataPreloaded(for: resolvedPath)
        if let specimenFilterAnchor {
            self.specimenFilterAnchor = specimenFilterAnchor.retargeted(to: resolvedPath)
        }
    }

    func updateDisplayName(for workbookPath: String, to displayName: String) {
        let previousSnapshot = undoSnapshot()
        setGroupState(
            workbookPath: workbookPath,
            displayName: displayName,
            includeInCompare: groupState(for: workbookPath)?.includeInCompare ?? true
        )
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Rename Group")
    }

    func updateCompareInclusion(for workbookPath: String, includeInCompare: Bool) {
        let previousSnapshot = undoSnapshot()
        setGroupState(
            workbookPath: workbookPath,
            displayName: groupState(for: workbookPath)?.displayName ?? "",
            includeInCompare: includeInCompare
        )
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Toggle Compare Inclusion")
    }

    func openSpecimenFilter(for workbookPath: String, anchor: DataStudioSpecimenFilterAnchor) {
        if let currentPath = specimenFilterWorkbookPath,
           currentPath != workbookPath,
           hasPendingFilterChanges(for: currentPath)
        {
            revertDraftSpecimenStates(for: currentPath)
        }
        focusedWorkbookPath = workbookPath
        specimenFilterAnchor = anchor
        primeDraftSpecimenStates(for: workbookPath)
        ensureSpecimenFilterDataPreloaded(for: workbookPath)
    }

    func openSpecimenFilter(for workbookPath: String) {
        openSpecimenFilter(for: workbookPath, anchor: .focusedStrip(workbookPath: workbookPath))
    }

    func closeSpecimenFilter() {
        guard let workbookPath = specimenFilterWorkbookPath else {
            dismissSpecimenFilter()
            return
        }
        if hasPendingFilterChanges(for: workbookPath) {
            revertDraftSpecimenStates(for: workbookPath)
        }
        dismissSpecimenFilter()
    }

    func retryPreviewRefresh() {
        guard let workbookPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath else {
            Task { await rebuildComparisonContext() }
            return
        }
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        scheduleBaselineWorkbookPreviewRefresh(for: workbookPath)
    }

    func applySuggestedExclusions(for workbookPath: String) {
        let includedIDs = suggestedAutoIncludedSpecimenIDs(for: workbookPath)
        guard !includedIDs.isEmpty else {
            return
        }
        let allSpecimenIDs = Set(allKnownSpecimenIDs(for: workbookPath))
        applyCommittedSpecimenStates(
            for: workbookPath,
            includedIDs: includedIDs,
            explicitlyExcludedIDs: allSpecimenIDs.subtracting(includedIDs),
            actionName: "Use Auto Keep 5"
        )
    }

    func applySuggestedExclusionsToAllWorkbooks() {
        let presentation = bulkAutoKeepPresentation
        guard presentation.availability.isEnabled else {
            return
        }
        let previousSnapshot = undoSnapshot()
        var changedWorkbookPaths: [String] = []
        for workbookPath in presentation.eligibleWorkbookPaths {
            let includedIDs = suggestedAutoIncludedSpecimenIDs(for: workbookPath)
            guard !includedIDs.isEmpty else {
                continue
            }
            let allSpecimenIDs = Set(allKnownSpecimenIDs(for: workbookPath))
            let previousStates = normalizedSpecimenStates(specimenStates(for: workbookPath))
            setSpecimenInclusion(
                for: workbookPath,
                includedIDs: includedIDs,
                explicitlyExcludedIDs: allSpecimenIDs.subtracting(includedIDs)
            )
            if normalizedSpecimenStates(specimenStates(for: workbookPath)) != previousStates {
                changedWorkbookPaths.append(workbookPath)
            }
        }
        guard !changedWorkbookPaths.isEmpty else {
            return
        }
        for workbookPath in changedWorkbookPaths {
            scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: false)
        }
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Use Auto Keep 5 for All Groups")
    }

    func restoreAllSpecimens(for workbookPath: String) {
        let specimenIDs = allKnownSpecimenIDs(for: workbookPath)
        guard !specimenIDs.isEmpty else {
            return
        }
        applyCommittedSpecimenStates(
            for: workbookPath,
            includedIDs: Set(specimenIDs),
            explicitlyExcludedIDs: [],
            actionName: "Turn Off Filter"
        )
    }

    func updateDraftSpecimenInclusion(for workbookPath: String, specimenId: String, included: Bool) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = upsertSpecimenState(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func updateDraftRepresentativeSelection(for workbookPath: String, specimenId: String) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = setRepresentativeSelection(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func restoreAutoRepresentativeSelection(for workbookPath: String) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = setRepresentativeSelection(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: nil
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func applyManualFilter(for workbookPath: String, completion: (() -> Void)? = nil) {
        primeDraftSpecimenStates(for: workbookPath)
        let draftStates = normalizedSpecimenStates(draftSpecimenStates(for: workbookPath))
        let previousSnapshot = undoSnapshot()
        specimenStatesByWorkbookPath[workbookPath] = draftStates
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Apply Specimen Filter Changes")
        completion?()
    }

    func revertDraftSpecimenStates(for workbookPath: String) {
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func updateSpecimenInclusion(for workbookPath: String, specimenId: String, included: Bool) {
        let previousSnapshot = undoSnapshot()
        let currentStates = upsertSpecimenState(
            in: specimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included
        )
        specimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Toggle Specimen Inclusion")
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        let previousSnapshot = undoSnapshot()
        var ordered = orderedGroups.map(\.state)
        ordered.move(fromOffsets: source, toOffset: destination)
        groupStates = ordered.enumerated().map { index, state in
            DataStudioGroupStatePayload(
                workbookPath: state.workbookPath,
                displayName: state.displayName,
                includeInCompare: state.includeInCompare,
                sortOrder: index
            )
        }
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Reorder Groups")
    }

    func removeWorkbook(path: String) {
        asyncCoordination.workbookPreview.cancel(for: path)
        asyncCoordination.baselineWorkbookPreview.cancel(for: path)
        workbooks.removeAll { $0.response.workbookPath == path }
        groupStates.removeAll { $0.workbookPath == path }
        specimenStatesByWorkbookPath.removeValue(forKey: path)
        draftSpecimenStatesByWorkbookPath.removeValue(forKey: path)
        workbookPreviewByPath.removeValue(forKey: path)
        baselineWorkbookPreviewByPath.removeValue(forKey: path)
        if specimenFilterWorkbookPath == path {
            dismissSpecimenFilter()
        }
        selectedComparisonFigureID = nil
        reindexGroupStates()
        if focusedWorkbookPath == path {
            focusedWorkbookPath = orderedWorkbooks.first?.response.workbookPath
        }
        Task { await rebuildComparisonContext() }
    }

    func refreshFocusedWorkbookPreviewIfNeeded() async {
        if let workbookPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath {
            await refreshWorkbookPreview(for: workbookPath)
            if baselineWorkbookPreview(for: workbookPath) == nil {
                await refreshBaselineWorkbookPreview(for: workbookPath)
            }
        }
    }

    func scheduleWorkbookPreviewRefresh(for workbookPath: String, rebuildComparisonContext: Bool) {
        asyncCoordination.workbookPreview.schedule(for: workbookPath) { [weak self] workbookPath, revision in
            guard let self else {
                return
            }
            await self.refreshWorkbookPreview(for: workbookPath, revision: revision)
            guard self.asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: revision), !Task.isCancelled else {
                return
            }
            if rebuildComparisonContext {
                self.scheduleComparisonContextRebuild()
            }
        }
    }

    func scheduleBaselineWorkbookPreviewRefresh(for workbookPath: String) {
        asyncCoordination.baselineWorkbookPreview.schedule(for: workbookPath) { [weak self] workbookPath, revision in
            guard let self else {
                return
            }
            await self.refreshBaselineWorkbookPreview(for: workbookPath, revision: revision)
        }
    }

    func ensureSpecimenFilterDataPreloaded(for workbookPath: String) {
        if workbookPreview(for: workbookPath) == nil {
            scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: false)
        }
        if baselineWorkbookPreview(for: workbookPath) == nil {
            scheduleBaselineWorkbookPreviewRefresh(for: workbookPath)
        }
    }

    func tracksAppliedWorkbookPreviewRefreshState(for workbookPath: String) -> Bool {
        let trackedPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath
        return trackedPath == workbookPath
    }

    func refreshWorkbookPreview(for workbookPath: String, revision: Int? = nil) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.workbookPreview.beginNow(for: workbookPath)
        if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
            focusedWorkbookPreviewRefreshState = .refreshing(workbookPath: workbookPath)
        }
        do {
            let response = try await client.previewDataStudioWorkbook(
                .init(
                    workbookPath: workbookPath,
                    specimenStates: specimenStates(for: workbookPath)
                )
            )
            guard asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            workbookPreviewByPath[workbookPath] = response
            synchronizeSpecimenStates(with: response)
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                focusedWorkbookPreviewRefreshState = .idle
            }
        } catch {
            guard asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                focusedWorkbookPreviewRefreshState = .failed(
                    workbookPath: workbookPath,
                    message: error.localizedDescription
                )
            }
        }
    }

    func refreshBaselineWorkbookPreview(for workbookPath: String, revision: Int? = nil) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.baselineWorkbookPreview.beginNow(for: workbookPath)
        if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
            baselineWorkbookPreviewRefreshState = .refreshing(workbookPath: workbookPath)
        }
        do {
            let response = try await client.previewDataStudioWorkbook(.init(workbookPath: workbookPath))
            guard asyncCoordination.baselineWorkbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            baselineWorkbookPreviewByPath[workbookPath] = response
            if specimenStatesByWorkbookPath[workbookPath] == nil, response.supported {
                specimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(
                    response.specimens.map {
                        DataStudioSpecimenStatePayload(
                            workbookPath: workbookPath,
                            specimenId: $0.specimenId,
                            included: $0.included,
                            selectedAsRepresentative: false
                        )
                    }
                )
            }
            if draftSpecimenStatesByWorkbookPath[workbookPath] == nil {
                draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                baselineWorkbookPreviewRefreshState = .idle
            }
        } catch {
            guard asyncCoordination.baselineWorkbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                baselineWorkbookPreviewRefreshState = .failed(
                    workbookPath: workbookPath,
                    message: error.localizedDescription
                )
            }
        }
    }

    func synchronizeSpecimenStates(with preview: DataStudioWorkbookPreviewResponse) {
        guard preview.supported else {
            return
        }
        let preservedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: specimenStates(for: preview.workbookPath)
        )
        specimenStatesByWorkbookPath[preview.workbookPath] = normalizedSpecimenStates(preview.specimens.map {
            DataStudioSpecimenStatePayload(
                workbookPath: preview.workbookPath,
                specimenId: $0.specimenId,
                included: $0.included,
                selectedAsRepresentative: $0.included && $0.specimenId == preservedRepresentativeSpecimenID
            )
        })
        if !hasPendingFilterChanges(for: preview.workbookPath) {
            draftSpecimenStatesByWorkbookPath[preview.workbookPath] = normalizedSpecimenStates(specimenStates(for: preview.workbookPath))
        }
    }

    func setSpecimenInclusion(
        for workbookPath: String,
        includedIDs: Set<String>,
        explicitlyExcludedIDs: Set<String>
    ) {
        let specimenIDs = allKnownSpecimenIDs(for: workbookPath)
        guard !specimenIDs.isEmpty else {
            return
        }
        let preservedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: specimenStates(for: workbookPath)
        )
        specimenStatesByWorkbookPath[workbookPath] = specimenIDs.map { specimenId in
            let included = explicitlyExcludedIDs.contains(specimenId) ? false : includedIDs.contains(specimenId)
            return DataStudioSpecimenStatePayload(
                workbookPath: workbookPath,
                specimenId: specimenId,
                included: included,
                selectedAsRepresentative: included && specimenId == preservedRepresentativeSpecimenID
            )
        }
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func allKnownSpecimenIDs(for workbookPath: String) -> [String] {
        let baselineIDs = baselineWorkbookPreview(for: workbookPath)?.specimens.map(\.specimenId) ?? []
        if !baselineIDs.isEmpty {
            return baselineIDs
        }
        let previewIDs = workbookPreview(for: workbookPath)?.specimens.map(\.specimenId) ?? []
        if !previewIDs.isEmpty {
            return previewIDs
        }
        let committedIDs = specimenStates(for: workbookPath).map(\.specimenId)
        if !committedIDs.isEmpty {
            return committedIDs
        }
        return draftSpecimenStates(for: workbookPath).map(\.specimenId)
    }

    func primeDraftSpecimenStates(for workbookPath: String) {
        if draftSpecimenStatesByWorkbookPath[workbookPath] != nil {
            return
        }
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func applyCommittedSpecimenStates(
        for workbookPath: String,
        includedIDs: Set<String>,
        explicitlyExcludedIDs: Set<String>,
        actionName: String
    ) {
        let previousSnapshot = undoSnapshot()
        setSpecimenInclusion(
            for: workbookPath,
            includedIDs: includedIDs,
            explicitlyExcludedIDs: explicitlyExcludedIDs
        )
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: actionName)
    }

    func normalizedSpecimenStates(_ states: [DataStudioSpecimenStatePayload]) -> [DataStudioSpecimenStatePayload] {
        var latestStatesBySpecimenID: [String: DataStudioSpecimenStatePayload] = [:]
        for state in states {
            latestStatesBySpecimenID[state.specimenId] = state
        }
        let normalizedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: Array(latestStatesBySpecimenID.values)
        )
        return latestStatesBySpecimenID.values
            .map { state in
                DataStudioSpecimenStatePayload(
                    workbookPath: state.workbookPath,
                    specimenId: state.specimenId,
                    included: state.included,
                    selectedAsRepresentative: state.included && state.specimenId == normalizedRepresentativeSpecimenID
                )
            }
            .sorted { lhs, rhs in
                lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
            }
    }

    func upsertSpecimenState(
        in states: [DataStudioSpecimenStatePayload],
        workbookPath: String,
        specimenId: String,
        included: Bool
    ) -> [DataStudioSpecimenStatePayload] {
        var updatedStates = states
        let selectedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(in: states)
        let payload = DataStudioSpecimenStatePayload(
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included,
            selectedAsRepresentative: included && selectedRepresentativeSpecimenID == specimenId
        )
        if let index = updatedStates.firstIndex(where: { $0.specimenId == specimenId }) {
            updatedStates[index] = payload
        } else {
            updatedStates.append(payload)
        }
        return updatedStates
    }

    func setRepresentativeSelection(
        in states: [DataStudioSpecimenStatePayload],
        workbookPath: String,
        specimenId: String?
    ) -> [DataStudioSpecimenStatePayload] {
        let selectedSpecimenID = specimenId.flatMap { candidate in
            states.contains(where: { $0.specimenId == candidate && $0.included }) ? candidate : nil
        }
        return states.map { state in
            DataStudioSpecimenStatePayload(
                workbookPath: workbookPath,
                specimenId: state.specimenId,
                included: state.included,
                selectedAsRepresentative: state.included && state.specimenId == selectedSpecimenID
            )
        }
    }

    func selectedRepresentativeSpecimenID(in states: [DataStudioSpecimenStatePayload]) -> String? {
        states.reversed().first(where: { $0.included && $0.selectedAsRepresentative })?.specimenId
    }

    func specimenFilename(for workbookPath: String, specimenId: String?) -> String? {
        guard let specimenId else {
            return nil
        }
        if let filename = baselineWorkbookPreview(for: workbookPath)?
            .specimens
            .first(where: { $0.specimenId == specimenId })?
            .filename
        {
            return filename
        }
        if let filename = workbookPreview(for: workbookPath)?
            .specimens
            .first(where: { $0.specimenId == specimenId })?
            .filename
        {
            return filename
        }
        return specimenId
    }

    func dismissSpecimenFilter() {
        specimenFilterAnchor = nil
        focusedWorkbookPreviewRefreshState = .idle
        baselineWorkbookPreviewRefreshState = .idle
    }

    func resolveRestoredWorkbookPath(selectedWorkbookID: String?, primaryWorkbookID: String?) -> String? {
        let identifiers = [selectedWorkbookID, primaryWorkbookID].compactMap { $0 }
        for identifier in identifiers {
            if let workbook = workbooks.first(where: {
                $0.response.workbookID == identifier || $0.response.workbookPath == identifier
            }) {
                return workbook.response.workbookPath
            }
        }
        return orderedWorkbooks.first?.response.workbookPath
    }

    func setGroupState(workbookPath: String, displayName: String, includeInCompare: Bool) {
        let existing = groupState(for: workbookPath)
        let sortOrder = existing?.sortOrder ?? groupStates.count
        let newState = DataStudioGroupStatePayload(
            workbookPath: workbookPath,
            displayName: displayName,
            includeInCompare: includeInCompare,
            sortOrder: sortOrder
        )
        if let index = groupStates.firstIndex(where: { $0.workbookPath == workbookPath }) {
            groupStates[index] = newState
        } else {
            groupStates.append(newState)
        }
        reindexGroupStates()
    }

    func groupState(for workbookPath: String) -> DataStudioGroupStatePayload? {
        groupStates.first(where: { $0.workbookPath == workbookPath })
    }

    func displayName(for workbook: DataStudioWorkbookItem) -> String {
        normalizedDisplayName(for: workbook, override: groupState(for: workbook.response.workbookPath)?.displayName)
    }

    func normalizedDisplayName(for workbook: DataStudioWorkbookItem, override: String?) -> String {
        let trimmed = (override ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return seededDisplayName(for: workbook)
    }

    func reindexGroupStates() {
        let orderedPaths = orderedWorkbooks.map { $0.response.workbookPath }
        let stateByPath = Dictionary(uniqueKeysWithValues: groupStates.map { ($0.workbookPath, $0) })
        groupStates = orderedPaths.enumerated().map { index, path in
            let state = stateByPath[path]
            let workbook = workbooks.first(where: { $0.response.workbookPath == path })
            return DataStudioGroupStatePayload(
                workbookPath: path,
                displayName: workbook.map { normalizedDisplayName(for: $0, override: state?.displayName) }
                    ?? seededDisplayName(workbookPath: path, responseLabel: state?.displayName ?? ""),
                includeInCompare: state?.includeInCompare ?? true,
                sortOrder: index
            )
        }
    }

    func seededDisplayName(for workbook: DataStudioWorkbookItem) -> String {
        seededDisplayName(workbookPath: workbook.response.workbookPath, responseLabel: workbook.response.label)
    }

    func seededDisplayName(for response: DataStudioWorkbookResponse) -> String {
        seededDisplayName(workbookPath: response.workbookPath, responseLabel: response.label)
    }

    func seededDisplayName(workbookPath: String, responseLabel: String) -> String {
        let workbookStem = URL(fileURLWithPath: workbookPath)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !workbookStem.isEmpty {
            return workbookStem
        }
        let trimmedLabel = responseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return "Workbook"
    }

    func upsertWorkbook(_ response: DataStudioWorkbookResponse, shouldFocus: Bool) {
        let item = DataStudioWorkbookItem(id: response.workbookID, response: response)
        if let index = workbooks.firstIndex(where: { $0.response.workbookPath == response.workbookPath }) {
            workbooks[index] = item
        } else {
            workbooks.append(item)
        }
        let existingState = groupState(for: response.workbookPath)
        if existingState == nil {
            groupStates.append(
                DataStudioGroupStatePayload(
                    workbookPath: response.workbookPath,
                    displayName: seededDisplayName(for: response),
                    includeInCompare: true,
                    sortOrder: groupStates.count
                )
            )
        }
        reindexGroupStates()
        if shouldFocus || focusedWorkbookPath == nil {
            focusedWorkbookPath = response.workbookPath
        }
        if specimenStatesByWorkbookPath[response.workbookPath] == nil {
            specimenStatesByWorkbookPath[response.workbookPath] = []
        }
        ensureSpecimenFilterDataPreloaded(for: response.workbookPath)
    }

    func applyRestoredGroupStates(_ restoredStates: [DataStudioGroupStatePayload]) {
        let validPaths = Set(workbooks.map { $0.response.workbookPath })
        let filtered = restoredStates.filter { validPaths.contains($0.workbookPath) }
        let existingPaths = Set(filtered.map(\.workbookPath))
        var merged = filtered
        for workbook in orderedWorkbooks where !existingPaths.contains(workbook.response.workbookPath) {
            merged.append(
                DataStudioGroupStatePayload(
                    workbookPath: workbook.response.workbookPath,
                    displayName: seededDisplayName(for: workbook),
                    includeInCompare: true,
                    sortOrder: merged.count
                )
            )
        }
        groupStates = merged
        reindexGroupStates()
    }

    func applyRestoredSpecimenStates(_ restoredStates: [DataStudioSpecimenStatePayload]) {
        let validPaths = Set(workbooks.map { $0.response.workbookPath })
        let filtered = restoredStates.filter { validPaths.contains($0.workbookPath) }
        specimenStatesByWorkbookPath = Dictionary(grouping: filtered, by: \.workbookPath)
            .mapValues(normalizedSpecimenStates)
    }
}
