import Foundation

extension DataStudioSession {
    var resolverPresentation: DataStudioResolverPresentation {
        let rankedMatches = rankedRecommendedMatches(availableTemplates: templates)
        let recommendedTemplateIDs = Set(rankedMatches.map(\.templateID))
        let sortedTemplates = templates
            .filter { !recommendedTemplateIDs.contains($0.id) }
            .sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        let useSelectedTemplateAvailability: ActionAvailability
        if let importPreview, importPreview.status != "enabled" {
            useSelectedTemplateAvailability = .disabled(importPreview.help.isEmpty ? "The selected import filter is disabled." : importPreview.help)
        } else if selectedTemplateID == nil {
            useSelectedTemplateAvailability = .disabled("Choose a parse template before continuing.")
        } else if let selectedMatch = rankedMatches.first(where: { $0.templateID == selectedTemplateID }),
                  !selectedMatch.missingRoles.isEmpty
        {
            useSelectedTemplateAvailability = .disabled(
                "Missing required roles: \(selectedMatch.missingRoles.joined(separator: ", "))."
            )
        } else {
            useSelectedTemplateAvailability = .enabled()
        }
        return DataStudioResolverPresentation(
            recommendedMatches: rankedMatches,
            otherTemplates: sortedTemplates,
            selectedTemplateLabel: selectedTemplate?.label,
            renameTemplateAvailability: renameSelectedTemplateAvailability,
            deleteTemplateAvailability: deleteSelectedTemplateAvailability,
            useSelectedTemplateAvailability: useSelectedTemplateAvailability
        )
    }

    var createTemplateSuggestions: [DataStudioBindingSuggestionResponse] { [] }
    var createTemplatePrimaryCurveSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryMetricSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryMetadataSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePrimaryStructureSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplateSecondaryCurveSuggestions: [DataStudioBindingSuggestionResponse] { [] }
    var createTemplateFocusedSuggestion: DataStudioBindingSuggestionResponse? { nil }
    var createTemplatePreviewCaption: String? { nil }
    var activePreviewRanges: [DataStudioPreviewRangeResponse] { [] }

    var templateEditorPresentation: DataStudioTemplateEditorPresentation {
        DataStudioTemplateEditorPresentation(
            previewCaption: templatePreviewSummary,
            primaryCurveSuggestion: nil,
            primaryMetricSuggestion: nil,
            primaryMetadataSuggestion: nil,
            primaryStructureSuggestion: nil,
            secondaryCurveSuggestions: [],
            advancedCandidates: [],
            selectedSummaryItems: selectedTemplateSummaryItems,
            validationItems: templateValidationItems,
            saveTemplateAvailability: createTemplateSaveAvailability,
            saveTemplateAndContinueAvailability: createTemplateSaveAndContinueAvailability
        )
    }

    var selectedTemplateSummaryItems: [DataStudioTemplateSummaryItem] {
        var items: [DataStudioTemplateSummaryItem] = []
        if let sourcePreview {
            items.append(
                .init(
                    id: "source",
                    title: "Source",
                    value: URL(fileURLWithPath: sourcePreview.inputPath).lastPathComponent
                )
            )
            if let encoding = sourcePreview.encoding, !encoding.isEmpty {
                items.append(.init(id: "encoding", title: "Encoding", value: encoding))
            }
            if let delimiter = sourcePreview.delimiter, !delimiter.isEmpty {
                let label = delimiter == "\t" ? "Tab" : delimiter
                items.append(.init(id: "delimiter", title: "Delimiter", value: label))
            }
        }
        if let selectedSegment {
            items.append(.init(id: "segment", title: "Segment", value: selectedSegment.label))
        }
        if let x = templateDraftXColumnName, !x.isEmpty {
            items.append(.init(id: "x", title: "X", value: x))
        }
        if !templateDraftYColumnNames.isEmpty {
            items.append(.init(id: "y", title: "Y", value: templateDraftYColumnNames.joined(separator: ", ")))
        }
        if !templateDraftSampleNameByYColumn.isEmpty {
            let sampleValues = templateDraftYColumnNames.compactMap { column -> String? in
                let value = templateDraftSampleNameByYColumn[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !value.isEmpty else {
                    return nil
                }
                return value
            }
            if !sampleValues.isEmpty {
                items.append(.init(id: "sample_names", title: "Sample Names", value: sampleValues.joined(separator: ", ")))
            }
        }
        if !templateDraftMetricColumnNames.isEmpty,
           templateDraftOutputKind == "metric_table"
           || templateDraftOutputKind == "matrix_heatmap"
           || templateDraftComparisonEnabled
        {
            items.append(
                .init(
                    id: "metrics",
                    title: "Metrics",
                    value: templateDraftMetricColumnNames.joined(separator: ", ")
                )
            )
        }
        if templateDraftOutputKind == "curve_metrics" {
            items.append(
                .init(
                    id: "comparison",
                    title: "Comparison",
                    value: templateDraftComparisonEnabled ? "Enabled" : "Disabled"
                )
            )
        }
        return items
    }

    var selectedTemplate: DataStudioTemplateResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first(where: { $0.id == selectedTemplateID })
    }

    var selectedSegment: SourceTableSegmentResponse? {
        guard let selectedPreviewSegmentID else {
            return nil
        }
        return sourcePreview?.segments.first(where: { $0.id == selectedPreviewSegmentID })
    }

    var templatePreviewSummary: String? {
        guard let templatePreview else {
            return nil
        }
        if !templatePreview.errors.isEmpty {
            return templatePreview.errors.joined(separator: " ")
        }
        if !templatePreview.missingRoles.isEmpty {
            return "Missing roles: \(templatePreview.missingRoles.joined(separator: ", "))."
        }
        switch templatePreview.outputKind {
        case "metric_table":
            return "\(templatePreview.metricCount) metric fields resolved."
        case "matrix_heatmap":
            return "\(templatePreview.matrixRowCount) matrix rows resolved."
        default:
            return "\(templatePreview.seriesCount) curves resolved."
        }
    }

    var templateValidationItems: [DataStudioTemplateSummaryItem] {
        guard let templatePreview else {
            return [
                .init(id: "status", title: "Status", value: "Preview not run"),
            ]
        }

        var items: [DataStudioTemplateSummaryItem] = []
        if !templatePreview.errors.isEmpty {
            items.append(.init(id: "errors", title: "Errors", value: templatePreview.errors.joined(separator: " ")))
        }
        if !templatePreview.missingRoles.isEmpty {
            items.append(.init(id: "missing_roles", title: "Missing Roles", value: templatePreview.missingRoles.joined(separator: ", ")))
        }
        items.append(.init(id: "samples", title: "Samples", value: "\(templatePreview.parsedSampleCount) parsed / \(templatePreview.failedSampleCount) failed"))
        switch templatePreview.outputKind {
        case "metric_table":
            items.append(.init(id: "metrics", title: "Metrics", value: "\(templatePreview.metricCount)"))
        case "matrix_heatmap":
            items.append(.init(id: "matrix_rows", title: "Matrix Rows", value: "\(templatePreview.matrixRowCount)"))
        default:
            items.append(.init(id: "curves", title: "Curves", value: "\(templatePreview.seriesCount)"))
            items.append(.init(id: "metrics", title: "Metrics", value: "\(templatePreview.metricCount)"))
        }
        if !templatePreview.segments.isEmpty {
            items.append(.init(id: "segments", title: "Segments", value: "\(templatePreview.segments.count)"))
        }
        if !templatePreview.warnings.isEmpty {
            items.append(.init(id: "warnings", title: "Warnings", value: templatePreview.warnings.joined(separator: " ")))
        }
        if items.isEmpty {
            items.append(.init(id: "status", title: "Status", value: "Ready"))
        }
        return items
    }

    var canGoBackInImportWizard: Bool {
        switch importWizardStep {
        case .scope:
            return false
        case .kind:
            return hasSessionContent
        case .resolver, .createTemplate:
            return true
        }
    }
}
