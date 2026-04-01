import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class DataStudioSessionTests: XCTestCase {
    func testBeginImportUsesSingleImporterStateAcrossDataStudioModes() {
        let session = DataStudioSession()

        session.showImportMenu()
        session.beginImport(kind: .sourceFiles)

        XCTAssertFalse(session.isImportMenuPresented)
        XCTAssertTrue(session.isImportPresented)
        XCTAssertEqual(session.pendingImportKind, .sourceFiles)

        session.isImportPresented = false
        session.showImportMenu()
        session.beginImport(kind: .workbook)

        XCTAssertFalse(session.isImportMenuPresented)
        XCTAssertTrue(session.isImportPresented)
        XCTAssertEqual(session.pendingImportKind, .workbook)
    }

    func testNewTemplateFlowUsesRecommendedCandidatesAndSavesTemplate() async {
        let client = MockSidecarClient()
        let session = DataStudioSession()
        session.configure(client: client)
        session.selectTemplateMode(.createNewTemplate)

        await session.handleImportedTemplateSample([URL(fileURLWithPath: "/tmp/raw_a.csv")])

        XCTAssertEqual(client.dataStudioSourcePreviewRequests.count, 1)
        XCTAssertNotNil(session.sourcePreview)
        XCTAssertFalse(session.selectedCandidateIDs.isEmpty)
        XCTAssertEqual(session.templateDraftLabel, "raw_a")

        await session.createTemplateFromDraft()

        XCTAssertEqual(client.dataStudioCreateTemplateRequests.count, 1)
        XCTAssertEqual(client.dataStudioCreateTemplateRequests.last?.label, "raw_a")
        XCTAssertEqual(
            Set(client.dataStudioCreateTemplateRequests.last?.acceptedCandidateIDs ?? []),
            Set(session.selectedCandidateIDs)
        )
        XCTAssertEqual(session.templateMode, .existingTemplate)
        XCTAssertEqual(session.selectedTemplateID, client.dataStudioTemplateResponse.id)
    }

    func testDataStudioBuildImportCompareExportAndPlotHandoff() async {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")
        let exportDirectoryURL = URL(fileURLWithPath: "/tmp/data_studio_exports", isDirectory: true)
        let client = MockSidecarClient()
        client.dataStudioWorkbookResponse = TestPayloads.dataStudioWorkbook(
            id: "workbook-1",
            path: outputWorkbookURL.path,
            label: "Primary Group"
        )
        client.dataStudioImportWorkbookHandler = { request in
            if request.workbookPath == "/tmp/second.xlsx" {
                return TestPayloads.dataStudioWorkbook(
                    id: "workbook-2",
                    path: request.workbookPath,
                    label: "Second Group"
                )
            }
            return TestPayloads.dataStudioWorkbook(path: request.workbookPath, label: "Imported Group")
        }

        var chosenFormat: ExportGraphicFormat?
        let session = DataStudioSession(
            chooseDirectory: { _, _ in exportDirectoryURL },
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL },
            chooseComparisonFigureFormat: { _, _ in
                chosenFormat = .tiff
                return .tiff
            },
            materializeComparisonOutputs: { sourceURLs, format in
                chosenFormat = format
                return sourceURLs.map { $0.deletingPathExtension().appendingPathExtension("tiff") }
            }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())
        session.selectedTemplateID = "builtin/tensile"

        await session.handleImportedSourceFiles([
            URL(fileURLWithPath: "/tmp/raw_a.csv"),
            URL(fileURLWithPath: "/tmp/raw_b.csv"),
        ])

        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.count, 1)
        XCTAssertEqual(client.dataStudioBuildWorkbookRequests.first?.templateID, "builtin/tensile")
        XCTAssertEqual(session.primaryWorkbook?.workbookURL, outputWorkbookURL)
        XCTAssertEqual(session.focusedWorkbook?.workbookURL, outputWorkbookURL)
        XCTAssertEqual(client.inspectRequests.first?.inputPath, outputWorkbookURL.path)
        XCTAssertEqual(client.renderRequests.first?.inputPath, outputWorkbookURL.path)

        await session.handleImportedWorkbooks([URL(fileURLWithPath: "/tmp/second.xlsx")])

        XCTAssertEqual(session.orderedWorkbooks.count, 2)
        XCTAssertEqual(client.dataStudioPreviewComparisonRequests.last?.workbookPaths.count, 2)
        XCTAssertEqual(session.comparisonSet?.recipes.count, 2)
        XCTAssertTrue(session.canExportComparison)

        var openedWorkbook: URL?
        var openedSheet: SheetValue?
        session.openInPlotHandler = { url, sheet in
            openedWorkbook = url
            openedSheet = sheet
        }

        session.setPrimaryWorkbook(id: "workbook-2")
        session.openPrimaryWorkbookInPlot()

        XCTAssertEqual(openedWorkbook?.path, "/tmp/second.xlsx")
        XCTAssertEqual(openedSheet, .name("Representative_Curve"))

        await session.exportComparisonBundle()

        XCTAssertEqual(client.dataStudioExportComparisonRequests.count, 1)
        XCTAssertEqual(session.comparisonExportDestinationURL, exportDirectoryURL)
        XCTAssertEqual(chosenFormat, .tiff)
        XCTAssertEqual(
            session.comparisonFigureItems.map(\.url.lastPathComponent),
            ["representative_curve.tiff", "strength_box.tiff"]
        )
        XCTAssertEqual(session.selectedComparisonFigure?.response.label, "Representative Curve Compare")
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
        session.apply(meta: TestPayloads.meta())

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
            importedPaths: ["/tmp/raw_a.csv"],
            templateDraftPath: "/tmp/raw_a.csv"
        )

        await session.restoreSession(from: payload)

        XCTAssertEqual(session.selectedTemplateID, "builtin/tensile")
        XCTAssertEqual(session.primaryWorkbookID, "workbook-1")
        XCTAssertEqual(session.focusedWorkbookID, "workbook-2")
        XCTAssertEqual(session.selectedRecipeID, "strength_box")
        XCTAssertEqual(client.dataStudioImportWorkbookRequests.count, 2)
        XCTAssertEqual(client.dataStudioSourcePreviewRequests.count, 1)
    }
}
