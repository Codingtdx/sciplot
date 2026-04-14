import Foundation

extension DataStudioSession {
    var autoKeepAllAvailability: ActionAvailability {
        bulkAutoKeepPresentation.availability
    }

    var autoKeepAllHelp: String {
        bulkAutoKeepPresentation.help
    }

    var orderedWorkbooks: [DataStudioWorkbookItem] {
        let stateByPath = Dictionary(uniqueKeysWithValues: groupStates.map { ($0.workbookPath, $0) })
        return workbooks.sorted { lhs, rhs in
            let leftState = stateByPath[lhs.response.workbookPath]
            let rightState = stateByPath[rhs.response.workbookPath]
            let leftOrder = leftState?.sortOrder ?? Int.max
            let rightOrder = rightState?.sortOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    var orderedGroups: [DataStudioGroupRowItem] {
        orderedWorkbooks.compactMap { workbook in
            guard let state = groupState(for: workbook.response.workbookPath) else {
                return nil
            }
            return DataStudioGroupRowItem(workbook: workbook, state: state)
        }
    }

    var focusedWorkbook: DataStudioWorkbookItem? {
        guard let focusedWorkbookPath else {
            return orderedWorkbooks.first
        }
        return orderedWorkbooks.first(where: { $0.response.workbookPath == focusedWorkbookPath }) ?? orderedWorkbooks.first
    }

    var specimenFilterWorkbookPath: String? {
        specimenFilterAnchor?.workbookPath
    }

    var isSpecimenFilterPresented: Bool {
        specimenFilterAnchor != nil
    }

    var focusedWorkbookPreview: DataStudioWorkbookPreviewResponse? {
        guard let focusedWorkbook else {
            return nil
        }
        return workbookPreview(for: focusedWorkbook.response.workbookPath)
    }

    var includedGroups: [DataStudioGroupRowItem] {
        orderedGroups.filter(\.state.includeInCompare)
    }

    func workbookPreview(for workbookPath: String) -> DataStudioWorkbookPreviewResponse? {
        workbookPreviewByPath[workbookPath]
    }

    func baselineWorkbookPreview(for workbookPath: String) -> DataStudioWorkbookPreviewResponse? {
        baselineWorkbookPreviewByPath[workbookPath]
    }

    func specimenStates(for workbookPath: String) -> [DataStudioSpecimenStatePayload] {
        specimenStatesByWorkbookPath[workbookPath] ?? []
    }

    func draftSpecimenStates(for workbookPath: String) -> [DataStudioSpecimenStatePayload] {
        draftSpecimenStatesByWorkbookPath[workbookPath] ?? specimenStates(for: workbookPath)
    }

    func draftRepresentativeSpecimenID(for workbookPath: String) -> String? {
        selectedRepresentativeSpecimenID(in: draftSpecimenStates(for: workbookPath))
    }

    func draftRepresentativeFilename(for workbookPath: String) -> String? {
        specimenFilename(
            for: workbookPath,
            specimenId: draftRepresentativeSpecimenID(for: workbookPath)
        )
    }

    func suggestedAutoIncludedSpecimenIDs(for workbookPath: String) -> Set<String> {
        Set(
            baselineWorkbookPreview(for: workbookPath)?
                .specimens
                .filter { $0.autoRuleRole == "keep" }
                .map(\.specimenId) ?? []
        )
    }

    func displayedMetrics(for workbook: DataStudioWorkbookItem) -> [DataStudioMetricSummaryResponse] {
        workbookPreview(for: workbook.response.workbookPath)?.metrics ?? workbook.response.metrics
    }

    func displayedReplicateBadge(for workbook: DataStudioWorkbookItem) -> String {
        if let preview = workbookPreview(for: workbook.response.workbookPath), preview.supported {
            return "\(preview.includedSpecimenCount) / \(preview.totalSpecimenCount) included"
        }
        return "\(workbook.response.parsedSampleCount) reps"
    }

    func workbookHasWarnings(_ workbook: DataStudioWorkbookItem) -> Bool {
        if let preview = workbookPreview(for: workbook.response.workbookPath), !preview.warnings.isEmpty {
            return true
        }
        return workbook.response.failedSampleCount > 0 || !workbook.response.warnings.isEmpty
    }

    func hasPendingFilterChanges(for workbookPath: String) -> Bool {
        normalizedSpecimenStates(draftSpecimenStates(for: workbookPath)) != normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func specimenFilterMode(for workbookPath: String) -> DataStudioSpecimenFilterMode {
        let excludedIDs = Set(
            specimenStates(for: workbookPath)
                .filter { !$0.included }
                .map(\.specimenId)
        )
        if excludedIDs.isEmpty {
            return .off
        }
        let baselineSuggested = Set(baselineWorkbookPreview(for: workbookPath)?.suggestedExclusionIds ?? [])
        if !baselineSuggested.isEmpty, excludedIDs == baselineSuggested {
            return .auto
        }
        return .manual
    }

    func specimenFilterPresentation(for workbookPath: String) -> DataStudioSpecimenFilterPresentation {
        let mode = specimenFilterMode(for: workbookPath)
        let hasPendingChanges = hasPendingFilterChanges(for: workbookPath)
        let baselinePreview = baselineWorkbookPreview(for: workbookPath)
        let appliedPreview = workbookPreview(for: workbookPath)
        let appliedRefreshing: Bool
        switch focusedWorkbookPreviewRefreshState {
        case let .refreshing(currentPath):
            appliedRefreshing = currentPath == workbookPath
        default:
            appliedRefreshing = false
        }
        let baselineRefreshing: Bool
        switch baselineWorkbookPreviewRefreshState {
        case let .refreshing(currentPath):
            baselineRefreshing = currentPath == workbookPath
        default:
            baselineRefreshing = false
        }
        let isBusy = appliedRefreshing || baselineRefreshing || currentActivity == .previewingComparison
        let totalSpecimenCount = appliedPreview?.totalSpecimenCount ?? baselinePreview?.totalSpecimenCount ?? 0
        let appliedIncludedCount = appliedPreview?.includedSpecimenCount ?? totalSpecimenCount
        let autoKeepCount = baselinePreview?.specimens.filter { $0.autoRuleRole == "keep" }.count ?? 0
        let autoFilterSupported = baselinePreview?.supported == true && (baselinePreview?.suggestionSupported ?? false)
        let autoFilterReason: String?
        if baselinePreview?.supported == false {
            autoFilterReason = baselinePreview?.unsupportedReason
        } else if baselinePreview?.suggestionSupported == false {
            autoFilterReason = baselinePreview?.suggestionSupportReason
        } else {
            autoFilterReason = nil
        }

        let title: String
        switch mode {
        case .off:
            title = "All Specimens"
        case .auto:
            title = "Auto Keep 5"
        case .manual:
            title = "Manual Keep \(appliedIncludedCount)"
        }

        let help = hasPendingChanges ? "Advanced manual edits are still draft." : (autoFilterReason ?? mode.defaultHelp)
        let useAutoKeepAvailability: ActionAvailability
        if isBusy {
            useAutoKeepAvailability = .disabled("Wait for the current preview refresh to finish before applying Auto Keep 5.")
        } else if !autoFilterSupported {
            useAutoKeepAvailability = .disabled(autoFilterReason ?? "Auto Keep 5 is unavailable for this workbook group.")
        } else if autoKeepCount == 0 {
            useAutoKeepAvailability = .disabled("Auto Keep 5 did not find any eligible specimens for this workbook group.")
        } else if mode == .auto && !hasPendingChanges {
            useAutoKeepAvailability = .disabled("Auto Keep 5 is already applied to this workbook group.")
        } else {
            useAutoKeepAvailability = .enabled()
        }

        let turnOffAvailability: ActionAvailability
        if isBusy {
            turnOffAvailability = .disabled("Wait for the current preview refresh to finish before turning the filter off.")
        } else if appliedIncludedCount < totalSpecimenCount || hasPendingChanges {
            turnOffAvailability = .enabled()
        } else {
            turnOffAvailability = .disabled("All specimens are already included.")
        }

        let applyDraftAvailability: ActionAvailability
        if isBusy {
            applyDraftAvailability = .disabled("Wait for the current preview refresh to finish before applying draft specimen changes.")
        } else if hasPendingChanges {
            applyDraftAvailability = .enabled()
        } else {
            applyDraftAvailability = .disabled("Change inclusion or representative selection in Advanced before applying it.")
        }

        let useAutoRepresentativeAvailability: ActionAvailability
        if isBusy {
            useAutoRepresentativeAvailability = .disabled("Wait for the current preview refresh to finish before restoring the auto representative.")
        } else if draftRepresentativeSpecimenID(for: workbookPath) == nil {
            useAutoRepresentativeAvailability = .disabled("The focused workbook is already using the auto representative.")
        } else {
            useAutoRepresentativeAvailability = .enabled()
        }

        let revertDraftAvailability: ActionAvailability
        if hasPendingChanges {
            revertDraftAvailability = .enabled()
        } else {
            revertDraftAvailability = .disabled("There are no draft specimen edits to revert.")
        }

        let sortDescriptor = specimenFilterSortDescriptor(for: baselinePreview)
        let rankedSourceRows = sortedSpecimenRows(
            baselinePreview?.specimens ?? [],
            descriptor: sortDescriptor,
            groupByDisposition: true
        )
        let rankedRows = rankedSourceRows.enumerated().map { index, specimen in
            let disposition = specimenFilterDisposition(for: specimen)
            let showsCutoffAfter = disposition == .keep
                && rankedSourceRows.dropFirst(index + 1).contains(where: { specimenFilterDisposition(for: $0) != .keep })
            return DataStudioSpecimenFilterRankedRow(
                id: specimen.specimenId,
                rank: index + 1,
                sortValue: specimenFilterSortValue(for: specimen, descriptor: sortDescriptor),
                distanceFromMeanScore: specimen.distanceFromMeanScore,
                disposition: disposition,
                showsCutoffAfter: showsCutoffAfter
            )
        }

        return DataStudioSpecimenFilterPresentation(
            mode: mode,
            title: title,
            help: help,
            rowBadge: hasPendingChanges ? "Edited" : nil,
            hasPendingChanges: hasPendingChanges,
            isBusy: isBusy,
            autoFilterSupported: autoFilterSupported,
            autoFilterReason: autoFilterReason,
            useAutoKeepAvailability: useAutoKeepAvailability,
            turnOffAvailability: turnOffAvailability,
            applyDraftAvailability: applyDraftAvailability,
            useAutoRepresentativeAvailability: useAutoRepresentativeAvailability,
            revertDraftAvailability: revertDraftAvailability,
            sortDescriptor: sortDescriptor,
            rankedRows: rankedRows,
            advancedRows: sortedSpecimenRows(
                baselinePreview?.specimens ?? [],
                descriptor: sortDescriptor,
                groupByDisposition: false
            )
        )
    }

    func draftSpecimenIncluded(for workbookPath: String, specimenId: String) -> Bool {
        draftSpecimenStates(for: workbookPath)
            .first(where: { $0.specimenId == specimenId })?
            .included ?? true
    }

    func draftSpecimenSelectedAsRepresentative(for workbookPath: String, specimenId: String) -> Bool {
        draftRepresentativeSpecimenID(for: workbookPath) == specimenId
    }

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

    private var bulkAutoKeepPresentation: BulkAutoKeepPresentation {
        guard !orderedWorkbooks.isEmpty else {
            return BulkAutoKeepPresentation(
                eligibleWorkbookPaths: [],
                availability: .disabled("Import workbook groups before applying Auto Keep 5."),
                help: "Import workbook groups before applying Auto Keep 5."
            )
        }

        var eligibleWorkbookPaths: [String] = []
        var skippedCount = 0
        var loadingCount = 0
        for workbook in orderedWorkbooks {
            let workbookPath = workbook.response.workbookPath
            guard groupState(for: workbookPath)?.includeInCompare ?? true else {
                continue
            }
            if let baselinePreview = baselineWorkbookPreview(for: workbookPath) {
                let supported = baselinePreview.supported && baselinePreview.suggestionSupported
                let keepCount = baselinePreview.specimens.filter { $0.autoRuleRole == "keep" }.count
                if supported && keepCount > 0 {
                    eligibleWorkbookPaths.append(workbookPath)
                } else {
                    skippedCount += 1
                }
            } else {
                loadingCount += 1
            }
        }

        let availability: ActionAvailability
        let help: String
        if !eligibleWorkbookPaths.isEmpty {
            availability = .enabled()
            let label = eligibleWorkbookPaths.count == 1 ? "1 group" : "\(eligibleWorkbookPaths.count) groups"
            help = "Apply Auto Keep 5 to \(label) in the current session."
        } else if loadingCount > 0 {
            let reason = "Wait for workbook previews to finish loading before applying Auto Keep 5 to all groups."
            availability = .disabled(reason)
            help = reason
        } else if skippedCount > 0 {
            let reason = "No included workbook groups currently support Auto Keep 5."
            availability = .disabled(reason)
            help = reason
        } else {
            let reason = "Add at least one included workbook group before applying Auto Keep 5 to all groups."
            availability = .disabled(reason)
            help = reason
        }

        return BulkAutoKeepPresentation(
            eligibleWorkbookPaths: eligibleWorkbookPaths,
            availability: availability,
            help: help
        )
    }

    private func specimenFilterSortDescriptor(
        for preview: DataStudioWorkbookPreviewResponse?
    ) -> DataStudioSpecimenFilterSortDescriptor {
        guard let preview else {
            return DataStudioSpecimenFilterSortDescriptor(
                key: .distanceFromMean,
                label: "Distance from Mean",
                unit: nil
            )
        }
        var candidateMetricIDs: [String] = []
        if let currentMetricID = currentFigureFamily?.metricID, !currentMetricID.isEmpty {
            candidateMetricIDs.append(currentMetricID)
        }
        candidateMetricIDs.append("Elongation")
        candidateMetricIDs.append(contentsOf: preview.metrics.map(\.label))

        var seenMetricIDs: Set<String> = []
        for metricID in candidateMetricIDs {
            let normalizedMetricID = normalizeFigureFamilyID(metricID)
            guard seenMetricIDs.insert(normalizedMetricID).inserted else {
                continue
            }
            guard preview.specimens.contains(where: { specimenMetricValue(for: $0, metricID: metricID) != nil }) else {
                continue
            }
            let summary = preview.metrics.first(where: {
                metricIdentifierMatches($0.label, metricID) || metricIdentifierMatches($0.id, metricID)
            })
            return DataStudioSpecimenFilterSortDescriptor(
                key: .metric(metricID: summary?.label ?? metricID),
                label: summary?.label ?? metricID,
                unit: summary?.unit
            )
        }

        return DataStudioSpecimenFilterSortDescriptor(
            key: .distanceFromMean,
            label: "Distance from Mean",
            unit: nil
        )
    }

    private func specimenFilterSortValue(
        for specimen: DataStudioSpecimenPreviewResponse,
        descriptor: DataStudioSpecimenFilterSortDescriptor
    ) -> Double? {
        switch descriptor.key {
        case let .metric(metricID):
            return specimenMetricValue(for: specimen, metricID: metricID)
        case .distanceFromMean:
            return specimen.distanceFromMeanScore
        }
    }

    private func sortedSpecimenRows(
        _ specimens: [DataStudioSpecimenPreviewResponse],
        descriptor: DataStudioSpecimenFilterSortDescriptor,
        groupByDisposition: Bool
    ) -> [DataStudioSpecimenPreviewResponse] {
        specimens.sorted { lhs, rhs in
            if groupByDisposition {
                let leftDisposition = specimenFilterDisposition(for: lhs)
                let rightDisposition = specimenFilterDisposition(for: rhs)
                let leftPriority = specimenFilterDispositionPriority(leftDisposition)
                let rightPriority = specimenFilterDispositionPriority(rightDisposition)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
            }
            let leftValue = specimenFilterSortValue(for: lhs, descriptor: descriptor)
            let rightValue = specimenFilterSortValue(for: rhs, descriptor: descriptor)
            switch (leftValue, rightValue) {
            case let (left?, right?) where left != right:
                return descriptor.sortsHighToLow ? (left > right) : (left < right)
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }
            let leftDistance = lhs.distanceFromMeanScore ?? .infinity
            let rightDistance = rhs.distanceFromMeanScore ?? .infinity
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            let filenameComparison = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
            if filenameComparison != .orderedSame {
                return filenameComparison == .orderedAscending
            }
            return lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
        }
    }

    private func specimenMetricValue(
        for specimen: DataStudioSpecimenPreviewResponse,
        metricID: String
    ) -> Double? {
        specimen.metrics.first { metricIdentifierMatches($0.key, metricID) }?.value ?? nil
    }

    private func metricIdentifierMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func specimenFilterDisposition(
        for specimen: DataStudioSpecimenPreviewResponse
    ) -> DataStudioSpecimenFilterRankDisposition {
        switch specimen.autoRuleRole {
        case "keep":
            return .keep
        case "exclude":
            return .out
        default:
            return .ineligible
        }
    }

    private func specimenFilterDispositionPriority(
        _ disposition: DataStudioSpecimenFilterRankDisposition
    ) -> Int {
        switch disposition {
        case .keep:
            return 0
        case .out:
            return 1
        case .ineligible:
            return 2
        }
    }
}
