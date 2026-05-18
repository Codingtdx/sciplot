import Foundation
import CoreGraphics

extension PlotSession {
    func newSession() {
        isImporterPresented = false
        isDataWorkbookPresented = false
        previewPixelBucket = nil
        selectedPlotTool = .select
        selectedPlotAdjustmentCategory = .figure
        canvasSelection = .figure
        selectedPreviewObjectID = nil
        selectedPreviewQuickEditorObjectID = nil
        clearPreviewContext(preserveRenderOptions: false)
    }

    func handleImportedDocument(_ url: URL) {
        if FileTypeCatalog.isProjectURL(url) {
            Task {
                if let openProjectDocumentHandler {
                    await openProjectDocumentHandler(url)
                } else {
                    await openProject(url)
                }
            }
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
        previewSceneResponse = nil
        previewSceneRevision = nil
        previewSceneFallbackReason = nil
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
        selectedPreviewObjectID = nil
        selectedPreviewQuickEditorObjectID = nil
        selectedSeriesQuickEditorID = nil
        plotEditCommandLedger = []
        plotCommandGraphRevision = 0
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
        setTemplate(
            migratedTemplateID,
            shouldResetRenderOptions: true,
            preservingSize: renderOptions.size
        )
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
        recordAxisCommandsIfNeeded(before: previousSnapshot.renderOptions, after: renderOptions)
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

    func openSeriesQuickEditor(seriesID: String) {
        selectedPreviewQuickEditorObjectID = nil
        selectedSeriesQuickEditorID = seriesID
        canvasInteractionMode = .select
        selectedPlotAdjustmentCategory = .legend
        selectPlotLayer(.series(seriesID))
    }

    @discardableResult
    func selectPreviewSeries(at location: CGPoint, mapper: PlotPreviewCoordinateMapper) -> Bool {
        guard let seriesID = PlotInteractionHitTester(mapper: mapper).hitTest(at: location)?.seriesID else {
            return false
        }
        selectPlotLayer(.series(seriesID))
        return true
    }

    @discardableResult
    func openPreviewSeriesQuickEditor(at location: CGPoint, mapper: PlotPreviewCoordinateMapper) -> Bool {
        guard let seriesID = PlotInteractionHitTester(mapper: mapper).hitTest(at: location)?.seriesID else {
            return false
        }
        openSeriesQuickEditor(seriesID: seriesID)
        return true
    }

    @discardableResult
    func selectPreviewObject(_ object: PreviewInteractionObjectMetadata) -> Bool {
        selectedPreviewQuickEditorObjectID = nil
        if let payloadRef = object.payloadRef {
            switch payloadRef.type {
            case "series":
                selectPlotLayer(.series(payloadRef.id))
            case "reference_guide":
                selectedPlotAdjustmentCategory = .guides
                selectPlotLayer(.referenceGuide(payloadRef.id))
            case "text_annotation":
                selectedPlotAdjustmentCategory = .annotations
                selectPlotLayer(.textAnnotation(payloadRef.id))
            case "shape_annotation":
                selectedPlotAdjustmentCategory = .annotations
                selectPlotLayer(.shapeAnnotation(payloadRef.id))
            case "analytical_layer", "function":
                selectedPlotAdjustmentCategory = .functions
                selectPlotLayer(.function(payloadRef.id))
            case "fit_overlay":
                selectedPlotAdjustmentCategory = .fit
                selectPlotLayer(.fitOverlay)
            case "axis", "axis_label":
                selectedPlotAdjustmentCategory = .axes
                let yAxisKinds = ["y_axis", "y_label", "colorbar"]
                selectCanvasSelection(.axis(yAxisKinds.contains(object.kind) ? .y : .x))
            case "legend":
                selectedPlotAdjustmentCategory = .legend
                selectCanvasSelection(.figure)
            case "table", "table_cell", "heatmap_cell", "artist":
                canvasSelection = .figure
                selectedSeriesQuickEditorID = nil
                selectedReferenceGuideID = nil
                selectedTextAnnotationID = nil
                selectedShapeAnnotationID = nil
            default:
                canvasSelection = .figure
                selectedSeriesQuickEditorID = nil
                selectedReferenceGuideID = nil
                selectedTextAnnotationID = nil
                selectedShapeAnnotationID = nil
            }
            selectedPreviewObjectID = object.id
            return true
        }

        switch object.kind {
        case "x_axis", "x_label":
            selectedPlotAdjustmentCategory = .axes
            selectCanvasSelection(.axis(.x))
        case "y_axis", "y_label", "colorbar":
            selectedPlotAdjustmentCategory = .axes
            selectCanvasSelection(.axis(.y))
        case "axis", "axis_title":
            selectedPlotAdjustmentCategory = .axes
            selectCanvasSelection(.axis(.x))
        case "legend", "legend_entry":
            selectedPlotAdjustmentCategory = .legend
            selectCanvasSelection(.figure)
        case "function_layer":
            selectedPlotAdjustmentCategory = .functions
            selectCanvasSelection(.layer(.function(object.payloadRef?.id ?? object.id)))
        case "fit_overlay":
            selectedPlotAdjustmentCategory = .fit
            selectCanvasSelection(.layer(.fitOverlay))
        default:
            canvasSelection = .figure
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        }
        selectedPreviewObjectID = object.id
        return true
    }

    @discardableResult
    func openPreviewObjectQuickEditor(_ object: PreviewInteractionObjectMetadata) -> Bool {
        if let seriesID = object.seriesID, object.operations.contains("quick_edit") {
            openSeriesQuickEditor(seriesID: seriesID)
            return true
        }
        guard selectPreviewObject(object) else {
            return false
        }
        if object.operations.contains("quick_edit") || object.operations.contains("more") {
            selectedPreviewQuickEditorObjectID = object.id
        }
        return true
    }

    func updateSeriesStyle(
        seriesID: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout SeriesStylePayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var styles = options.seriesStyles ?? []
            let index = styles.firstIndex { $0.seriesID == seriesID }
            let before = index.map { styles[$0] }
            var style = before ?? SeriesStylePayload(seriesID: seriesID)
            mutate(&style)
            guard before != style else {
                return
            }
            if let index {
                styles[index] = style
            } else {
                styles.append(style)
            }
            options.seriesStyles = styles
            recordPlotEditCommand(
                kind: "edit",
                targetObjectID: plotObjectID(prefix: "series", id: seriesID),
                before: before.map(plotCommandPayload),
                after: plotCommandPayload(style)
            )
        }
    }

    func updateSeriesOffset(
        seriesID: String,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: (inout SeriesOffsetPayload) -> Void
    ) {
        updateRenderOptions(policy: policy) { options in
            var offsets = options.seriesOffsets ?? []
            let index = offsets.firstIndex { $0.seriesID == seriesID }
            let before = index.map { offsets[$0] }
            var offset = before ?? SeriesOffsetPayload(seriesID: seriesID)
            mutate(&offset)
            guard before != offset else {
                return
            }
            if let index {
                offsets[index] = offset
            } else {
                offsets.append(offset)
            }
            options.seriesOffsets = offsets
            recordPlotEditCommand(
                kind: "edit",
                targetObjectID: plotObjectID(prefix: "series", id: seriesID),
                before: before.map(plotCommandPayload),
                after: plotCommandPayload(offset)
            )
        }
    }

    func setSeriesOffset(
        seriesID: String,
        xOffset: Double,
        yOffset: Double,
        policy: PlotPreviewRefreshPolicy = .immediate
    ) {
        updateSeriesOffset(seriesID: seriesID, policy: policy) { offset in
            offset.enabled = true
            offset.xOffset = xOffset
            offset.yOffset = yOffset
        }
    }

    func resetSeriesOffset(
        seriesID: String,
        policy: PlotPreviewRefreshPolicy = .immediate
    ) {
        updateSeriesOffset(seriesID: seriesID, policy: policy) { offset in
            offset.xOffset = 0.0
            offset.yOffset = 0.0
        }
    }

    func commitPreviewSeriesDrag(
        seriesID: String,
        xOffset: Double,
        yOffset: Double,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        updateSeriesOffset(seriesID: seriesID, policy: policy) { offset in
            offset.enabled = true
            offset.xOffset += xOffset
            offset.yOffset += yOffset
        }
    }

    func nudgeSelectedPreviewObject(
        delta: PlotCanvasDataPoint,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        guard case .layer(let selection) = canvasSelection else {
            return
        }
        switch selection {
        case .series(let id):
            commitPreviewSeriesDrag(seriesID: id, xOffset: delta.x, yOffset: delta.y, policy: policy)
        case .referenceGuide, .textAnnotation, .shapeAnnotation:
            moveSelectedOverlay(delta: delta, policy: policy)
        case .function(let id):
            updateAnalyticalLayer(id: id, policy: policy) { layer in
                layer.xStart += delta.x
                layer.xEnd += delta.x
            }
        case .fitOverlay:
            break
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
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "guide", id: guide.id),
                before: nil,
                after: plotCommandPayload(guide)
            )
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
            let before = guide
            mutate(&guide)
            guard before != guide else {
                return
            }
            guides[index] = guide
            options.referenceGuides = guides
            recordPlotEditCommand(
                kind: plotCommandKind(before: before.enabled, after: guide.enabled),
                targetObjectID: plotObjectID(prefix: "guide", id: id),
                before: plotCommandPayload(before),
                after: plotCommandPayload(guide)
            )
        }
    }

    func removeReferenceGuide(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var guides = options.referenceGuides ?? []
            guard let removed = guides.first(where: { $0.id == id }) else {
                return
            }
            guides.removeAll { $0.id == id }
            options.referenceGuides = guides.isEmpty ? nil : guides
            if selectedReferenceGuideID == id {
                selectedReferenceGuideID = guides.first?.id
            }
            recordPlotEditCommand(
                kind: "delete",
                targetObjectID: plotObjectID(prefix: "guide", id: id),
                before: plotCommandPayload(removed),
                after: nil
            )
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
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "text_annotation", id: annotation.id),
                before: nil,
                after: plotCommandPayload(annotation)
            )
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
            let before = annotation
            mutate(&annotation)
            guard before != annotation else {
                return
            }
            annotations[index] = annotation
            options.textAnnotations = annotations
            recordPlotEditCommand(
                kind: plotCommandKind(before: before.enabled, after: annotation.enabled),
                targetObjectID: plotObjectID(prefix: "text_annotation", id: id),
                before: plotCommandPayload(before),
                after: plotCommandPayload(annotation)
            )
        }
    }

    func removeTextAnnotation(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.textAnnotations ?? []
            guard let removed = annotations.first(where: { $0.id == id }) else {
                return
            }
            annotations.removeAll { $0.id == id }
            options.textAnnotations = annotations.isEmpty ? nil : annotations
            if selectedTextAnnotationID == id {
                selectedTextAnnotationID = annotations.first?.id
            }
            recordPlotEditCommand(
                kind: "delete",
                targetObjectID: plotObjectID(prefix: "text_annotation", id: id),
                before: plotCommandPayload(removed),
                after: nil
            )
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
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "shape_annotation", id: annotation.id),
                before: nil,
                after: plotCommandPayload(annotation)
            )
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
            let before = annotation
            mutate(&annotation)
            guard before != annotation else {
                return
            }
            annotations[index] = annotation
            options.shapeAnnotations = annotations
            recordPlotEditCommand(
                kind: plotCommandKind(before: before.enabled, after: annotation.enabled),
                targetObjectID: plotObjectID(prefix: "shape_annotation", id: id),
                before: plotCommandPayload(before),
                after: plotCommandPayload(annotation)
            )
        }
    }

    func removeShapeAnnotation(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.shapeAnnotations ?? []
            guard let removed = annotations.first(where: { $0.id == id }) else {
                return
            }
            annotations.removeAll { $0.id == id }
            options.shapeAnnotations = annotations.isEmpty ? nil : annotations
            if selectedShapeAnnotationID == id {
                selectedShapeAnnotationID = annotations.first?.id
            }
            recordPlotEditCommand(
                kind: "delete",
                targetObjectID: plotObjectID(prefix: "shape_annotation", id: id),
                before: plotCommandPayload(removed),
                after: nil
            )
        }
    }

    func beginCanvasPlacement(_ mode: PlotCanvasInteractionMode) {
        guard mode == .select || plotAdjustmentAvailability(for: selectedPlotAdjustmentCategory).isEnabled else {
            return
        }
        canvasInteractionMode = mode
        switch mode {
        case .text, .callout, .rectangle, .ellipse, .bracket:
            selectPlotAdjustmentCategory(.annotations)
        case .guideLine, .guideRegion:
            selectPlotAdjustmentCategory(.guides)
        case .select:
            break
        }
    }

    func commitCanvasDraft(_ draft: PlotCanvasDraft) {
        switch draft {
        case .text(let point, let displayStyle, let connectorTarget):
            commitCanvasText(point: point, displayStyle: displayStyle, connectorTarget: connectorTarget)
        case .shape(let kind, let start, let end):
            commitCanvasShape(kind: kind, start: start, end: end)
        case .guideLine(let axisTarget, let value):
            commitCanvasGuideLine(axisTarget: axisTarget, value: value)
        case .guideRegion(let axisTarget, let start, let end):
            commitCanvasGuideRegion(axisTarget: axisTarget, start: start, end: end)
        }
        canvasInteractionMode = .select
    }

    private func commitCanvasText(
        point: PlotCanvasDataPoint,
        displayStyle: String,
        connectorTarget: PlotCanvasDataPoint?
    ) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.textAnnotations ?? []
            let annotation = TextAnnotationPayload(
                text: "Annotation",
                coordinateSpace: "data",
                x: point.x,
                y: point.y,
                displayStyle: displayStyle,
                connectorEnabled: connectorTarget != nil || displayStyle == "callout",
                targetX: connectorTarget?.x ?? point.x,
                targetY: connectorTarget?.y ?? point.y,
                targetYAxisTarget: "y_primary"
            )
            annotations.append(annotation)
            options.textAnnotations = annotations
            selectedTextAnnotationID = annotation.id
            canvasSelection = .layer(.textAnnotation(annotation.id))
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "text_annotation", id: annotation.id),
                before: nil,
                after: plotCommandPayload(annotation)
            )
        }
    }

    private func commitCanvasShape(
        kind: String,
        start: PlotCanvasDataPoint,
        end: PlotCanvasDataPoint
    ) {
        updateRenderOptions(policy: .immediate) { options in
            var annotations = options.shapeAnnotations ?? []
            let xStart = min(start.x, end.x)
            let xEnd = max(start.x, end.x)
            let yStart = min(start.y, end.y)
            let yEnd = max(start.y, end.y)
            let bracketOrientation = abs(end.x - start.x) >= abs(end.y - start.y) ? "horizontal" : "vertical"
            let annotation = ShapeAnnotationPayload(
                kind: kind,
                bracketOrientation: kind == "bracket" ? bracketOrientation : "horizontal",
                xStart: kind == "bracket" && bracketOrientation == "vertical" ? start.x : xStart,
                xEnd: kind == "bracket" && bracketOrientation == "vertical" ? start.x : xEnd,
                yStart: kind == "bracket" && bracketOrientation == "horizontal" ? start.y : yStart,
                yEnd: kind == "bracket" && bracketOrientation == "horizontal" ? start.y : yEnd
            )
            annotations.append(annotation)
            options.shapeAnnotations = annotations
            selectedShapeAnnotationID = annotation.id
            canvasSelection = .layer(.shapeAnnotation(annotation.id))
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "shape_annotation", id: annotation.id),
                before: nil,
                after: plotCommandPayload(annotation)
            )
        }
    }

    private func commitCanvasGuideLine(axisTarget: String, value: Double) {
        updateRenderOptions(policy: .immediate) { options in
            var guides = options.referenceGuides ?? []
            let guide = ReferenceGuidePayload(
                kind: "line",
                axisTarget: axisTarget,
                value: value
            )
            guides.append(guide)
            options.referenceGuides = guides
            selectedReferenceGuideID = guide.id
            canvasSelection = .layer(.referenceGuide(guide.id))
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "guide", id: guide.id),
                before: nil,
                after: plotCommandPayload(guide)
            )
        }
    }

    private func commitCanvasGuideRegion(axisTarget: String, start: Double, end: Double) {
        updateRenderOptions(policy: .immediate) { options in
            var guides = options.referenceGuides ?? []
            let guide = ReferenceGuidePayload(
                kind: "band",
                axisTarget: axisTarget,
                value: nil,
                start: min(start, end),
                end: max(start, end)
            )
            guides.append(guide)
            options.referenceGuides = guides
            selectedReferenceGuideID = guide.id
            canvasSelection = .layer(.referenceGuide(guide.id))
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "guide", id: guide.id),
                before: nil,
                after: plotCommandPayload(guide)
            )
        }
    }

    func moveSelectedOverlay(
        delta: PlotCanvasDataPoint,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        guard case .layer(let selection) = canvasSelection else {
            return
        }
        switch selection {
        case .referenceGuide(let id):
            nudgeReferenceGuide(id: id, deltaX: delta.x, deltaY: delta.y, policy: policy)
        case .textAnnotation(let id):
            nudgeTextAnnotationPosition(id: id, deltaX: delta.x, deltaY: delta.y, includeTarget: true, policy: policy)
        case .shapeAnnotation(let id):
            nudgeShapeAnnotation(id: id, deltaX: delta.x, deltaY: delta.y, policy: policy)
        case .fitOverlay, .function, .series:
            break
        }
    }

    func resizeSelectedOverlay(
        handle: PlotCanvasResizeHandle,
        point: PlotCanvasDataPoint,
        policy: PlotPreviewRefreshPolicy = .debounced
    ) {
        guard case .layer(.shapeAnnotation(let id)) = canvasSelection else {
            return
        }
        updateShapeAnnotation(id: id, policy: policy) { annotation in
            switch handle {
            case .topLeft:
                annotation.xStart = point.x
                annotation.yEnd = point.y
            case .topRight:
                annotation.xEnd = point.x
                annotation.yEnd = point.y
            case .bottomLeft:
                annotation.xStart = point.x
                annotation.yStart = point.y
            case .bottomRight:
                annotation.xEnd = point.x
                annotation.yStart = point.y
            case .start:
                annotation.xStart = point.x
                annotation.yStart = point.y
            case .end:
                annotation.xEnd = point.x
                annotation.yEnd = point.y
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
            recordPlotEditCommand(
                kind: "add",
                targetObjectID: plotObjectID(prefix: "function", id: layer.id),
                before: nil,
                after: plotCommandPayload(layer)
            )
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
            let before = layer
            mutate(&layer)
            guard before != layer else {
                return
            }
            layers[index] = layer
            options.analyticalLayers = layers
            recordPlotEditCommand(
                kind: plotCommandKind(before: before.enabled, after: layer.enabled),
                targetObjectID: plotObjectID(prefix: "function", id: id),
                before: plotCommandPayload(before),
                after: plotCommandPayload(layer)
            )
        }
    }

    func removeAnalyticalLayer(id: String) {
        updateRenderOptions(policy: .immediate) { options in
            var layers = options.analyticalLayers ?? []
            guard let removed = layers.first(where: { $0.id == id }) else {
                return
            }
            layers.removeAll { $0.id == id }
            options.analyticalLayers = layers.isEmpty ? nil : layers
            recordPlotEditCommand(
                kind: "delete",
                targetObjectID: plotObjectID(prefix: "function", id: id),
                before: plotCommandPayload(removed),
                after: nil
            )
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
        canvasInteractionMode = .select
        canvasSelection = .figure
        selectedPreviewObjectID = nil
        selectedPreviewQuickEditorObjectID = nil
        selectedSeriesQuickEditorID = nil
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

    func plotObjectID(prefix: String, id: String) -> String {
        "plot:\(prefix):\(id)"
    }

    func plotCommandKind(before: Bool, after: Bool) -> String {
        before != after ? "visibility" : "edit"
    }

    func plotCommandPayload<T: Encodable>(_ value: T) -> [String: JSONValue] {
        guard
            let data = try? JSONEncoder().encode(value),
            let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data)
        else {
            return [:]
        }
        return payload
    }

    func recordPlotEditCommand(
        kind: String,
        targetObjectID: String,
        before: [String: JSONValue]?,
        after: [String: JSONValue]?
    ) {
        guard !runtimeState.isApplyingUndoRedo else {
            return
        }
        let commandKind = kind.replacingOccurrences(of: "-", with: "_")
        let command = PlotEditCommandPayload(
            commandID: "cmd:\(commandKind):\(targetObjectID):\(plotEditCommandLedger.count + 1)",
            kind: commandKind,
            targetObjectID: targetObjectID,
            before: before,
            after: after,
            graphPatch: [
                "target_object_id": .string(targetObjectID),
                "kind": .string(commandKind)
            ],
            reversible: before != after,
            help: "Undoable typed plot edit command recorded by PlotSession."
        )
        plotEditCommandLedger.append(command)
        normalizeRecordedPlotEditCommand(commandID: command.commandID)
    }

    private func recordAxisCommandsIfNeeded(before: RenderOptionsPayload, after: RenderOptionsPayload) {
        let beforeX = axisCommandPayload(axis: "x", options: before)
        let afterX = axisCommandPayload(axis: "x", options: after)
        if beforeX != afterX {
            recordPlotEditCommand(
                kind: before.xLabelOverride != after.xLabelOverride ? "rename" : "edit",
                targetObjectID: "plot:axis:x",
                before: beforeX,
                after: afterX
            )
        }

        let beforeY = axisCommandPayload(axis: "y", options: before)
        let afterY = axisCommandPayload(axis: "y", options: after)
        if beforeY != afterY {
            recordPlotEditCommand(
                kind: before.yLabelOverride != after.yLabelOverride ? "rename" : "edit",
                targetObjectID: "plot:axis:y",
                before: beforeY,
                after: afterY
            )
        }
    }

    private func axisCommandPayload(axis: String, options: RenderOptionsPayload) -> [String: JSONValue] {
        func optionalNumber(_ value: Double?) -> JSONValue {
            value.map(JSONValue.number) ?? .null
        }
        func optionalString(_ value: String?) -> JSONValue {
            value.map(JSONValue.string) ?? .null
        }
        if axis == "x" {
            return [
                "axis": .string("x"),
                "label": optionalString(options.xLabelOverride),
                "min": optionalNumber(options.xMin),
                "max": optionalNumber(options.xMax),
                "scale": optionalString(options.xscale),
                "tickDensity": optionalString(options.xTickDensity),
                "tickEdgeLabels": optionalString(options.xTickEdgeLabels),
                "reverse": .bool(options.reverseX)
            ]
        }
        return [
            "axis": .string("y"),
            "label": optionalString(options.yLabelOverride),
            "min": optionalNumber(options.yMin),
            "max": optionalNumber(options.yMax),
            "scale": optionalString(options.yscale),
            "tickDensity": optionalString(options.yTickDensity),
            "tickEdgeLabels": optionalString(options.yTickEdgeLabels)
        ]
    }

    private func normalizeRecordedPlotEditCommand(commandID: String) {
        Task { @MainActor [weak self] in
            await self?.normalizeAndApplyRecordedPlotEditCommand(commandID: commandID)
        }
    }

    private func normalizeAndApplyRecordedPlotEditCommand(commandID: String) async {
        guard
            let client,
            let index = plotEditCommandLedger.firstIndex(where: { $0.commandID == commandID })
        else {
            return
        }
        let localCommand = plotEditCommandLedger[index]
        do {
            let normalized = try await client.normalizeCommand(.init(command: localCommand))
            guard
                normalized.command.commandID == commandID,
                let normalizedIndex = plotEditCommandLedger.firstIndex(where: { $0.commandID == commandID })
            else {
                return
            }
            plotEditCommandLedger[normalizedIndex] = normalized.command
            let response = try await client.applyCommandPreview(
                .init(
                    command: normalized.command,
                    documentGraph: [
                        "schema_version": .number(2),
                        "revision": .number(Double(plotCommandGraphRevision))
                    ]
                )
            )
            guard
                response.command.commandID == commandID,
                let appliedIndex = plotEditCommandLedger.firstIndex(where: { $0.commandID == commandID })
            else {
                return
            }
            plotCommandGraphRevision = response.graphRevision
            plotEditCommandLedger[appliedIndex] = response.command
        } catch {
            return
        }
    }
}
