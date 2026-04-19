import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class DataStudioSessionTests: XCTestCase {
    private func assertImportFlow(
        _ session: DataStudioSession,
        equals expected: DataStudioImportFlowState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(session.importFlow, expected, file: file, line: line)
    }

    func testImportWizardUsesSinglePresentationStateAndStepTransitions() {
        let session = DataStudioSession()

        session.beginImportFlow()
        assertImportFlow(session, equals: .wizard(step: .kind))
        XCTAssertEqual(session.importWizardStep, .kind)

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
        assertImportFlow(session, equals: .wizard(step: .scope))
        XCTAssertEqual(session.importWizardStep, .scope)

        session.chooseImportDisposition(.addToCurrentSession)
        XCTAssertEqual(session.importWizardStep, .kind)

        session.importWizardStep = .resolver
        session.goBackInImportWizard()
        XCTAssertEqual(session.importWizardStep, .kind)
    }

    func testChooseImportKindDismissesWizardThenPresentsImporter() async {
        let session = DataStudioSession()
        session.beginImportFlow()

        assertImportFlow(session, equals: .wizard(step: .kind))

        session.chooseImportKind(.rawFiles)

        assertImportFlow(session, equals: .idle)

        try? await Task.sleep(nanoseconds: 20_000_000)

        assertImportFlow(session, equals: .importer(kind: .rawFiles))
    }

    func testExportAvailabilityExplainsBlockingStates() {
        let session = DataStudioSession()
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("sidecar") ?? false)

        let client = MockSidecarClient()
        session.configure(client: client)
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("Import workbook groups") ?? false)

        session.comparisonSet = TestPayloads.dataStudioComparisonSet()
        XCTAssertTrue(session.exportAvailability.isEnabled)
        XCTAssertNil(session.exportAvailability.reason)
    }

    func testUndoRestoresGroupCompareInclusion() {
        let session = DataStudioSession()
        let undoManager = UndoManager()
        session.attachUndoManager(undoManager)
        session.workbooks = [
            .init(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(id: "workbook-1", path: "/tmp/prepared.xlsx", label: "Prepared")
            ),
        ]
        session.groupStates = [
            .init(workbookPath: "/tmp/prepared.xlsx", displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]

        session.updateCompareInclusion(for: "/tmp/prepared.xlsx", includeInCompare: false)
        XCTAssertEqual(session.groupStates.first?.includeInCompare, false)

        undoManager.undo()
        XCTAssertEqual(session.groupStates.first?.includeInCompare, true)
    }

    func testImportFlowStartsAtChooserForEmptySessionAndScopeForNonEmptySession() {
        let session = DataStudioSession()

        session.beginImportFlow()
        assertImportFlow(session, equals: .wizard(step: .kind))

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
        assertImportFlow(session, equals: .wizard(step: .scope))
    }

    func testCancelledImportPanelDoesNotSetErrorAndResetsPendingImportState() {
        let session = DataStudioSession()
        session.pendingImportDisposition = .startNewSession
        session.pendingImportKind = .existingWorkbook
        session.importFlow = .importer(kind: .existingWorkbook)
        session.errorMessage = "Old import error"

        session.handleImportPanelFailure(CancellationError())

        XCTAssertNil(session.errorMessage)
        assertImportFlow(session, equals: .idle)
        XCTAssertEqual(session.pendingImportDisposition, .addToCurrentSession)
        XCTAssertEqual(session.pendingImportKind, .rawFiles)
    }

    func testRefreshTemplatesCancellationDoesNotSurfaceError() async {
        let client = MockSidecarClient()
        client.dataStudioTemplateListHandler = {
            throw CancellationError()
        }

        let session = DataStudioSession()
        session.configure(client: client)

        await session.refreshTemplates()

        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.currentActivity, .idle)
        XCTAssertTrue(session.templates.isEmpty)
    }

    func testCancelledImportAfterKindSelectionEndsImportFlow() async {
        let session = DataStudioSession()

        session.beginImportFlow()
        session.chooseImportKind(.existingWorkbook)
        try? await Task.sleep(nanoseconds: 20_000_000)
        assertImportFlow(session, equals: .importer(kind: .existingWorkbook))

        session.handleImportPanelFailure(CancellationError())

        assertImportFlow(session, equals: .idle)
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
        session.importFlow = .wizard(step: .kind)
        session.errorMessage = "Chooser warning"
        session.dismissImportChooser()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.pendingImportDisposition, .addToCurrentSession)
        XCTAssertEqual(session.pendingImportKind, .rawFiles)

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        assertImportFlow(session, equals: .wizard(step: .resolver))
        session.errorMessage = "Resolver warning"
        session.dismissImportResolver()

        XCTAssertNil(session.errorMessage)
        assertImportFlow(session, equals: .idle)
        XCTAssertNil(session.sourcePreview)
        XCTAssertTrue(session.importedSourceURLs.isEmpty)
    }

    func testCompactEmptyStateFlagsOnlyAppearWithoutGroups() {
        let session = DataStudioSession()
        XCTAssertTrue(session.showsCompactEmptyInspector)
        XCTAssertFalse(session.showsInspectorActions)
        XCTAssertTrue(session.orderedGroups.isEmpty)

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
        XCTAssertFalse(session.orderedGroups.isEmpty)
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
        XCTAssertEqual(client.dataStudioComparisonContextRequests.count, 1)
        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.first?.displayName, "prepared")
        XCTAssertEqual(session.plotSession.selectedFileURL?.path, "/tmp/data_studio_exports/primary-vs-second/primary-vs-second.xlsx")
    }

    func testComparisonContextFailureKeepsLastSuccessfulPreviewAndMarksSessionStale() async {
        let client = MockSidecarClient()
        var shouldFailRefresh = false
        client.dataStudioComparisonContextHandler = { request in
            if shouldFailRefresh {
                throw NSError(
                    domain: "DataStudioTest",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
                )
            }
            return TestPayloads.dataStudioComparisonContext()
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])
        let previousComparisonWorkbook = session.comparisonSet?.comparisonWorkbookPath
        let previousPreviewSource = session.plotSession.selectedFileURL?.path

        shouldFailRefresh = true
        session.updateDisplayName(for: "/tmp/prepared.xlsx", to: "Renamed Group")
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(session.comparisonSet?.comparisonWorkbookPath, previousComparisonWorkbook)
        XCTAssertEqual(session.plotSession.selectedFileURL?.path, previousPreviewSource)
        XCTAssertTrue(session.isPreviewStale)
        XCTAssertEqual(session.previewWarning, "Refresh failed, showing last successful preview.")
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
        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.count, 2)
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

        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.first?.displayName, "Renamed Group")
    }

    func testRawBuildUsesChosenWorkbookFilenameAsInitialDisplayName() async {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/E3.xlsx")
        let client = MockSidecarClient()
        client.dataStudioBuildWorkbookHandler = { request in
            XCTAssertEqual(request.groupName, "E3")
            return TestPayloads.dataStudioWorkbook(
                id: "workbook-1",
                path: request.outputPath,
                label: "Primary Group"
            )
        }
        let session = DataStudioSession(
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([
            URL(fileURLWithPath: "/tmp/raw_a.csv"),
            URL(fileURLWithPath: "/tmp/raw_b.csv"),
        ])

        XCTAssertEqual(session.orderedGroups.first?.state.displayName, "E3")
        XCTAssertEqual(session.focusTitle, "E3")
        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.first?.displayName, "E3")
    }

    func testExistingWorkbookImportUsesFilenameStemAsInitialDisplayName() async {
        let client = MockSidecarClient()
        client.dataStudioImportWorkbookHandler = { request in
            TestPayloads.dataStudioImportWorkbook(
                workbooks: [
                    TestPayloads.dataStudioWorkbook(
                        id: "workbook-1",
                        path: request.workbookPath,
                        label: "Primary Group"
                    ),
                ]
            )
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/E3.xlsx")])

        XCTAssertEqual(session.orderedGroups.first?.state.displayName, "E3")
        XCTAssertEqual(session.focusTitle, "E3")
        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.first?.displayName, "E3")

        session.updateDisplayName(for: "/tmp/E3.xlsx", to: "")
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(client.dataStudioComparisonContextRequests.last?.groupStates.first?.displayName, "E3")
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

        assertImportFlow(session, equals: .wizard(step: .resolver))
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

        assertImportFlow(session, equals: .wizard(step: .createTemplate))

        let draftName = session.templateDraftLabel
        let selectedCandidates = session.selectedCandidateIDs
        let selectedSuggestions = session.selectedSuggestionIDs
        session.returnToImportResolver()
        try? await Task.sleep(nanoseconds: 20_000_000)

        assertImportFlow(session, equals: .wizard(step: .resolver))
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

    func testResolverPresentationExplainsMissingTemplateSelection() async {
        let client = MockSidecarClient()
        client.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        session.selectedTemplateID = nil

        XCTAssertFalse(session.resolverPresentation.useSelectedTemplateAvailability.isEnabled)
        XCTAssertEqual(
            session.resolverPresentation.useSelectedTemplateAvailability.reason,
            "Choose a parse template before continuing."
        )
    }

    func testTemplateEditorPresentationUsesSingleSourceValuesLocationsAndSaveReasons() async throws {
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

        let curvePresentation = try XCTUnwrap(session.templateEditorPresentation.primaryCurveSuggestion)
        XCTAssertEqual(curvePresentation.values, ["X: Strain (%)", "Y: Stress (MPa)"])
        XCTAssertEqual(curvePresentation.location, "Sheet1 / Primary Data Block")
        XCTAssertEqual(session.templateEditorPresentation.previewCaption, session.createTemplatePreviewCaption)

        session.templateDraftLabel = ""
        XCTAssertFalse(session.templateEditorPresentation.saveTemplateAvailability.isEnabled)
        XCTAssertEqual(
            session.templateEditorPresentation.saveTemplateAvailability.reason,
            "Provide a parse template name before saving it."
        )

        session.templateDraftLabel = "New Template"
        session.selectedCandidateIDs = []
        XCTAssertFalse(session.templateEditorPresentation.saveTemplateAndContinueAvailability.isEnabled)
        XCTAssertEqual(
            session.templateEditorPresentation.saveTemplateAndContinueAvailability.reason,
            "Select at least one suggested or manual field before saving the parse template."
        )
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
        assertImportFlow(session, equals: .wizard(step: .resolver))
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
        assertImportFlow(session, equals: .idle)
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

        assertImportFlow(session, equals: .idle)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.first?.templateID, "builtin/tensile")
    }

    func testFocusedWorkbookNoticesMergePreviewWarningsWorkbookWarningsAndExclusions() {
        let session = DataStudioSession()
        let workbook = DataStudioWorkbookItem(
            id: "workbook-1",
            response: DataStudioWorkbookResponse(
                workbookID: "workbook-1",
                workbookPath: "/tmp/prepared.xlsx",
                label: "Prepared",
                templateMatch: TestPayloads.dataStudioWorkbook().templateMatch,
                sourceFiles: ["/tmp/raw_a.csv"],
                sheetNames: ["Representative_Curve"],
                preferredSheet: "Representative_Curve",
                parsedSampleCount: 1,
                failedSampleCount: 0,
                representativeFilename: "raw_a.csv",
                metrics: [],
                warnings: ["Workbook warning"],
                exclusions: ["Excluded sample"],
                samples: []
            )
        )
        session.workbooks = [workbook]
        session.groupStates = [
            .init(workbookPath: "/tmp/prepared.xlsx", displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]
        session.workbookPreviewByPath["/tmp/prepared.xlsx"] = DataStudioWorkbookPreviewResponse(
            workbookPath: "/tmp/prepared.xlsx",
            label: "Prepared",
            supported: true,
            unsupportedReason: "",
            totalSpecimenCount: 1,
            includedSpecimenCount: 1,
            excludedSpecimenCount: 0,
            representativeSpecimenId: nil,
            representativeFilename: nil,
            metrics: [],
            specimens: [],
            warnings: ["Preview warning", "Workbook warning"],
            suggestedExclusionIds: [],
            suggestionSupported: false,
            suggestionSupportReason: ""
        )

        let notices = session.focusedWorkbookNotices(for: workbook)

        XCTAssertEqual(notices.map(\.message), ["Preview warning", "Workbook warning", "Excluded sample"])
        XCTAssertEqual(notices.map(\.style), [.warning, .warning, .exclusion])
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
                optionsByTemplate: ["box": RenderOptionsPayload(stylePreset: "nature", palettePreset: "colorblind_safe")]
            ),
        ]

        session.newSession()

        XCTAssertTrue(session.orderedGroups.isEmpty)
        XCTAssertNil(session.focusedWorkbook)
        XCTAssertEqual(session.selectedFigureFamilyID, "strength")
        XCTAssertEqual(session.figurePreferences.first?.selectedTemplateID, "box")
    }

    func testAvailableFigureTemplatesUseBackendTemplateLabels() {
        let session = DataStudioSession()
        let baseMeta = TestPayloads.meta()
        let templates = baseMeta.templates.map { template in
            guard template.id == "box_strip" else {
                return template
            }
            return MetaTemplateSummary(
                id: template.id,
                label: "Backend Box Strip",
                description: template.description,
                category: template.category,
                presentationKind: template.presentationKind,
                defaultSize: template.defaultSize,
                allowedSizes: template.allowedSizes,
                editableOptions: template.editableOptions,
                defaultOptions: template.defaultOptions,
                availableStyles: template.availableStyles,
                availablePalettes: template.availablePalettes,
                canonicalID: template.canonicalID,
                role: template.role,
                lifecyclePolicy: template.lifecyclePolicy,
                implementationID: template.implementationID
            )
        }
        let meta = SidecarMetaResponse(
            version: baseMeta.version,
            defaults: baseMeta.defaults,
            sizes: baseMeta.sizes,
            styles: baseMeta.styles,
            palettes: baseMeta.palettes,
            templates: templates,
            templateIds: baseMeta.templateIds,
            sizeIds: baseMeta.sizeIds,
            palettePresetIds: baseMeta.palettePresetIds,
            visualThemes: baseMeta.visualThemes
        )

        session.apply(meta: meta, contract: TestPayloads.contract())
        session.comparisonSet = TestPayloads.dataStudioComparisonSetSharedMetricTemplate()
        session.selectedFigureFamilyID = "strength"

        XCTAssertEqual(session.availableFigureTemplates.first?.label, "Backend Box Strip")
    }

    func testDisplayedFigureFallsBackToRecommendedThemeAndPaletteWithoutStoredPreferences() async throws {
        let client = MockSidecarClient()
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.comparisonSet = TestPayloads.dataStudioComparisonSet()
        session.selectedFigureFamilyID = "strength"
        session.syncFigureSelection()

        try await session.refreshDisplayedFigure()

        XCTAssertEqual(session.currentFigureTemplateID, "box")
        XCTAssertEqual(session.plotSession.renderOptions.stylePreset, "nature")
        XCTAssertEqual(session.plotSession.renderOptions.palettePreset, "macarons")
        XCTAssertEqual(session.plotSession.renderOptions.visualThemeID, "macarons")
    }

    func testRestoreSessionMigratesLegacyGroupedBarSelections() async {
        let session = DataStudioSession()

        await session.restoreSession(
            from: DataStudioSessionResponse(
                version: 1,
                selectedTemplateID: "builtin/tensile",
                selectedWorkbookID: nil,
                primaryWorkbookID: nil,
                selectedRecipeID: "strength_grouped_bar_error",
                workbookPaths: [],
                comparisonRecipeIDs: ["strength_grouped_bar_error"],
                selectedFigureFamilyID: "strength",
                selectedFigureTemplateID: "grouped_bar_error",
                groupStates: [],
                specimenStates: [],
                figurePreferences: [
                    .init(
                        familyID: "strength",
                        selectedTemplateID: "grouped_bar_error",
                        optionsByTemplate: ["grouped_bar_error": RenderOptionsPayload(stylePreset: "nature", palettePreset: "colorblind_safe")]
                    ),
                ],
                importedPaths: [],
                templateDraftPath: nil
            )
        )

        XCTAssertEqual(session.selectedRecipeID, "strength_bar")
        XCTAssertEqual(session.selectedFigureTemplateID, "bar")
        XCTAssertEqual(session.figurePreferences.first?.selectedTemplateID, "bar")
        XCTAssertNotNil(session.figurePreferences.first?.optionsByTemplate["bar"])
    }

    func testExportAndOpenCurrentFigureInPlotUseCurrentFigureContext() async {
        let exportDirectoryURL = URL(fileURLWithPath: "/tmp/data_studio_exports", isDirectory: true)
        let client = MockSidecarClient()
        client.inspectHandler = { request in
            TestPayloads.inspectFile(path: request.inputPath)
        }
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
        session.plotSession.updateRenderOptions(policy: .immediate) {
            $0.yMin = 35.0
            $0.yMax = 80.0
            $0.yTickDensity = "sparse"
            $0.yTickEdgeLabels = "hide_min"
        }
        await waitUntil(
            {
                client.renderRequests.last?.template == "box" &&
                client.renderRequests.last?.options.yMin == 35.0 &&
                client.renderRequests.last?.options.yMax == 80.0 &&
                client.renderRequests.last?.options.yTickDensity == "sparse" &&
                client.renderRequests.last?.options.yTickEdgeLabels == "hide_min"
            },
            timeout: 3.0
        )
        session.openCurrentFigureInPlot()
        await session.exportComparisonBundle()

        XCTAssertEqual(openedURL?.lastPathComponent, "primary-vs-second.xlsx")
        XCTAssertEqual(openedSheet, .name("Strength_Replicates"))
        XCTAssertEqual(openedTemplateID, "box")
        XCTAssertEqual(openedOptions?.stylePreset, session.plotSession.renderOptions.stylePreset)
        XCTAssertEqual(openedOptions?.yMin, 35.0)
        XCTAssertEqual(openedOptions?.yMax, 80.0)
        XCTAssertEqual(openedOptions?.yTickDensity, "sparse")
        XCTAssertEqual(openedOptions?.yTickEdgeLabels, "hide_min")
        XCTAssertEqual(client.dataStudioExportComparisonRequests.count, 1)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.selectedRecipeIDs, ["representative_curve", "strength_box"])
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.stylePreset, session.plotSession.renderOptions.stylePreset)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.yMin, 35.0)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.yMax, 80.0)
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.yTickDensity, "sparse")
        XCTAssertEqual(client.dataStudioExportComparisonRequests.last?.figureOptionsByRecipeID["strength_box"]?.yTickEdgeLabels, "hide_min")
        XCTAssertEqual(session.latestComparisonWorkbookURL?.lastPathComponent, "primary-vs-second.xlsx")
        XCTAssertEqual(session.comparisonFilteredWorkbookItems.map(\.response.label), ["Primary", "Second"])
        XCTAssertEqual(
            session.comparisonFilteredWorkbookItems.map(\.response.representativeFilename),
            ["sample_2.csv", "sample_3.csv"]
        )
    }

    func testFigureFamilySwitchRestoresSavedAxisOverridesAndResetsUnsavedFamilies() async throws {
        let client = MockSidecarClient()
        client.inspectHandler = { request in
            TestPayloads.inspectFile(path: request.inputPath)
        }
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])
        await waitUntil({ session.plotSession.previewResponse != nil }, timeout: 3.0)

        session.plotSession.updateRenderOptions(policy: .immediate) {
            $0.xMin = -10.0
            $0.yMin = -10.0
            $0.xTickDensity = "sparse"
            $0.yTickEdgeLabels = "hide_both"
        }
        await waitUntil(
            {
                client.renderRequests.last?.template == "curve" &&
                client.renderRequests.last?.options.xMin == -10.0 &&
                client.renderRequests.last?.options.yMin == -10.0 &&
                client.renderRequests.last?.options.xTickDensity == "sparse" &&
                client.renderRequests.last?.options.yTickEdgeLabels == "hide_both"
            },
            timeout: 3.0
        )

        session.selectFigureFamily(id: "strength")
        await waitUntil(
            {
                session.currentFigureFamily?.id == "strength" &&
                session.plotSession.selectedTemplateID == "box" &&
                client.renderRequests.last?.template == "box"
            },
            timeout: 3.0
        )

        XCTAssertNil(session.plotSession.renderOptions.xMin)
        XCTAssertNil(session.plotSession.renderOptions.xMax)
        XCTAssertNil(session.plotSession.renderOptions.yMin)
        XCTAssertNil(session.plotSession.renderOptions.yMax)
        XCTAssertNil(session.plotSession.renderOptions.xTickDensity)
        XCTAssertNil(session.plotSession.renderOptions.yTickEdgeLabels)
        XCTAssertNil(client.renderRequests.last?.options.xMin)
        XCTAssertNil(client.renderRequests.last?.options.xMax)
        XCTAssertNil(client.renderRequests.last?.options.yMin)
        XCTAssertNil(client.renderRequests.last?.options.yMax)
        XCTAssertNil(client.renderRequests.last?.options.xTickDensity)
        XCTAssertNil(client.renderRequests.last?.options.yTickEdgeLabels)

        session.selectFigureFamily(id: "representative_curve")
        await waitUntil(
            {
                session.currentFigureFamily?.id == "representative_curve" &&
                session.plotSession.selectedTemplateID == "curve" &&
                session.plotSession.renderOptions.xMin == -10.0 &&
                session.plotSession.renderOptions.yMin == -10.0 &&
                session.plotSession.renderOptions.xTickDensity == "sparse" &&
                session.plotSession.renderOptions.yTickEdgeLabels == "hide_both" &&
                client.renderRequests.last?.template == "curve" &&
                client.renderRequests.last?.options.xMin == -10.0 &&
                client.renderRequests.last?.options.yMin == -10.0 &&
                client.renderRequests.last?.options.xTickDensity == "sparse" &&
                client.renderRequests.last?.options.yTickEdgeLabels == "hide_both"
            },
            timeout: 3.0
        )
    }

    func testRepresentativeCurveInspectorControlsRecoverFromPreviewTemplateWhenSelectionStateDrifts() async throws {
        let client = MockSidecarClient()
        client.inspectHandler = { request in
            TestPayloads.inspectFile(path: request.inputPath)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])
        await waitUntil(
            {
                session.currentFigureTemplateID == "curve" &&
                session.plotSession.previewResponse != nil &&
                session.plotSession.selectedTemplateSummary?.id == "curve"
            },
            timeout: 3.0
        )

        session.plotSession.selectedTemplateID = nil

        XCTAssertEqual(session.currentFigureTemplateID, "curve")
        XCTAssertEqual(session.plotSession.effectiveTemplateID, "curve")
        XCTAssertEqual(session.plotSession.selectedTemplateSummary?.id, "curve")
        XCTAssertTrue(session.plotSession.editableOptionIDs.contains("x_min"))
        XCTAssertTrue(session.plotSession.editableOptionIDs.contains("y_max"))

        session.plotSession.updateRenderOptions(policy: .immediate) {
            $0.xMin = -5.0
            $0.yMax = 85.0
        }

        await waitUntil(
            {
                client.renderRequests.last?.template == "curve" &&
                client.renderRequests.last?.options.xMin == -5.0 &&
                client.renderRequests.last?.options.yMax == 85.0
            },
            timeout: 3.0
        )
    }

    func testFigureFamilySwitchResetsUnsavedRangesWhenFamiliesReuseTheSameTemplate() async throws {
        let client = MockSidecarClient()
        client.dataStudioComparisonContextHandler = { _ in
            TestPayloads.dataStudioComparisonContextSharedMetricTemplate()
        }
        client.inspectHandler = { request in
            let base = TestPayloads.inspectFile(path: request.inputPath)
            return InspectFileResponse(
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: ["Representative_Curve", "Strength_Replicates", "Elongation_Replicates"],
                inspection: base.inspection,
                dataset: base.dataset
            )
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/prepared.xlsx")])
        await waitUntil({ session.plotSession.previewResponse != nil }, timeout: 3.0)

        session.selectFigureFamily(id: "strength")
        await waitUntil(
            {
                session.currentFigureFamily?.id == "strength" &&
                session.plotSession.selectedTemplateID == "box_strip" &&
                client.renderRequests.last?.template == "box_strip" &&
                client.renderRequests.last?.sheet == .name("Strength_Replicates")
            },
            timeout: 3.0
        )

        session.plotSession.updateRenderOptions(policy: .immediate) {
            $0.yMin = 60.0
            $0.yMax = 90.0
        }
        await waitUntil(
            {
                session.plotSession.renderOptions.yMin == 60.0 &&
                session.plotSession.renderOptions.yMax == 90.0 &&
                client.renderRequests.last?.options.yMin == 60.0 &&
                client.renderRequests.last?.options.yMax == 90.0
            },
            timeout: 3.0
        )

        session.selectFigureFamily(id: "elongation")
        await waitUntil(
            {
                session.currentFigureFamily?.id == "elongation" &&
                session.plotSession.selectedTemplateID == "box_strip" &&
                client.renderRequests.last?.template == "box_strip" &&
                client.renderRequests.last?.sheet == .name("Elongation_Replicates")
            },
            timeout: 3.0
        )

        XCTAssertNil(session.plotSession.renderOptions.yMin)
        XCTAssertNil(session.plotSession.renderOptions.yMax)
        XCTAssertNil(client.renderRequests.last?.options.yMin)
        XCTAssertNil(client.renderRequests.last?.options.yMax)

        session.selectFigureFamily(id: "strength")
        await waitUntil(
            {
                session.currentFigureFamily?.id == "strength" &&
                session.plotSession.selectedTemplateID == "box_strip" &&
                session.plotSession.renderOptions.yMin == 60.0 &&
                session.plotSession.renderOptions.yMax == 90.0 &&
                client.renderRequests.last?.template == "box_strip" &&
                client.renderRequests.last?.sheet == .name("Strength_Replicates") &&
                client.renderRequests.last?.options.yMin == 60.0 &&
                client.renderRequests.last?.options.yMax == 90.0
            },
            timeout: 3.0
        )
    }

    func testAutoKeepAllAppliesEligibleGroupsAndSupportsSingleUndo() async {
        let firstWorkbookPath = "/tmp/prepared.xlsx"
        let secondWorkbookPath = "/tmp/second.xlsx"
        let client = MockSidecarClient()
        client.dataStudioImportWorkbookHandler = { request in
            let workbookID = request.workbookPath == secondWorkbookPath ? "workbook-2" : "workbook-1"
            let label = request.workbookPath == secondWorkbookPath ? "Second Group" : "Prepared Group"
            return TestPayloads.dataStudioImportWorkbook(
                workbooks: [
                    TestPayloads.dataStudioWorkbook(
                        id: workbookID,
                        path: request.workbookPath,
                        label: label
                    ),
                ]
            )
        }
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        let undoManager = UndoManager()
        session.attachUndoManager(undoManager)
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([
            URL(fileURLWithPath: firstWorkbookPath),
            URL(fileURLWithPath: secondWorkbookPath),
        ])
        await waitUntil(
            {
                session.autoKeepAllAvailability.isEnabled &&
                session.specimenStates(for: firstWorkbookPath).count == 7 &&
                session.specimenStates(for: secondWorkbookPath).count == 7
            },
            timeout: 3.0
        )

        XCTAssertTrue(session.autoKeepAllAvailability.isEnabled)
        XCTAssertTrue(session.autoKeepAllHelp.contains("2 groups"))

        session.applySuggestedExclusionsToAllWorkbooks()
        await waitUntil(
            {
                session.specimenStates(for: firstWorkbookPath).filter { !$0.included }.count == 2 &&
                session.specimenStates(for: secondWorkbookPath).filter { !$0.included }.count == 2 &&
                client.dataStudioComparisonContextRequests.last?
                    .specimenStates
                    .filter { !$0.included }
                    .map(\.workbookPath)
                    .sorted() == [firstWorkbookPath, firstWorkbookPath, secondWorkbookPath, secondWorkbookPath]
            },
            timeout: 3.0
        )

        XCTAssertEqual(
            session.specimenStates(for: firstWorkbookPath).filter { !$0.included }.map(\.specimenId).sorted(),
            ["sample-1", "sample-7"]
        )
        XCTAssertEqual(
            session.specimenStates(for: secondWorkbookPath).filter { !$0.included }.map(\.specimenId).sorted(),
            ["sample-1", "sample-7"]
        )
        undoManager.undo()
        await waitUntil(
            {
                session.specimenStates(for: firstWorkbookPath).filter { !$0.included }.isEmpty &&
                session.specimenStates(for: secondWorkbookPath).filter { !$0.included }.isEmpty
            },
            timeout: 3.0
        )

        XCTAssertEqual(session.specimenStates(for: firstWorkbookPath).filter { !$0.included }.count, 0)
        XCTAssertEqual(session.specimenStates(for: secondWorkbookPath).filter { !$0.included }.count, 0)
    }

    func testSpecimenSuggestionWorkflowAppliesSuggestedExclusionsToPreviewAndComparisonRequests() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 7)
        XCTAssertEqual(
            Set(session.baselineWorkbookPreview(for: workbookPath)?.suggestedExclusionIds ?? []),
            ["sample-1", "sample-7"]
        )
        XCTAssertEqual(
            session.specimenFilterPresentation(for: workbookPath)
                .rankedRows
                .filter { $0.disposition == .keep }
                .count,
            5
        )

        session.applySuggestedExclusions(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 5)
        XCTAssertEqual(
            session.specimenStates(for: workbookPath)
                .filter { !$0.included }
                .map(\.specimenId)
                .sorted(),
            ["sample-1", "sample-7"]
        )
        XCTAssertEqual(
            client.dataStudioComparisonContextRequests.last?
                .specimenStates
                .filter { !$0.included }
                .map(\.specimenId)
                .sorted(),
            ["sample-1", "sample-7"]
        )
        XCTAssertTrue(session.isSpecimenFilterPresented)
    }

    func testSpecimenFilterModeInferenceTracksOffAutoAndManualStates() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.specimenFilterMode(for: workbookPath), .off)
        XCTAssertEqual(session.specimenFilterPresentation(for: workbookPath).title, "All Specimens")

        session.applySuggestedExclusions(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.specimenFilterMode(for: workbookPath), .auto)
        XCTAssertEqual(session.specimenFilterPresentation(for: workbookPath).title, "Auto Keep 5")

        session.updateDraftSpecimenInclusion(for: workbookPath, specimenId: "sample-1", included: true)
        XCTAssertTrue(session.hasPendingFilterChanges(for: workbookPath))
        XCTAssertEqual(session.specimenFilterMode(for: workbookPath), .auto)

        session.applyManualFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.specimenFilterMode(for: workbookPath), .manual)
        XCTAssertEqual(session.specimenFilterPresentation(for: workbookPath).title, "Manual Keep 6")
        XCTAssertEqual(
            session.specimenStates(for: workbookPath)
                .filter { !$0.included }
                .map(\.specimenId)
                .sorted(),
            ["sample-7"]
        )
    }

    func testSpecimenFilterPresentationRanksAutoKeepRowsAndMarksCutoff() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let presentation = session.specimenFilterPresentation(for: workbookPath)
        XCTAssertEqual(presentation.rankedRows.filter { $0.disposition == .keep }.count, 5)
        XCTAssertEqual(presentation.rankedRows.count, 7)
        XCTAssertEqual(
            Array(presentation.rankedRows.prefix(5).map(\.disposition)),
            Array(repeating: .keep, count: 5)
        )
        XCTAssertEqual(presentation.sortDescriptor.label, "Elongation")
        XCTAssertEqual(
            presentation.rankedRows.map(\.id),
            ["sample-6", "sample-5", "sample-4", "sample-3", "sample-2", "sample-7", "sample-1"]
        )
        XCTAssertEqual(
            presentation.advancedRows.map(\.specimenId),
            ["sample-7", "sample-6", "sample-5", "sample-4", "sample-3", "sample-2", "sample-1"]
        )
        XCTAssertTrue(presentation.rankedRows[4].showsCutoffAfter)
        XCTAssertEqual(
            Array(presentation.rankedRows.suffix(2).map(\.disposition)),
            Array(repeating: .out, count: 2)
        )
        XCTAssertEqual(presentation.rankedRows[0].rank, 1)
        XCTAssertLessThanOrEqual(
            presentation.rankedRows[0].distanceFromMeanScore ?? .infinity,
            presentation.rankedRows[1].distanceFromMeanScore ?? .infinity
        )
    }

    func testSpecimenFilterPresentationDisablesAutoKeepWhenBaselineIsUnsupported() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            let base = TestPayloads.dataStudioWorkbookPreview(path: request.workbookPath, label: "Prepared Group")
            return DataStudioWorkbookPreviewResponse(
                workbookPath: base.workbookPath,
                label: base.label,
                supported: false,
                unsupportedReason: "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation.",
                totalSpecimenCount: base.totalSpecimenCount,
                includedSpecimenCount: base.includedSpecimenCount,
                excludedSpecimenCount: base.excludedSpecimenCount,
                representativeSpecimenId: base.representativeSpecimenId,
                representativeFilename: base.representativeFilename,
                metrics: base.metrics,
                specimens: base.specimens,
                warnings: base.warnings,
                suggestedExclusionIds: [],
                suggestionSupported: false,
                suggestionSupportReason: "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation."
            )
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let presentation = session.specimenFilterPresentation(for: workbookPath)
        XCTAssertEqual(presentation.mode, .off)
        XCTAssertEqual(presentation.title, "All Specimens")
        XCTAssertFalse(presentation.autoFilterSupported)
        XCTAssertFalse(presentation.useAutoKeepAvailability.isEnabled)
        XCTAssertEqual(
            presentation.useAutoKeepAvailability.reason,
            "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation."
        )
        XCTAssertEqual(presentation.help, "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation.")
        XCTAssertEqual(presentation.autoFilterReason, "Auto Keep 5 needs at least 5 included specimens with Strength / Modulus / Elongation.")
    }

    func testSpecimenFilterPresentationProvidesTypedActionAvailabilityReasons() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        var presentation = session.specimenFilterPresentation(for: workbookPath)
        XCTAssertTrue(presentation.useAutoKeepAvailability.isEnabled)
        XCTAssertFalse(presentation.turnOffAvailability.isEnabled)
        XCTAssertEqual(presentation.turnOffAvailability.reason, "All specimens are already included.")
        XCTAssertFalse(presentation.applyDraftAvailability.isEnabled)
        XCTAssertEqual(
            presentation.applyDraftAvailability.reason,
            "Change inclusion or representative selection in Advanced before applying it."
        )
        XCTAssertFalse(presentation.useAutoRepresentativeAvailability.isEnabled)
        XCTAssertEqual(
            presentation.useAutoRepresentativeAvailability.reason,
            "The focused workbook is already using the auto representative."
        )
        XCTAssertFalse(presentation.revertDraftAvailability.isEnabled)
        XCTAssertEqual(
            presentation.revertDraftAvailability.reason,
            "There are no draft specimen edits to revert."
        )

        session.updateDraftRepresentativeSelection(for: workbookPath, specimenId: "sample-2")
        presentation = session.specimenFilterPresentation(for: workbookPath)
        XCTAssertTrue(presentation.applyDraftAvailability.isEnabled)
        XCTAssertTrue(presentation.useAutoRepresentativeAvailability.isEnabled)
        XCTAssertTrue(presentation.revertDraftAvailability.isEnabled)
    }

    func testManualDraftDoesNotChangeCommittedComparisonUntilApply() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)
        session.applySuggestedExclusions(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let comparisonRequestCountBeforeDraft = client.dataStudioComparisonContextRequests.count
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 5)

        session.updateDraftSpecimenInclusion(for: workbookPath, specimenId: "sample-1", included: true)

        XCTAssertTrue(session.hasPendingFilterChanges(for: workbookPath))
        XCTAssertTrue(session.draftSpecimenIncluded(for: workbookPath, specimenId: "sample-1"))
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 5)
        XCTAssertEqual(client.dataStudioComparisonContextRequests.count, comparisonRequestCountBeforeDraft)
        XCTAssertEqual(
            session.specimenStates(for: workbookPath)
                .filter { !$0.included }
                .map(\.specimenId)
                .sorted(),
            ["sample-1", "sample-7"]
        )

        session.applyManualFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 6)
        XCTAssertGreaterThan(client.dataStudioComparisonContextRequests.count, comparisonRequestCountBeforeDraft)
        XCTAssertEqual(
            client.dataStudioComparisonContextRequests.last?
                .specimenStates
                .filter { !$0.included }
                .map(\.specimenId)
                .sorted(),
            ["sample-7"]
        )
    }

    func testManualRepresentativeDraftDoesNotChangeCommittedComparisonUntilApply() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let comparisonRequestCountBeforeDraft = client.dataStudioComparisonContextRequests.count
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.representativeSpecimenId, "sample-3")

        session.updateDraftRepresentativeSelection(for: workbookPath, specimenId: "sample-2")

        XCTAssertTrue(session.hasPendingFilterChanges(for: workbookPath))
        XCTAssertEqual(session.draftRepresentativeSpecimenID(for: workbookPath), "sample-2")
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.representativeSpecimenId, "sample-3")
        XCTAssertEqual(client.dataStudioComparisonContextRequests.count, comparisonRequestCountBeforeDraft)

        session.applyManualFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.representativeSpecimenId, "sample-2")
        XCTAssertTrue(
            client.dataStudioComparisonContextRequests.last?
                .specimenStates
                .contains(where: { $0.specimenId == "sample-2" && $0.selectedAsRepresentative }) == true
        )
        XCTAssertFalse(
            client.dataStudioComparisonContextRequests.last?
                .specimenStates
                .contains(where: { $0.specimenId == "sample-3" && $0.selectedAsRepresentative }) == true
        )
    }

    func testClosingSpecimenFilterWithPendingDraftDiscardsWithoutConfirmation() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        session.updateDraftSpecimenInclusion(for: workbookPath, specimenId: "sample-1", included: false)
        XCTAssertTrue(session.hasPendingFilterChanges(for: workbookPath))

        session.closeSpecimenFilter()

        XCTAssertFalse(session.isSpecimenFilterPresented)
        XCTAssertFalse(session.hasPendingFilterChanges(for: workbookPath))
        XCTAssertEqual(session.specimenStates(for: workbookPath).filter { !$0.included }.count, 0)
        XCTAssertNil(session.specimenFilterPresentation(for: workbookPath).rowBadge)
    }

    func testImportPreloadsSpecimenFilterPreviewBeforePopoverOpens() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)], refreshContext: false)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(session.workbookPreview(for: workbookPath))
        XCTAssertNotNil(session.baselineWorkbookPreview(for: workbookPath))
        XCTAssertGreaterThanOrEqual(client.dataStudioWorkbookPreviewRequests.count, 2)
        XCTAssertFalse(session.isSpecimenFilterPresented)
    }

    func testBaselinePreviewStaysDistinctFromCommittedPreviewAfterAutoApply() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        client.dataStudioWorkbookPreviewHandler = { request in
            Self.makeSuggestedWorkbookPreviewResponse(from: request)
        }

        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])
        session.openSpecimenFilter(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.baselineWorkbookPreview(for: workbookPath)?.includedSpecimenCount, 7)
        XCTAssertEqual(
            Set(session.baselineWorkbookPreview(for: workbookPath)?.suggestedExclusionIds ?? []),
            ["sample-1", "sample-7"]
        )
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 7)

        session.applySuggestedExclusions(for: workbookPath)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(session.baselineWorkbookPreview(for: workbookPath)?.includedSpecimenCount, 7)
        XCTAssertEqual(
            Set(session.baselineWorkbookPreview(for: workbookPath)?.suggestedExclusionIds ?? []),
            ["sample-1", "sample-7"]
        )
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.includedSpecimenCount, 5)
        XCTAssertEqual(session.workbookPreview(for: workbookPath)?.suggestedExclusionIds.count, 0)
        XCTAssertTrue(client.dataStudioWorkbookPreviewRequests.contains(where: { $0.workbookPath == workbookPath && $0.specimenStates.isEmpty }))
        XCTAssertTrue(client.dataStudioWorkbookPreviewRequests.contains(where: {
            $0.workbookPath == workbookPath && Set($0.specimenStates.filter { !$0.included }.map(\.specimenId)) == ["sample-1", "sample-7"]
        }))
    }

    func testWorkbookPreviewRefreshIgnoresLateStaleResponseAfterRapidSpecimenToggles() async {
        let workbookPath = "/tmp/prepared.xlsx"
        let client = MockSidecarClient()
        let session = DataStudioSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        await session.handleImportedWorkbooks([URL(fileURLWithPath: workbookPath)])

        client.dataStudioWorkbookPreviewHandler = { request in
            let sampleAExcluded = request.specimenStates.contains {
                $0.workbookPath == workbookPath && $0.specimenId == "sample-a" && !$0.included
            }
            let delayNanoseconds: UInt64 = sampleAExcluded ? 220_000_000 : 20_000_000
            let deadline = ContinuousClock.now + .nanoseconds(Int(delayNanoseconds))
            while ContinuousClock.now < deadline {
                await Task.yield()
            }
            return Self.makeWorkbookPreviewResponse(from: request)
        }

        session.updateSpecimenInclusion(for: workbookPath, specimenId: "sample-a", included: false)
        session.updateSpecimenInclusion(for: workbookPath, specimenId: "sample-a", included: true)
        try? await Task.sleep(nanoseconds: 700_000_000)

        let finalPreview = session.workbookPreview(for: workbookPath)
        let sampleAIncluded = finalPreview?
            .specimens
            .first(where: { $0.specimenId == "sample-a" })?
            .included
        XCTAssertGreaterThanOrEqual(client.dataStudioWorkbookPreviewRequests.count, 2)
        XCTAssertEqual(sampleAIncluded, true)
        XCTAssertEqual(finalPreview?.includedSpecimenCount, 2)
        XCTAssertEqual(
            client.dataStudioComparisonContextRequests.last?
                .specimenStates
                .first(where: { $0.workbookPath == workbookPath && $0.specimenId == "sample-a" })?
                .included,
            true
        )
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
            specimenStates: [
                .init(
                    workbookPath: "/tmp/prepared.xlsx",
                    specimenId: "sample-a",
                    included: true,
                    selectedAsRepresentative: true
                ),
            ],
            figurePreferences: [
                .init(
                    familyID: "strength",
                    selectedTemplateID: "box",
                    optionsByTemplate: ["box": RenderOptionsPayload(size: "single_panel", stylePreset: "nature", palettePreset: "colorblind_safe")]
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
        XCTAssertEqual(session.specimenStates(for: "/tmp/prepared.xlsx").first?.selectedAsRepresentative, true)
        XCTAssertEqual(client.dataStudioImportWorkbookRequests.count, 2)
        XCTAssertEqual(client.dataStudioComparisonContextRequests.count, 1)
    }

    func testRevealFocusedWorkbookSurfacesMissingFileError() {
        let session = DataStudioSession()
        let workbook = DataStudioWorkbookItem(
            id: "workbook-1",
            response: TestPayloads.dataStudioWorkbook(path: "/tmp/missing-workbook.xlsx", label: "Prepared")
        )
        session.workbooks = [workbook]
        session.groupStates = [
            .init(workbookPath: workbook.response.workbookPath, displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]
        session.focusedWorkbookPath = workbook.response.workbookPath

        session.revealFocusedWorkbook()

        XCTAssertTrue(session.errorMessage?.contains("Couldn't find") ?? false)
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for DataStudioSession state")
    }

    private static func makeWorkbookPreviewResponse(from request: DataStudioWorkbookPreviewRequest) -> DataStudioWorkbookPreviewResponse {
        let base = TestPayloads.dataStudioWorkbookPreview(path: request.workbookPath, label: "Prepared Group")
        let excludedIDs = Set(
            request.specimenStates
                .filter { !$0.included }
                .map(\.specimenId)
        )
        let selectedRepresentativeSpecimenID = request.specimenStates.reversed().first(where: {
            $0.included && $0.selectedAsRepresentative
        })?.specimenId
        let specimens = base.specimens.map { specimen in
            let included = !excludedIDs.contains(specimen.specimenId)
            return DataStudioSpecimenPreviewResponse(
                specimenId: specimen.specimenId,
                label: specimen.label,
                filename: specimen.filename,
                sourcePath: specimen.sourcePath,
                included: included,
                metrics: specimen.metrics,
                warnings: specimen.warnings,
                exclusions: included ? [] : ["Excluded from compare"],
                miniCurvePoints: specimen.miniCurvePoints,
                triadComplete: specimen.triadComplete,
                suggestedExclusion: specimen.suggestedExclusion,
                compositeSignedScore: specimen.compositeSignedScore,
                distanceFromMeanScore: specimen.distanceFromMeanScore,
                scoreSide: specimen.scoreSide,
                autoRuleRole: specimen.autoRuleRole,
                eligibleForAutoFilter: specimen.eligibleForAutoFilter
            )
        }
        let includedCount = specimens.filter(\.included).count
        let representative = specimens.first(where: { $0.included && $0.specimenId == selectedRepresentativeSpecimenID })
            ?? specimens.first(where: \.included)

        return DataStudioWorkbookPreviewResponse(
            workbookPath: request.workbookPath,
            label: base.label,
            supported: base.supported,
            unsupportedReason: base.unsupportedReason,
            totalSpecimenCount: specimens.count,
            includedSpecimenCount: includedCount,
            excludedSpecimenCount: specimens.count - includedCount,
            representativeSpecimenId: representative?.specimenId,
            representativeFilename: representative?.filename,
            metrics: base.metrics,
            specimens: specimens,
            warnings: base.warnings,
            suggestedExclusionIds: [],
            suggestionSupported: base.suggestionSupported,
            suggestionSupportReason: base.suggestionSupportReason
        )
    }

    private static func makeSuggestedWorkbookPreviewResponse(from request: DataStudioWorkbookPreviewRequest) -> DataStudioWorkbookPreviewResponse {
        let excluded = Set(
            request.specimenStates
                .filter { !$0.included }
                .map(\.specimenId)
        )
        let selectedRepresentativeSpecimenID = request.specimenStates.reversed().first(where: {
            $0.included && $0.selectedAsRepresentative
        })?.specimenId
        return TestPayloads.dataStudioWorkbookPreviewWithSuggestedExclusions(
            path: request.workbookPath,
            label: "Prepared Group",
            excludedSpecimenIDs: excluded,
            selectedRepresentativeSpecimenID: selectedRepresentativeSpecimenID
        )
    }
}
