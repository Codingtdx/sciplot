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

    func focusedWorkbookNotices(for workbook: DataStudioWorkbookItem) -> [DataStudioFocusedWorkbookNotice] {
        let workbookPath = workbook.response.workbookPath
        let previewWarnings = workbookPreview(for: workbookPath)?.warnings ?? []
        var notices: [DataStudioFocusedWorkbookNotice] = []
        var seen = Set<String>()

        func append(_ messages: [String], style: DataStudioFocusedWorkbookNoticeStyle) {
            for message in messages {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continue
                }
                let notice = DataStudioFocusedWorkbookNotice(style: style, message: trimmed)
                guard seen.insert(notice.id).inserted else {
                    continue
                }
                notices.append(notice)
            }
        }

        append(previewWarnings, style: .warning)
        append(workbook.response.warnings, style: .warning)
        append(workbook.response.exclusions, style: .exclusion)
        return notices
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
            applyDraftAvailability = .disabled("Wait for preview refresh to finish.")
        } else if hasPendingChanges {
            applyDraftAvailability = .enabled()
        } else {
            applyDraftAvailability = .disabled("Update inclusion or representative first.")
        }

        let useAutoRepresentativeAvailability: ActionAvailability
        if isBusy {
            useAutoRepresentativeAvailability = .disabled("Wait for preview refresh to finish.")
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

    var bulkAutoKeepPresentation: BulkAutoKeepPresentation {
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
            let reason = "Wait for workbook previews to finish loading."
            availability = .disabled(reason)
            help = reason
        } else if skippedCount > 0 {
            let reason = "No included workbook groups currently support Auto Keep 5."
            availability = .disabled(reason)
            help = reason
        } else {
            let reason = "Add an included workbook group first."
            availability = .disabled(reason)
            help = reason
        }

        return BulkAutoKeepPresentation(
            eligibleWorkbookPaths: eligibleWorkbookPaths,
            availability: availability,
            help: help
        )
    }

    func specimenFilterSortDescriptor(
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

    func specimenFilterSortValue(
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

    func sortedSpecimenRows(
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

    func specimenMetricValue(
        for specimen: DataStudioSpecimenPreviewResponse,
        metricID: String
    ) -> Double? {
        specimen.metrics.first { metricIdentifierMatches($0.key, metricID) }?.value ?? nil
    }

    func metricIdentifierMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func specimenFilterDisposition(
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

    func specimenFilterDispositionPriority(
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
