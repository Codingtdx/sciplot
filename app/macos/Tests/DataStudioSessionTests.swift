import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class DataStudioSessionTests: XCTestCase {
    func testImportFlowStartsAtChooserForEmptySessionAndScopeForNonEmptySession() {
        let session = DataStudioSession()

        session.beginImportFlow()
        XCTAssertTrue(session.isImportChooserPresented)
        XCTAssertFalse(session.isImportScopePresented)

        session.dismissImportChooser()
        session.workbooks = [
            .init(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(id: "workbook-1", path: "/tmp/prepared.xlsx", label: "Prepared")
            ),
        ]
        session.groupStates = [
            .init(workbookPath: "/tmp/prepared.xlsx", displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]

        session.beginImportFlow()
        XCTAssertTrue(session.isImportScopePresented)
        XCTAssertFalse(session.isImportChooserPresented)
    }

    func testCancelledImportPanelDoesNotSetErrorAndResetsPendingImportState() {
        let session = DataStudioSession()
        session.pendingImportDisposition = .startNewSession
        session.pendingImportKind = .existingWorkbook
        session.isImportPresented = true
        session.errorMessage = "Old import error"

        session.handleImportPanelFailure(CancellationError())

        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(session.isImportPresented)
        XCTAssertEqual(session.pendingImportDisposition, .addToCurrentSession)
        XCTAssertEqual(session.pendingImportKind, .rawFiles)
    }

    func testDismissingImportStepsClearsTransientImportErrors() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.errorMessage = "Transient import problem"
        session.beginImportFlow()
        XCTAssertNil(session.errorMessage)

        session.pendingImportDisposition = .startNewSession
        session.isImportChooserPresented = true
        session.errorMessage = "Chooser warning"
        session.dismissImportChooser()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.pendingImportDisposition, .addToCurrentSession)
        XCTAssertEqual(session.pendingImportKind, .rawFiles)

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        XCTAssertTrue(session.isImportResolverPresented)
        session.errorMessage = "Resolver warning"
        session.dismissImportResolver()

        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(session.isImportResolverPresented)
        XCTAssertNil(session.sourcePreview)
        XCTAssertTrue(session.importedSourceURLs.isEmpty)
    }

    func testCompactEmptyStateFlagsOnlyAppearWithoutGroups() {
        let session = DataStudioSession()
        XCTAssertTrue(session.showsCompactEmptyInspector)
        XCTAssertFalse(session.showsInspectorActions)
        XCTAssertEqual(session.groupRailEmptyHint, "Use the toolbar Import action to add workbook groups.")

        session.workbooks = [
            .init(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(id: "workbook-1", path: "/tmp/prepared.xlsx", label: "Prepared")
            ),
        ]
        session.groupStates = [
            .init(workbookPath: "/tmp/prepared.xlsx", displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]

        XCTAssertFalse(session.showsCompactEmptyInspector)
        XCTAssertTrue(session.showsInspectorActions)
        XCTAssertNil(session.groupRailEmptyHint)
    }

    func testImportingWorkbookDoesNotSurfaceMisclassifiedComparisonWorkbookWarning() async {
        let client = MockSidecarClient()
        client.inspectHandler = { request in
            if request.inputPath == "/tmp/data_studio_exports/primary-vs-second/primary-vs-second.xlsx" {
                throw NSError(
                    domain: "DataStudioTest",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "primary-vs-second.xlsx must contain exactly 1 representative curve group in Representative_Curve.",
                    ]
                )
            }
            return TestPayloads.inspectFile(path: request.inputPath)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])

        XCTAssertNil(session.errorMessage)
        XCTAssertNil(session.plotSession.errorMessage)
    }

    func testExistingWorkbookImportImmediatelyBuildsSingleGroupPreviewContext() async {
        let client = MockSidecarClient()
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])

        XCTAssertEqual(session.orderedGroups.count, 1)
        XCTAssertEqual(session.focusedWorkbook?.response.workbookPath, "/tmp/prepared.xlsx")
        XCTAssertEqual(session.includedGroups.count, 1)
        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.count, 1)
        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.last?.groupStates.first?.displayName, "Primary Group")
        XCTAssertEqual(session.plotSession.selectedFileURL?.path, "/tmp/data_studio_exports/primary-vs-second/primary-vs-second.xlsx")
    }

    func testComparisonWorkbookImportExpandsIntoReferencedWorkbookGroups() async {
        let client = MockSidecarClient()
        client.dataStudioImportWorkbookHandler = { request in
            if request.workbookPath == "/tmp/compare_bundle.xlsx" {
                return TestPayloads.dataStudioImportWorkbook(
                    workbooks: [
                        TestPayloads.dataStudioWorkbook(id: "workbook-1", path: "/tmp/prepared.xlsx", label: "Primary Group"),
                        TestPayloads.dataStudioWorkbook(id: "workbook-2", path: "/tmp/second.xlsx", label: "Second Group"),
                    ]
                )
            }
            return TestPayloads.dataStudioImportWorkbook()
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/compare_bundle.xlsx")])

        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.orderedGroups.map(\.workbook.response.workbookPath), ["/tmp/prepared.xlsx", "/tmp/second.xlsx"])
        XCTAssertEqual(session.includedGroups.count, 2)
        XCTAssertEqual(client.dataStudioImportWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.last?.groupStates.count, 2)
    }

    func testRawImportAutoMatchesBuiltinTemplateAndRespectsGroupStateInPreview() async {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")
        let client = MockSidecarClient()
        let session = DataStudioSession(
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([
            URL(fileURLWithPath: "/tmp/raw_a.csv"),
            URL(fileURLWithPath: "/tmp/raw_b.csv"),
        ])

        XCTAssertEqual(client.dataStudioSourcePreviewRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.first?.templateID, "builtin/tensile")
        XCTAssertEqual(session.orderedGroups.count, 1)

        session.updateDisplayName(for: "/tmp/prepared.xlsx", to: "Renamed Group")
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.last?.groupStates.first?.displayName, "Renamed Group")
    }

    func testUnresolvedRawImportPresentsResolverWithoutOpeningTemplateEditor() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(
                preview: preview.preview,
                matches: [
                    .init(
                        templateID: "builtin/tensile",
                        label: "Tensile",
                        family: "tensile",
                        confidence: 0.74,
                        reasons: ["Matched tensile-style headers, but summary metrics were incomplete."],
                        warnings: [],
                        matchedSheetNames: ["Sheet1"],
                        autoSelected: false
                    ),
                    .init(
                        templateID: "user/custom_curve",
                        label: "Custom Curve Template",
                        family: "curve",
                        confidence: 0.58,
                        reasons: ["Detected a compatible curve block, but units were ambiguous."],
                        warnings: ["Manual review recommended."],
                        matchedSheetNames: ["Sheet1"],
                        autoSelected: false
                    ),
                ]
            )
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])

        XCTAssertTrue(session.isImportResolverPresented)
        XCTAssertFalse(session.isCreateTemplateEditorPresented)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 0)
        XCTAssertEqual(session.selectedTemplateID, "builtin/tensile")
    }

    func testCreateTemplateEditorOpensFromResolverAndCancelReturnsToResolver() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertFalse(session.isImportResolverPresented)
        XCTAssertTrue(session.isCreateTemplateEditorPresented)

        let draftName = session.templateDraftLabel
        let selectedCandidates = session.selectedCandidateIDs
        let selectedSuggestions = session.selectedSuggestionIDs
        session.returnToImportResolver()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(session.isImportResolverPresented)
        XCTAssertFalse(session.isCreateTemplateEditorPresented)
        XCTAssertEqual(session.templateDraftLabel, draftName)
        XCTAssertEqual(session.selectedCandidateIDs, selectedCandidates)
        XCTAssertEqual(session.selectedSuggestionIDs, selectedSuggestions)
        XCTAssertNotNil(session.sourcePreview)
    }

    func testCreateTemplateEditorStartsWithSuggestionSelectionsAndHoverPreview() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertFalse(session.selectedSuggestionIDs.isEmpty)
        XCTAssertEqual(session.createTemplatePrimaryCurveSuggestion?.title, "Recommended Curve")
        XCTAssertEqual(session.selectedTemplateSummaryItems.first?.title, "Curve")

        session.setHoveredSuggestion(id: "sheet1:block0::curve_pair")
        XCTAssertEqual(Set(session.hoveredPreviewRanges.map(\.role)), Set(["x", "y"]))
        XCTAssertEqual(session.selectedPreviewBlockID, "sheet1:block0")
        XCTAssertEqual(session.createTemplatePreviewCaption, "Previewing Recommended Curve in Sheet1 / Primary Data Block")
    }

    func testTogglingSuggestionAndManualCandidateSelectionStayInSync() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(session.selectedSuggestionIDs.contains("sheet1:block0::curve_pair"))
        XCTAssertTrue(session.selectedCandidateIDs.contains("candidate:strain"))
        XCTAssertTrue(session.selectedCandidateIDs.contains("candidate:stress"))

        session.toggleSuggestion(id: "sheet1:block0::curve_pair")
        XCTAssertFalse(session.selectedSuggestionIDs.contains("sheet1:block0::curve_pair"))
        XCTAssertFalse(session.selectedCandidateIDs.contains("candidate:strain"))
        XCTAssertFalse(session.selectedCandidateIDs.contains("candidate:stress"))

        session.setCandidateSelection(id: "candidate:strain", isSelected: true)
        session.setCandidateSelection(id: "candidate:stress", isSelected: true)
        XCTAssertTrue(session.selectedSuggestionIDs.contains("sheet1:block0::curve_pair"))
    }

    func testSelectedTemplateSummaryItemsStayHumanReadable() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let summary = Dictionary(uniqueKeysWithValues: session.selectedTemplateSummaryItems.map { ($0.title, $0.value) })
        XCTAssertEqual(summary["Curve"], "X = Strain (%), Y = Stress (MPa)")
        XCTAssertEqual(summary["Metrics"], "Strength")
        XCTAssertEqual(summary["Structure"], "Header Row 2 · Unit Row 3")
    }

    func testSaveTemplateReturnsToResolverWithoutBuildingWorkbook() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        client.dataStudioTemplateResponse = TestPayloads.dataStudioTemplate(
            id: "user/new_template",
            label: "My Template"
        )
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)
        session.templateDraftLabel = "My Template"

        await session.saveTemplateDraft()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(client.dataStudioCreateTemplateRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 0)
        XCTAssertEqual(session.selectedTemplateID, "user/new_template")
        XCTAssertTrue(session.templates.contains(where: { $0.id == "user/new_template" }))
        XCTAssertTrue(session.isImportResolverPresented)
        XCTAssertFalse(session.isCreateTemplateEditorPresented)
    }

    func testSaveTemplateAndContinueImportBuildsWorkbook() async {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        client.dataStudioTemplateResponse = TestPayloads.dataStudioTemplate(
            id: "user/new_template",
            label: "My Template"
        )
        let session = DataStudioSession(
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)
        session.templateDraftLabel = "My Template"

        await session.saveTemplateAndContinueImport()

        XCTAssertEqual(client.dataStudioCreateTemplateRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.first?.templateID, "user/new_template")
        XCTAssertFalse(session.isImportResolverPresented)
        XCTAssertFalse(session.isCreateTemplateEditorPresented)
        XCTAssertEqual(session.orderedGroups.count, 1)
    }

    func testUsingSelectedTemplateFromResolverBuildsWorkbook() async {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession(
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.selectedTemplateID = "builtin/tensile"
        await session.importWithSelectedTemplate()

        XCTAssertFalse(session.isImportResolverPresented)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.first?.templateID, "builtin/tensile")
    }

    func testNewSessionClearsContentStateButPreservesFigurePreferences() {
        let session = DataStudioSession()
        session.workbooks = [
            .init(id: "workbook-1", response: TestPayloads.dataStudioWorkbook(id: "workbook-1", path: "/tmp/prepared.xlsx", label: "Prepared")),
        ]
        session.groupStates = [
            .init(workbookPath: "/tmp/prepared.xlsx", displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]
        session.focusedWorkbookPath = "/tmp/prepared.xlsx"
        session.selectedFigureFamilyID = "strength"
        session.selectedFigureTemplateID = "box"
        session.figurePreferences = [
            .init(
                familyID: "strength",
                selectedTemplateID: "box",
                optionsByTemplate: ["box": RenderOptionsPayload(stylePreset: "journal_calm", palettePreset: "aqua_graphite")]
            ),
        ]

        session.newSession()

        XCTAssertTrue(session.orderedGroups.isEmpty)
        XCTAssertNil(session.focusedWorkbook)
        XCTAssertEqual(session.selectedFigureFamilyID, "strength")
        XCTAssertEqual(session.figurePreferences.first?.selectedTemplateID, "box")
    }

    func testExportAndOpenCurrentFigureInPlotUseCurrentFigureContext() async {
        let exportDirectoryURL = URL(fileURLWithPath: "/tmp/data_studio_exports", isDirectory: true)
        let client = MockSidecarClient()
        client.dataStudioImportWorkbookHandler = { request in
            if request.workbookPath == "/tmp/second.xlsx" {
                return TestPayloads.dataStudioImportWorkbook(
                    workbooks: [TestPayloads.dataStudioWorkbook(id: "workbook-2", path: request.workbookPath, label: "Second Group")]
                )
            }
            return TestPayloads.dataStudioImportWorkbook(
                workbooks: [TestPayloads.dataStudioWorkbook(id: "workbook-1", path: request.workbookPath, label: "Primary Group")]
            )
        }

        var openedURL: URL?
        var openedSheet: SheetValue?
        var openedTemplateID: String?
        var openedOptions: RenderOptionsPayload?

        let session = DataStudioSession(
            chooseDirectory: { _, _ in exportDirectoryURL },
            chooseComparisonFigureFormat: { _, _ in .pdf },
            materializeComparisonOutputs: { sourceURLs, _ in sourceURLs }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.openInPlotHandler = { url, sheet, templateID, options in
            openedURL = url
            openedSheet = sheet
            openedTemplateID = templateID
            openedOptions = options
        }

        await session.handleImportedWorkbooks([
            URL(fileURLWithPath: "/tmp/prepared.xlsx"),
            URL(fileURLWithPath: "/tmp/second.xlsx"),
        ])

        session.selectFigureFamily(id: "strength")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.currentRecipe?.id, "strength_box")
        session.openCurrentFigureInPlot()
        await session.exportComparisonBundle()

        XCTAssertEqual(openedURL?.lastPathComponent, "primary-vs-second.xlsx")
        XCTAssertEqual(openedSheet, .name("Strength_Replicates"))
        XCTAssertEqual(openedTemplateID, "box")
        XCTAssertEqual(openedOptions?.stylePreset, session.plotSession.renderOptions.stylePreset)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.count, 1)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.selectedRecipeIDs, ["representative_curve", "strength_box"])
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.stylePreset, session.plotSession.renderOptions.stylePreset)
    }

    func testNormalizeAndRestoreSessionStateRoundTripsThroughValidatedSchema() async {
        let client = MockSidecarClient()
        client.dataStudioImportWorkbookHandler = { request in
            switch request.workbookPath {
            case "/tmp/prepared.xlsx":
                return TestPayloads.dataStudioImportWorkbook(
                    workbooks: [TestPayloads.dataStudioWorkbook(id: "workbook-1", path: request.workbookPath, label: "Primary Group")]
                )
            case "/tmp/second.xlsx":
                return TestPayloads.dataStudioImportWorkbook(
                    workbooks: [TestPayloads.dataStudioWorkbook(id: "workbook-2", path: request.workbookPath, label: "Second Group")]
                )
            default:
                return TestPayloads.dataStudioImportWorkbook(
                    workbooks: [TestPayloads.dataStudioWorkbook(path: request.workbookPath, label: "Imported Group")]
                )
            }
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        let normalized = await session.normalizeSessionPayload()
        XCTAssertNotNil(normalized)

        let payload = DataStudioSessionResponse(
            version: 1,
            selectedTemplateID: "builtin/tensile",
            selectedWorkbookID: "workbook-2",
            primaryWorkbookID: "workbook-1",
            selectedRecipeID: "strength_box",
            workbookPaths: ["/tmp/prepared.xlsx", "/tmp/second.xlsx"],
            comparisonRecipeIDs: ["representative_curve", "strength_box"],
            selectedFigureFamilyID: "strength",
            selectedFigureTemplateID: "box",
            groupStates: [
                .init(workbookPath: "/tmp/prepared.xlsx", displayName: "A", includeInCompare: true, sortOrder: 1),
                .init(workbookPath: "/tmp/second.xlsx", displayName: "B", includeInCompare: true, sortOrder: 0),
            ],
            figurePreferences: [
                .init(
                    familyID: "strength",
                    selectedTemplateID: "box",
                    optionsByTemplate: ["box": RenderOptionsPayload(size: "single_panel", stylePreset: "journal_calm", palettePreset: "aqua_graphite")]
                ),
            ],
            importedPaths: ["/tmp/raw_a.csv"],
            templateDraftPath: "/tmp/raw_a.csv"
        )

        await session.restoreSession(from: payload)

        XCTAssertEqual(session.selectedTemplateID, "builtin/tensile")
        XCTAssertEqual(session.focusedWorkbook?.response.workbookPath, "/tmp/second.xlsx")
        XCTAssertEqual(session.selectedFigureFamilyID, "strength")
        XCTAssertEqual(session.currentFigureTemplateID, "box")
        XCTAssertEqual(session.orderedGroups.map { $0.state.displayName }, ["B", "A"])
        XCTAssertEqual(client.dataStudioImportWorkbookRequests.count, 2)
        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.count, 1)
    }
}
