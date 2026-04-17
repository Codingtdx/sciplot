import CoreGraphics
import Foundation

extension PlotSession {
    var availableSheets: [SheetValue] {
        if let inspectionResponse, !inspectionResponse.sheetNames.isEmpty {
            return inspectionResponse.sheetNames.map(SheetValue.name)
        }
        if selectedFileURL != nil {
            return [selectedSheet]
        }
        return [.index(0)]
    }

    var availableTemplateSummaries: [MetaTemplateSummary] {
        metadata?.templates ?? []
    }

    var templateGalleryItems: [PlotTemplateGalleryItem] {
        let templates = availableTemplateSummaries
        guard !templates.isEmpty else {
            return []
        }

        guard inspectionResponse != nil else {
            return templates.prefix(5).map { template in
                PlotTemplateGalleryItem(
                    id: template.id,
                    title: template.label,
                    description: template.description,
                    thumbnailKind: thumbnailKind(for: template.id),
                    aspectRatio: templateThumbnailAspectRatio(for: template.id),
                    availability: .disabled("Import a source file to inspect compatible templates.")
                )
            }
        }

        let summariesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        return compatibleRecommendations.prefix(5).map { recommendation in
            let summary = summariesByID[recommendation.templateID]
            return PlotTemplateGalleryItem(
                id: recommendation.templateID,
                title: summary?.label ?? recommendation.templateID,
                description: summary?.description,
                thumbnailKind: thumbnailKind(for: recommendation.templateID),
                aspectRatio: templateThumbnailAspectRatio(for: recommendation.templateID),
                availability: .enabled()
            )
        }
    }

    var compatibleRecommendations: [TemplateRecommendationResponse] {
        guard let inspection = inspectionResponse?.inspection else {
            return []
        }

        let orderedCandidates = inspection.primaryRecommendation + inspection.alternativeRecommendations + inspection.advancedTemplates
        let source = orderedCandidates.isEmpty ? inspection.recommendations : orderedCandidates
        var seen: Set<String> = []
        return source.filter { candidate in
            seen.insert(candidate.templateID).inserted
        }
    }

    var compatibleTemplateIDs: Set<String> {
        Set(compatibleRecommendations.map(\.templateID))
    }

    var selectedTemplateRecommendation: TemplateRecommendationResponse? {
        guard let selectedTemplateID = effectiveTemplateID else {
            return nil
        }
        return compatibleRecommendations.first { $0.templateID == selectedTemplateID }
            ?? inspectionResponse?.inspection.recommendations.first { $0.templateID == selectedTemplateID }
    }

    var effectiveTemplateID: String? {
        if let selectedTemplateID, !selectedTemplateID.isEmpty {
            return selectedTemplateID
        }
        if let stagedTemplateID = runtimeState.stagedExternalPinnedTemplateID, !stagedTemplateID.isEmpty {
            return stagedTemplateID
        }
        if let requestedTemplateID = previewResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        if let previewTemplate = previewResponse?.template, !previewTemplate.isEmpty {
            return previewTemplate
        }
        if let requestedTemplateID = preflightResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        if let preflightTemplate = preflightResponse?.template, !preflightTemplate.isEmpty {
            return preflightTemplate
        }
        if let requestedTemplateID = exportResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        return nil
    }

    var recommendedXAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        return nil
    }

    var recommendedYAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        return nil
    }

    func templateSummary(for templateID: String) -> MetaTemplateSummary? {
        availableTemplateSummaries.first { $0.id == templateID }
    }

    func templateLabel(for templateID: String) -> String {
        templateSummary(for: templateID)?.label ?? templateID
    }

    var selectedTemplateSummary: MetaTemplateSummary? {
        effectiveTemplateID.flatMap(templateSummary(for:))
    }

    var editableOptionIDs: Set<String> {
        Set(selectedTemplateSummary?.editableOptions ?? [])
    }

    var allowedSizes: [MetaSizeResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.sizes ?? []
        }
        return (metadata?.sizes ?? []).filter { selectedTemplateSummary.allowedSizes.contains($0.id) }
    }

    var availableStyles: [MetaStyleResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.styles ?? []
        }
        return (metadata?.styles ?? []).filter { selectedTemplateSummary.availableStyles.contains($0.id) }
    }

    var availablePalettes: [MetaPaletteResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.palettes ?? []
        }
        return (metadata?.palettes ?? []).filter { selectedTemplateSummary.availablePalettes.contains($0.id) }
    }

    var sampleColumns: [PlotSampleColumn] {
        if let dataset = inspectionResponse?.dataset, !dataset.columnProfiles.isEmpty {
            return dataset.columnProfiles.enumerated().map { index, profile in
                PlotSampleColumn(id: index, title: profile.name)
            }
        }

        let maxCount = inspectionResponse?.dataset?.sampleRows.first?.count ?? 0
        return (0..<maxCount).map { PlotSampleColumn(id: $0, title: "Column \($0 + 1)") }
    }

    var sampleRows: [PlotSampleRow] {
        inspectionResponse?.dataset?.sampleRows.enumerated().map { index, values in
            PlotSampleRow(id: index, values: values)
        } ?? []
    }

    var candidateSeriesLabels: [String] {
        inspectionResponse?.dataset?.candidateRoles.series ?? []
    }

    var shouldShowSeriesLegendControls: Bool {
        editableOptionIDs.contains("series_order") && candidateSeriesLabels.count > 1
    }

    var seriesOrderLabels: [String] {
        guard shouldShowSeriesLegendControls else {
            return []
        }

        if let explicit = renderOptions.seriesOrder, !explicit.isEmpty {
            return explicit
        }

        return candidateSeriesLabels
    }

    var seriesOrderRows: [SortableSeriesListRow] {
        let labels = seriesOrderLabels
        return labels.enumerated().map { index, label in
            SortableSeriesListRow(
                id: "\(index):\(label)",
                title: label,
                positionLabel: "#\(index + 1)",
                moveUpAvailability: seriesOrderMoveAvailability(for: index, offset: -1, count: labels.count),
                moveDownAvailability: seriesOrderMoveAvailability(for: index, offset: 1, count: labels.count)
            )
        }
    }

    var canEditSeriesOrder: Bool {
        shouldShowSeriesLegendControls
    }

    var resetSeriesOrderAvailability: ActionAvailability {
        guard canEditSeriesOrder else {
            return .disabled("This plot does not expose reorderable legend entries.")
        }
        guard renderOptions.seriesOrder != nil else {
            return .disabled("Legend order already matches the source order.")
        }
        return .enabled()
    }

    func moveSeriesOrder(id: String, by offset: Int) {
        guard let index = seriesOrderRows.firstIndex(where: { $0.id == id }) else {
            return
        }
        let availability = seriesOrderMoveAvailability(for: index, offset: offset, count: seriesOrderLabels.count)
        guard availability.isEnabled else {
            return
        }

        var labels = seriesOrderLabels
        let newIndex = index + offset
        guard labels.indices.contains(index), labels.indices.contains(newIndex) else {
            return
        }
        labels.swapAt(index, newIndex)
        setSeriesOrder(labels)
    }

    func setSeriesOrder(_ labels: [String]) {
        guard shouldShowSeriesLegendControls else {
            return
        }
        let cleaned = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        renderOptions.seriesOrder = cleaned.isEmpty ? nil : cleaned
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
    }

    func moveSeriesOrder(from source: IndexSet, to destination: Int) {
        var labels = seriesOrderLabels
        labels.move(fromOffsets: source, toOffset: destination)
        setSeriesOrder(labels)
    }

    func resetSeriesOrder() {
        renderOptions.seriesOrder = nil
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
    }

    var candidateRoleRows: [(String, String)] {
        guard let roles = inspectionResponse?.dataset?.candidateRoles else {
            return []
        }

        let pairs: [(String, [String])] = [
            ("X", roles.x),
            ("Y", roles.y),
            ("Z", roles.z),
            ("Group", roles.group),
            ("Sample", roles.sample),
            ("Value", roles.value),
            ("Metric", roles.metric),
            ("Label", roles.label),
            ("Series", roles.series),
        ]

        return pairs.compactMap { title, values in
            guard !values.isEmpty else {
                return nil
            }
            return (title, values.prefix(3).joined(separator: ", "))
        }
    }

    var inferredMappingRows: [(String, String)] {
        guard let mapping = selectedTemplateRecommendation?.inferredMapping else {
            return []
        }

        return mapping
            .filter { !$0.value.isEmpty }
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func templateThumbnailAspectRatio(for templateID: String) -> CGFloat {
        guard let summary = templateSummary(for: templateID),
              let size = metadata?.sizes.first(where: { $0.id == summary.defaultSize })
        else {
            return 60.0 / 55.0
        }
        guard size.heightMm > 0 else {
            return 60.0 / 55.0
        }
        return CGFloat(size.widthMm / size.heightMm)
    }

    func thumbnailKind(for templateID: String) -> PlotTemplateThumbnailKind {
        guard let summary = templateSummary(for: templateID) else {
            return .fallback
        }
        return PlotTemplateThumbnailKind(rawValue: summary.presentationKind) ?? .fallback
    }

    private func seriesOrderMoveAvailability(for index: Int, offset: Int, count: Int) -> ActionAvailability {
        guard canEditSeriesOrder else {
            return .disabled("This plot does not expose reorderable legend entries.")
        }

        let newIndex = index + offset
        guard (0..<count).contains(index), (0..<count).contains(newIndex) else {
            if offset < 0 {
                return .disabled("This legend entry is already first.")
            }
            return .disabled("This legend entry is already last.")
        }

        return .enabled()
    }
}
