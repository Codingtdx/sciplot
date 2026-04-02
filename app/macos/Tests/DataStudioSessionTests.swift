import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class DataStudioSessionTests: XCTestCase {
    func testImportFlowStartsAtKindForEmptySessionAndScopeForNonEmptySession() {
        let session = DataStudioSession()

        session.beginImportFlow()
        XCTAssertTrue(session.isImportFlowPresented)
        XCTAssertEqual(session.importFlowStep, .kind)

        session.dismissImportFlow()
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
        XCTAssertTrue(session.isImportFlowPresented)
        XCTAssertEqual(session.importFlowStep, .scope)
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
                return TestPayloads.dataStudioWorkbook(id: "workbook-2", path: request.workbookPath, label: "Second Group")
            }
            return TestPayloads.dataStudioWorkbook(id: "workbook-1", path: request.workbookPath, label: "Primary Group")
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
                return TestPayloads.dataStudioWorkbook(id: "workbook-1", path: request.workbookPath, label: "Primary Group")
            case "/tmp/second.xlsx":
                return TestPayloads.dataStudioWorkbook(id: "workbook-2", path: request.workbookPath, label: "Second Group")
            default:
                return TestPayloads.dataStudioWorkbook(path: request.workbookPath, label: "Imported Group")
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
