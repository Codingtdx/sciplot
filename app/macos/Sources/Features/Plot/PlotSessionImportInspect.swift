import Foundation

extension PlotSession {
    func handleImportedDocument(_ url: URL) {
        if url.pathExtension.lowercased() == "sciplotgod" {
            Task { await openProject(url) }
            return
        }
        importFile(url)
    }

    func importFile(_ url: URL) {
        prepareSource(url: url, sheet: .index(0), resetTemplate: true)
        scheduleInspection()
    }

    func importFileAndInspect(_ url: URL) async {
        importFile(url)
        await waitUntilInspectionFinishes(for: url)
    }

    func seedFromDataStudio(workbookURL: URL, preferredSheet: SheetValue) {
        prepareSource(url: workbookURL, sheet: preferredSheet, resetTemplate: true)
        scheduleInspection()
    }

    func setSelectedSheet(_ sheet: SheetValue) {
        guard selectedFileURL != nil else {
            selectedSheet = sheet
            return
        }
        guard selectedSheet != sheet || needsInspection else {
            return
        }
        let previousSnapshot = undoSnapshot()
        selectedSheet = sheet
        _ = asyncCoordination.preview.beginNow()
        isPreviewing = false
        invalidateSubmissionArtifacts()
        errorMessage = nil
        scheduleInspection()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Sheet")
    }

    func selectSheetAndReinspect(_ sheet: SheetValue) async {
        setSelectedSheet(sheet)
        guard selectedFileURL != nil else {
            return
        }
        await waitUntilInspectionFinishes(for: selectedFileURL)
    }

    func clearPreviewContext(preserveRenderOptions: Bool = true) {
        cancelInspectionTask()
        cancelPreviewTask()
        selectedFileURL = nil
        projectURL = nil
        selectedSheet = .index(0)
        inspectionResponse = nil
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
        errorMessage = nil
        isInspecting = false
        isPreviewing = false
        isRunningPreflight = false
        isExporting = false
        isSavingProject = false
        selectedTemplateID = nil
        runtimeState.inspectedInputPath = nil
        runtimeState.inspectedSheet = nil
        runtimeState.lastSavedProjectSnapshot = nil
        fitOptions = FitOptionsPayload()
        notifyFitOptionsDidChange()
        fitAnalysisSelectedSeriesID = nil
        sourceProvenance = PlotProjectSourceProvenancePayload(
            originalInputPath: nil,
            savedInputMtimeNs: nil,
            savedAt: nil
        )
        selectedReferenceGuideID = nil
        selectedTextAnnotationID = nil
        selectedShapeAnnotationID = nil
        resetDataWorkbookState()
        if !preserveRenderOptions {
            let defaultStyle = metadata?.defaults.stylePreset ?? "nature"
            renderOptions = RenderOptionsPayload(
                stylePreset: defaultStyle,
                palettePreset: metadata?.defaults.palettePreset ?? "colorblind_safe",
                visualThemeID: styleRecommendedThemeID(for: defaultStyle)
            )
            notifyRenderOptionsDidChange()
        }
    }

    func chooseTemplate(_ templateID: String) {
        let migratedTemplateID = migrateLegacyTemplateID(templateID) ?? templateID
        guard selectedTemplateID != migratedTemplateID else {
            return
        }
        let previousSnapshot = undoSnapshot()
        setTemplate(migratedTemplateID, shouldResetRenderOptions: true)
        schedulePreviewRefresh(policy: .immediate)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Template")
    }

    func updateRenderOptions(
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout RenderOptionsPayload) -> Void
    ) {
        let previousSnapshot = undoSnapshot()
        mutate(&renderOptions)
        guard previousSnapshot.renderOptions != renderOptions else {
            return
        }
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: policy)
        if dataWorkbookTab == .transformed {
            loadSourceTablePreview(offset: 0)
        }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Edit Plot Options")
    }

    func updateFitOptions(mutate: (inout FitOptionsPayload) -> Void) {
        let previousSnapshot = undoSnapshot()
        mutate(&fitOptions)
        guard previousSnapshot.fitOptions != fitOptions else {
            return
        }
        notifyFitOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        if supportsFitOverlayControls && fitOverlayAvailability.isEnabled {
            schedulePreviewRefresh(policy: .immediate)
        }
        if dataWorkbookTab == .fit {
            loadFitAnalysis(offset: 0)
        }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Edit Plot Fit")
    }

    func updateFitEnabled(_ enabled: Bool) {
        updateFitOptions { $0.enabled = enabled }
    }

    func updateFitModel(_ modelID: String) {
        updateFitOptions {
            $0.enabled = true
            $0.modelID = modelID
        }
    }

    func updateExtraXAxis(
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout ExtraAxisPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var axis = options.extraXAxis ?? ExtraAxisPayload(position: "top")
            mutate(&axis)
            options.extraXAxis = axis
        }
    }

    func updateExtraYAxis(
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout ExtraAxisPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var axis = options.extraYAxis ?? ExtraAxisPayload(position: "right")
            mutate(&axis)
            options.extraYAxis = axis
        }
    }

    func addAxisBreak(axis: PlotAxisSelection) {
        updateRenderOptions(policy: .immediate) { options in
            let displayMode: String
            switch axis {
            case .x:
                displayMode = (options.xAxisBreaks ?? []).contains(where: { $0.displayMode == "split" }) ? "split" : "compress"
            case .y:
                displayMode = (options.yAxisBreaks ?? []).contains(where: { $0.displayMode == "split" }) ? "split" : "compress"
            }
            let axisBreak = AxisBreakPayload(enabled: true, start: 0.0, end: 1.0, displayMode: displayMode)
            switch axis {
            case .x:
                var breaks = options.xAxisBreaks ?? []
                breaks.append(axisBreak)
                options.xAxisBreaks = breaks
            case .y:
                var breaks = options.yAxisBreaks ?? []
                breaks.append(axisBreak)
                options.yAxisBreaks = breaks
            }
        }
    }

    func updateAxisBreakDisplayMode(axis: PlotAxisSelection, mode: String) {
        updateRenderOptions(policy: .immediate) { options in
            switch axis {
            case .x:
                let breaks = (options.xAxisBreaks ?? []).map { axisBreak in
                    var updated = axisBreak
                    updated.displayMode = mode
                    return updated
                }
                options.xAxisBreaks = breaks.isEmpty ? nil : breaks
                if mode == "split" {
                    options.yAxisBreaks = nil
                }
            case .y:
                let breaks = (options.yAxisBreaks ?? []).map { axisBreak in
                    var updated = axisBreak
                    updated.displayMode = mode
                    return updated
                }
                options.yAxisBreaks = breaks.isEmpty ? nil : breaks
                if mode == "split" {
                    options.xAxisBreaks = nil
                }
            }
        }
    }

    func updateAxisBreak(
        axis: PlotAxisSelection,
        id: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout AxisBreakPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            switch axis {
            case .x:
                var breaks = options.xAxisBreaks ?? []
                guard let index = breaks.firstIndex(where: { $0.id == id }) else {
                    return
                }
                var axisBreak = breaks[index]
                mutate(&axisBreak)
                breaks[index] = axisBreak
                options.xAxisBreaks = breaks
            case .y:
                var breaks = options.yAxisBreaks ?? []
                guard let index = breaks.firstIndex(where: { $0.id == id }) else {
                    return
                }
                var axisBreak = breaks[index]
                mutate(&axisBreak)
                breaks[index] = axisBreak
                options.yAxisBreaks = breaks
            }
        }
    }

    func removeAxisBreak(axis: PlotAxisSelection, id: String) {
        updateRenderOptions(policy: .immediate) { options in
            switch axis {
            case .x:
                var breaks = options.xAxisBreaks ?? []
                breaks.removeAll { $0.id == id }
                options.xAxisBreaks = breaks.isEmpty ? nil : breaks
            case .y:
                var breaks = options.yAxisBreaks ?? []
                breaks.removeAll { $0.id == id }
                options.yAxisBreaks = breaks.isEmpty ? nil : breaks
            }
        }
    }

    func addReferenceGuide(kind: String, axisTarget: String = "y_primary") {
        updateRenderOptions(policy: .immediate) { options in
            var guides = options.referenceGuides ?? []
            let guide = ReferenceGuidePayload(
                enabled: true,
                kind: kind,
                axisTarget: axisTarget,
                value: kind == "line" ? 0.0 : nil,
                start: kind == "band" ? 0.0 : nil,
                end: kind == "band" ? 1.0 : nil
            )
            guides.append(guide)
            options.referenceGuides = guides
            selectedReferenceGuideID = guide.id
        }
    }

    func updateReferenceGuide(
        id: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout ReferenceGuidePayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var guides = options.referenceGuides ?? []
            guard let index = guides.firstIndex(where: { $0.id == id }) else {
                return
            }
            var guide = guides[index]
            mutate(&guide)
            guides[index] = guide
            options.referenceGuides = guides
        }
    }

    func removeReferenceGuide(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var guides = options.referenceGuides ?? []
            guides.removeAll { $0.id == id }
            options.referenceGuides = guides.isEmpty ? nil : guides
            if selectedReferenceGuideID == id {
                selectedReferenceGuideID = guides.first?.id
            }
        }
    }

    func addTextAnnotation(
        displayStyle: String = "plain",
        connectorEnabled: Bool = false
    ) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.textAnnotations ?? []
            let annotation = TextAnnotationPayload(
                coordinateSpace: "axes_fraction",
                displayStyle: displayStyle,
                connectorEnabled: connectorEnabled
            )
            annotations.append(annotation)
            options.textAnnotations = annotations
            selectedTextAnnotationID = annotation.id
        }
    }

    func updateTextAnnotation(
        id: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout TextAnnotationPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var annotations = options.textAnnotations ?? []
            guard let index = annotations.firstIndex(where: { $0.id == id }) else {
                return
            }
            var annotation = annotations[index]
            mutate(&annotation)
            annotations[index] = annotation
            options.textAnnotations = annotations
        }
    }

    func removeTextAnnotation(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.textAnnotations ?? []
            annotations.removeAll { $0.id == id }
            options.textAnnotations = annotations.isEmpty ? nil : annotations
            if selectedTextAnnotationID == id {
                selectedTextAnnotationID = annotations.first?.id
            }
        }
    }

    func addShapeAnnotation(kind: String) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.shapeAnnotations ?? []
            let annotation = ShapeAnnotationPayload(
                kind: kind,
                bracketOrientation: kind == "bracket" ? "horizontal" : "horizontal",
                xStart: 0.2,
                xEnd: 0.8,
                yStart: kind == "bracket" ? 0.75 : 0.2,
                yEnd: kind == "bracket" ? 0.75 : 0.8
            )
            annotations.append(annotation)
            options.shapeAnnotations = annotations
            selectedShapeAnnotationID = annotation.id
        }
    }

    func updateShapeAnnotation(
        id: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout ShapeAnnotationPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var annotations = options.shapeAnnotations ?? []
            guard let index = annotations.firstIndex(where: { $0.id == id }) else {
                return
            }
            var annotation = annotations[index]
            mutate(&annotation)
            annotations[index] = annotation
            options.shapeAnnotations = annotations
        }
    }

    func removeShapeAnnotation(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.shapeAnnotations ?? []
            annotations.removeAll { $0.id == id }
            options.shapeAnnotations = annotations.isEmpty ? nil : annotations
            if selectedShapeAnnotationID == id {
                selectedShapeAnnotationID = annotations.first?.id
            }
        }
    }

    func addAnalyticalFunctionLayer() {
        updateRenderOptions(policy: .immediate) { options in
            var layers = options.analyticalLayers ?? []
            let layer = AnalyticalLayerPayload(
                expression: "sin(x)",
                xStart: 0.0,
                xEnd: 1.0,
                sampleCount: 200,
                label: "Function"
            )
            layers.append(layer)
            options.analyticalLayers = layers
        }
    }

    func updateAnalyticalLayer(
        id: String,
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout AnalyticalLayerPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var layers = options.analyticalLayers ?? []
            guard let index = layers.firstIndex(where: { $0.id == id }) else {
                return
            }
            var layer = layers[index]
            mutate(&layer)
            layers[index] = layer
            options.analyticalLayers = layers
        }
    }

    func removeAnalyticalLayer(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var layers = options.analyticalLayers ?? []
            layers.removeAll { $0.id == id }
            options.analyticalLayers = layers.isEmpty ? nil : layers
        }
    }

    func addDataTransform(kind: String) {
        updateRenderOptions(policy: .immediate) { options in
            var transforms = options.dataTransforms ?? []
            let transform: DataTransformPayload
            switch kind {
            case "mask_filter":
                transform = DataTransformPayload(kind: "mask_filter", label: "Mask", expression: "col('x') > 0")
            case "row_filter":
                transform = DataTransformPayload(kind: "row_filter", label: "Filter", column: "Column 1", filterOperator: "between", lower: 0.0, upper: 1.0)
            case "pivot_matrix":
                transform = DataTransformPayload(kind: "pivot_matrix", label: "Pivot", xColumn: "x", yColumn: "y", zColumn: "z")
            case "bin_column":
                transform = DataTransformPayload(kind: "bin_column", label: "Bin", targetColumn: "x_bin", column: "x", bins: 10)
            case "rolling_window":
                transform = DataTransformPayload(kind: "rolling_window", label: "Smooth", targetColumn: "y_smooth", column: "y", window: 3, method: "mean")
            case "aggregate_summary":
                transform = DataTransformPayload(kind: "aggregate_summary", label: "Aggregate", groupBy: ["group"], valueColumns: ["value"], statistics: ["mean", "sd", "sem", "count"])
            default:
                transform = DataTransformPayload(kind: "derived_column", label: "Derived", targetColumn: "derived", expression: "x + 1")
            }
            transforms.append(transform)
            options.dataTransforms = transforms
        }
    }

    func addDataVariable(kind: String = "scalar") {
        updateRenderOptions(policy: .immediate) { options in
            var variables = options.dataVariables ?? []
            let variable: DataVariablePayload
            if kind == "expression" {
                variable = DataVariablePayload(kind: "expression", label: "Variable", value: nil, expression: "1 + 1")
            } else {
                variable = DataVariablePayload(kind: "scalar", label: "Variable", value: 1.0, expression: nil)
            }
            variables.append(variable)
            options.dataVariables = variables
        }
    }

    func updateDataVariable(
        id: String,
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout DataVariablePayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var variables = options.dataVariables ?? []
            guard let index = variables.firstIndex(where: { $0.id == id }) else {
                return
            }
            var variable = variables[index]
            mutate(&variable)
            variables[index] = variable
            options.dataVariables = variables
        }
    }

    func removeDataVariable(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var variables = options.dataVariables ?? []
            variables.removeAll { $0.id == id }
            options.dataVariables = variables.isEmpty ? nil : variables
        }
    }

    func updateDataTransform(
        id: String,
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout DataTransformPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var transforms = options.dataTransforms ?? []
            guard let index = transforms.firstIndex(where: { $0.id == id }) else {
                return
            }
            var transform = transforms[index]
            mutate(&transform)
            transforms[index] = transform
            options.dataTransforms = transforms
        }
    }

    func removeDataTransform(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var transforms = options.dataTransforms ?? []
            transforms.removeAll { $0.id == id }
            options.dataTransforms = transforms.isEmpty ? nil : transforms
        }
    }

    func selectReferenceGuide(id: String?) {
        selectedReferenceGuideID = selectedReferenceGuideID == id ? nil : id
    }

    func selectTextAnnotation(id: String?) {
        selectedTextAnnotationID = selectedTextAnnotationID == id ? nil : id
    }

    func selectShapeAnnotation(id: String?) {
        selectedShapeAnnotationID = selectedShapeAnnotationID == id ? nil : id
    }

    func nudgeReferenceGuide(
        id: String,
        deltaX: Double,
        deltaY: Double,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        updateReferenceGuide(id: id, policy: policy) { guide in
            if guide.kind == "line" {
                if guide.axisTarget == "x" {
                    guide.value = (guide.value ?? 0.0) + deltaX
                } else {
                    guide.value = (guide.value ?? 0.0) + deltaY
                }
            } else if guide.axisTarget == "x" {
                guide.start = (guide.start ?? 0.0) + deltaX
                guide.end = (guide.end ?? 1.0) + deltaX
            } else {
                guide.start = (guide.start ?? 0.0) + deltaY
                guide.end = (guide.end ?? 1.0) + deltaY
            }
        }
    }

    func nudgeTextAnnotationPosition(
        id: String,
        deltaX: Double,
        deltaY: Double,
        includeTarget: Bool = false,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        updateTextAnnotation(id: id, policy: policy) { annotation in
            annotation.x += deltaX
            annotation.y += deltaY
            if annotation.coordinateSpace == "axes_fraction" {
                annotation.x = min(max(annotation.x, 0.0), 1.0)
                annotation.y = min(max(annotation.y, 0.0), 1.0)
            }
            if includeTarget {
                annotation.targetX += deltaX
                annotation.targetY += deltaY
                if annotation.coordinateSpace == "axes_fraction" {
                    annotation.targetX = min(max(annotation.targetX, 0.0), 1.0)
                    annotation.targetY = min(max(annotation.targetY, 0.0), 1.0)
                }
            }
        }
    }

    func nudgeShapeAnnotation(
        id: String,
        deltaX: Double,
        deltaY: Double,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        updateShapeAnnotation(id: id, policy: policy) { annotation in
            if annotation.kind == "bracket" {
                if annotation.bracketOrientation == "horizontal" {
                    annotation.xStart += deltaX
                    annotation.xEnd += deltaX
                    annotation.yStart += deltaY
                    annotation.yEnd = annotation.yStart
                } else {
                    annotation.yStart += deltaY
                    annotation.yEnd += deltaY
                    annotation.xStart += deltaX
                    annotation.xEnd = annotation.xStart
                }
                return
            }

            annotation.xStart += deltaX
            annotation.xEnd += deltaX
            annotation.yStart += deltaY
            annotation.yEnd += deltaY
        }
    }

    func cancelInspectionTask() {
        asyncCoordination.inspection.cancel()
    }

    func waitUntilInspectionFinishes(for _: URL?) async {
        await asyncCoordination.inspection.wait()
    }

    func prepareSource(url: URL, sheet: SheetValue, resetTemplate: Bool) {
        cancelInspectionTask()
        _ = asyncCoordination.preview.beginNow()
        isPreviewing = false
        selectedFileURL = url
        sourceProvenance = sourceProvenanceForCurrentURL(url)
        selectedSheet = sheet
        selectedPlotTool = .select
        canvasSelection = .figure
        inspectionResponse = nil
        runtimeState.inspectedInputPath = nil
        runtimeState.inspectedSheet = nil
        if resetTemplate {
            selectedTemplateID = nil
        }
        runtimeState.stagedExternalPinnedSheet = nil
        runtimeState.stagedExternalPinnedTemplateID = nil
        fitOptions = FitOptionsPayload()
        notifyFitOptionsDidChange()
        fitAnalysisSelectedSeriesID = nil
        invalidateSubmissionArtifacts()
        resetDataWorkbookState()
        errorMessage = nil
    }

    func scheduleInspection() {
        guard let request = currentInspectionRequest() else {
            return
        }

        isInspecting = true
        errorMessage = nil

        asyncCoordination.inspection.schedule { [weak self] revision in
            guard let self else { return }
            await self.performInspection(request: request, revision: revision)
        }
    }

    func performInspection(request: FileRequest, revision: Int) async {
        guard let client else {
            if asyncCoordination.inspection.isLatest(revision) {
                isInspecting = false
            }
            return
        }

        do {
            let response = try await client.inspectFile(request)
            guard asyncCoordination.inspection.isLatest(revision), !Task.isCancelled else {
                return
            }
            applyInspectionResponse(response)
            isInspecting = false
        } catch {
            guard asyncCoordination.inspection.isLatest(revision), !Task.isCancelled else {
                return
            }
            if isUserCancellationError(error) {
                errorMessage = nil
                isInspecting = false
                return
            }
            errorMessage = error.localizedDescription
            isInspecting = false
        }
    }

    func applyInspectionResponse(_ response: InspectFileResponse) {
        inspectionResponse = response
        let resolvedSheet = runtimeState.stagedExternalPinnedSheet ?? response.sheet
        selectedSheet = resolvedSheet
        runtimeState.inspectedInputPath = response.inputPath
        runtimeState.inspectedSheet = resolvedSheet
        invalidateSubmissionArtifacts()
        errorMessage = nil

        if shouldAutoSelectTemplate(after: response, preservingTemplateID: runtimeState.stagedExternalPinnedTemplateID) {
            let preferredTemplateID = response.inspection.recommendations.first?.templateID
                ?? response.inspection.primaryRecommendation.first?.templateID
                ?? selectedTemplateID
            if let preferredTemplateID {
                setTemplate(preferredTemplateID, shouldResetRenderOptions: true)
            }
        }

        schedulePreviewRefresh(policy: .immediate)
        refreshDataWorkbookIfNeeded()
    }

    func shouldAutoSelectTemplate(
        after _: InspectFileResponse,
        preservingTemplateID: String? = nil
    ) -> Bool {
        if let preservingTemplateID, selectedTemplateID == preservingTemplateID {
            return false
        }
        guard let selectedTemplateID else {
            return true
        }
        return !compatibleTemplateIDs.contains(selectedTemplateID)
    }

    func currentInspectionRequest() -> FileRequest? {
        guard let selectedFileURL else {
            return nil
        }
        return .init(
            inputPath: selectedFileURL.path,
            sheet: selectedSheet,
            options: inspectionDataEngineOptions()
        )
    }

    func inspectionDataEngineOptions() -> RenderOptionsPayload? {
        let hasVariables = renderOptions.dataVariables?.isEmpty == false
        let hasTransforms = renderOptions.dataTransforms?.isEmpty == false
        guard hasVariables || hasTransforms else {
            return nil
        }
        return RenderOptionsPayload(
            stylePreset: renderOptions.stylePreset,
            palettePreset: renderOptions.palettePreset,
            visualThemeID: renderOptions.visualThemeID,
            dataVariables: renderOptions.dataVariables,
            dataTransforms: renderOptions.dataTransforms
        )
    }
}
