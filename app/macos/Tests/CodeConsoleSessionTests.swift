import Foundation
import XCTest
@testable import SciPlotMac

@MainActor
final class CodeConsoleSessionTests: XCTestCase {
    func testExportAvailabilityExplainsBlockingStates() {
        let session = CodeConsoleSession()
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("Run code to generate PDF figures") ?? false)

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("Run code to generate PDF figures") ?? false)

        session.latestRunResponse = TestPayloads.codeConsoleRun()
        XCTAssertTrue(session.exportAvailability.isEnabled)
        XCTAssertNil(session.exportAvailability.reason)
    }

    func testEditorSourceAndOutputPresentationsExplainBlockingStates() {
        let session = CodeConsoleSession()

        XCTAssertFalse(session.editorPresentation.refreshPromptAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.refreshPromptAvailability.reason?.contains("sidecar") ?? false)
        XCTAssertFalse(session.editorPresentation.copyPromptAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.copyPromptAvailability.reason?.contains("generate the external AI prompt") ?? false)
        XCTAssertFalse(session.editorPresentation.restoreStarterAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.restoreStarterAvailability.reason?.contains("Refresh the bound context") ?? false)
        XCTAssertFalse(session.editorPresentation.runAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.runAvailability.reason?.contains("sidecar") ?? false)

        XCTAssertFalse(session.sourceActionsPresentation.openSourceAvailability.isEnabled)
        XCTAssertTrue(session.sourceActionsPresentation.openSourceAvailability.reason?.contains("Bind a dataset") ?? false)
        XCTAssertFalse(session.outputsPresentation.revealLatestOutputAvailability.isEnabled)
        XCTAssertTrue(session.outputsPresentation.revealLatestOutputAvailability.reason?.contains("Run code or export figures") ?? false)
        XCTAssertFalse(session.outputsPresentation.openSelectedGeneratedFileAvailability.isEnabled)
        XCTAssertTrue(session.outputsPresentation.openSelectedGeneratedFileAvailability.reason?.contains("Run code to generate files") ?? false)

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        session.configure(client: MockSidecarClient())
        session.promptText = "prompt"
        session.starterCode = "print('starter')"
        session.editorText = "print('run')"

        XCTAssertTrue(session.editorPresentation.refreshPromptAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.copyPromptAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.restoreStarterAvailability.isEnabled)
        XCTAssertTrue(session.editorPresentation.runAvailability.isEnabled)
        XCTAssertTrue(session.sourceActionsPresentation.openSourceAvailability.isEnabled)

        session.latestRunResponse = TestPayloads.codeConsoleRun()
        XCTAssertTrue(session.outputsPresentation.revealLatestOutputAvailability.isEnabled)
        XCTAssertTrue(session.outputsPresentation.openSelectedGeneratedFileAvailability.isEnabled)
        XCTAssertTrue(session.outputsPresentation.revealSelectedGeneratedFileAvailability.isEnabled)
    }

    func testExportAvailabilityExplainsLatestRunWithoutPDFFigures() {
        let session = CodeConsoleSession()
        session.latestRunResponse = CodeConsoleRunResponse(
            status: "succeeded",
            exitCode: 0,
            durationSeconds: 0.2,
            stdout: "",
            stderr: "",
            runDir: "/tmp/code_console/run-2",
            outputDir: "/tmp/code_console/run-2/outputs",
            scriptPath: "/tmp/code_console/run-2/user_code.py",
            promptPath: "/tmp/code_console/run-2/external_ai_prompt.txt",
            contextPath: "/tmp/code_console/run-2/context.json",
            stdoutPath: "/tmp/code_console/run-2/stdout.txt",
            stderrPath: "/tmp/code_console/run-2/stderr.txt",
            generatedFiles: [
                .init(
                    path: "/tmp/code_console/run-2/outputs/fit_table.csv",
                    name: "fit_table.csv",
                    fileType: "csv",
                    sizeBytes: 256
                ),
            ]
        )

        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("did not generate any PDF figures") ?? false)
    }

    func testCodeConsoleContextRefreshesAndRunsWithBoundPlotState() async {
        let plot = PlotSession()
        plot.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .name("Representative_Curve")
        plot.selectedTemplateID = "curve"
        plot.renderOptions.size = "60x55"

        let dataStudio = DataStudioSession()
        dataStudio.workbooks = [
            .init(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(
                    id: "workbook-1",
                    path: "/tmp/prepared.xlsx",
                    label: "Prepared"
                )
            ),
        ]
        dataStudio.groupStates = [
            .init(
                workbookPath: "/tmp/prepared.xlsx",
                displayName: "Prepared",
                includeInCompare: true,
                sortOrder: 0
            ),
        ]
        dataStudio.focusedWorkbookPath = "/tmp/prepared.xlsx"

        let client = MockSidecarClient()
        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())

        session.refreshContext(plot: plot, dataStudio: dataStudio)
        await session.refreshCurrentContext()

        XCTAssertEqual(session.availableBindings.count, 2)
        XCTAssertEqual(session.selectedSourceFilename, "sample.csv")
        XCTAssertTrue(session.promptText.contains("src.code_console_runtime"))
        XCTAssertTrue(session.editorText.contains("console.save_figure"))
        XCTAssertFalse(session.boundContext.isEmpty)
        XCTAssertEqual(client.codeConsoleContextRequests.last?.template, "curve")

        session.editorText = "print('hello code console')"
        await session.runCurrentCode()

        XCTAssertEqual(client.codeConsoleRunRequests.count, 1)
        XCTAssertEqual(session.latestRunResponse?.status, "succeeded")
        XCTAssertEqual(session.selectedGeneratedFile?.name, "sample.pdf")
        XCTAssertEqual(session.latestRunResponse?.generatedFiles.count, 2)
        XCTAssertEqual(session.liveStatusSymbol, "checkmark.circle.fill")
    }

    func testCodeConsoleExportUsesOnlyLatestRunPDFFigures() async {
        let client = MockSidecarClient()
        var callOrder: [String] = []
        var chooserSuggestedName: String?
        var chooserIsMultiOutput: Bool?
        var materializedSourceURLs: [URL] = []
        let destinationURL = URL(fileURLWithPath: "/tmp/user_exports/code-console-final.pdf")

        let session = CodeConsoleSession(
            chooseExportFormat: { isMultiOutput in
                callOrder.append("format")
                chooserIsMultiOutput = isMultiOutput
                return .pdf
            },
            chooseExportDestination: { suggestedName, isMultiOutput, format in
                callOrder.append("destination")
                chooserSuggestedName = suggestedName
                chooserIsMultiOutput = isMultiOutput
                XCTAssertEqual(format, .pdf)
                return destinationURL
            },
            materializeExport: { sourceURLs, destination in
                materializedSourceURLs = sourceURLs
                XCTAssertEqual(destination, destinationURL)
                return [destination]
            }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await session.refreshCurrentContext()
        session.editorText = "print('hello code console')"
        await session.runCurrentCode()

        session.exportCurrentOutputs()

        XCTAssertEqual(callOrder, ["format", "destination"])
        XCTAssertEqual(chooserSuggestedName, "sample.pdf")
        XCTAssertEqual(chooserIsMultiOutput, false)
        XCTAssertEqual(materializedSourceURLs.map(\.lastPathComponent), ["sample.pdf"])
        XCTAssertEqual(session.latestExportItems.map(\.label), ["code-console-final.pdf"])
    }

    func testCodeConsoleProjectRoundtripKeepsNotebookArtifactsWithoutRerun() {
        let session = CodeConsoleSession()
        session.latestRunResponse = TestPayloads.codeConsoleRun()
        session.selectedGeneratedFilePath = "/tmp/code_console/run-1/outputs/sample.pdf"

        let payload = session.buildProjectPayload(projectDisplayName: "Notebook Artifacts")

        XCTAssertEqual(payload?.latestRun?.notebookArtifacts.first?.artifactID, "artifact:code_console:run-1:1")

        let restored = CodeConsoleSession()
        restored.restoreProjectPayload(
            payload!,
            plot: PlotSession(),
            dataStudio: DataStudioSession()
        )

        XCTAssertEqual(restored.latestRunResponse?.notebookArtifacts.first?.sourceGraphNodeID, "code_console:notebook_output:1")
        XCTAssertEqual(restored.latestRunResponse?.generatedFiles.first?.name, "sample.pdf")
    }

    func testContextRefreshCancellationDoesNotSurfaceError() async {
        let client = MockSidecarClient()
        client.codeConsoleContextHandler = { _ in
            throw CancellationError()
        }

        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))

        await session.refreshCurrentContext()

        XCTAssertNil(session.errorMessage)
        XCTAssertNil(session.contextResponse)
    }

    func testCodeConsoleExportCanMaterializeTIFFOutput() {
        var callOrder: [String] = []
        var chooserSuggestedName: String?
        var materializedDestination: URL?
        let destinationURL = URL(fileURLWithPath: "/tmp/user_exports/code-console-final.tiff")

        let session = CodeConsoleSession(
            chooseExportFormat: { isMultiOutput in
                callOrder.append("format")
                XCTAssertFalse(isMultiOutput)
                return .tiff
            },
            chooseExportDestination: { suggestedName, _, format in
                callOrder.append("destination")
                chooserSuggestedName = suggestedName
                XCTAssertEqual(format, .tiff)
                return destinationURL
            },
            materializeExport: { _, destination in
                materializedDestination = destination
                return [destination]
            }
        )
        session.latestRunResponse = TestPayloads.codeConsoleRun()

        session.exportCurrentOutputs()

        XCTAssertEqual(callOrder, ["format", "destination"])
        XCTAssertEqual(chooserSuggestedName, "sample.tiff")
        XCTAssertEqual(materializedDestination, destinationURL)
        XCTAssertEqual(session.latestExportItems.map(\.label), ["code-console-final.tiff"])
    }

    func testCodeConsoleMultiFigureExportUsesBoundSourceStemAndStableLatestExportItems() {
        var chooserSuggestedName: String?
        var chooserIsMultiOutput: Bool?
        var materializedSourceURLs: [URL] = []
        let session = CodeConsoleSession(
            chooseExportFormat: { isMultiOutput in
                chooserIsMultiOutput = isMultiOutput
                return .pdf
            },
            chooseExportDestination: { suggestedName, isMultiOutput, _ in
                chooserSuggestedName = suggestedName
                chooserIsMultiOutput = isMultiOutput
                return URL(fileURLWithPath: "/tmp/user_exports/sample_code_console.pdf")
            },
            materializeExport: { sourceURLs, destination in
                materializedSourceURLs = sourceURLs
                return [
                    destination.deletingLastPathComponent().appendingPathComponent("sample_code_console_storage.pdf"),
                    destination.deletingLastPathComponent().appendingPathComponent("sample_code_console_loss.pdf"),
                ]
            }
        )
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        session.latestRunResponse = CodeConsoleRunResponse(
            status: "succeeded",
            exitCode: 0,
            durationSeconds: 0.3,
            stdout: "",
            stderr: "",
            runDir: "/tmp/code_console/run-3",
            outputDir: "/tmp/code_console/run-3/outputs",
            scriptPath: "/tmp/code_console/run-3/user_code.py",
            promptPath: "/tmp/code_console/run-3/external_ai_prompt.txt",
            contextPath: "/tmp/code_console/run-3/context.json",
            stdoutPath: "/tmp/code_console/run-3/stdout.txt",
            stderrPath: "/tmp/code_console/run-3/stderr.txt",
            generatedFiles: [
                .init(
                    path: "/tmp/code_console/run-3/outputs/storage.pdf",
                    name: "storage.pdf",
                    fileType: "pdf",
                    sizeBytes: 1024
                ),
                .init(
                    path: "/tmp/code_console/run-3/outputs/loss.pdf",
                    name: "loss.pdf",
                    fileType: "pdf",
                    sizeBytes: 980
                ),
                .init(
                    path: "/tmp/code_console/run-3/outputs/fit_table.csv",
                    name: "fit_table.csv",
                    fileType: "csv",
                    sizeBytes: 256
                ),
            ]
        )

        session.exportCurrentOutputs()

        XCTAssertEqual(chooserIsMultiOutput, true)
        XCTAssertEqual(chooserSuggestedName, "sample_code_console.pdf")
        XCTAssertEqual(materializedSourceURLs.map(\.lastPathComponent), ["storage.pdf", "loss.pdf"])
        XCTAssertEqual(
            session.latestExportItems.map(\.label),
            ["sample_code_console_storage.pdf", "sample_code_console_loss.pdf"]
        )
    }

    func testRevealLatestOutputSurfacesMissingManagedOutputFolderError() {
        let session = CodeConsoleSession()
        session.latestRunResponse = CodeConsoleRunResponse(
            status: "succeeded",
            exitCode: 0,
            durationSeconds: 0.2,
            stdout: "",
            stderr: "",
            runDir: "/tmp/code_console/run-missing",
            outputDir: "/tmp/code_console/run-missing/outputs",
            scriptPath: "/tmp/code_console/run-missing/user_code.py",
            promptPath: "/tmp/code_console/run-missing/external_ai_prompt.txt",
            contextPath: "/tmp/code_console/run-missing/context.json",
            stdoutPath: "/tmp/code_console/run-missing/stdout.txt",
            stderrPath: "/tmp/code_console/run-missing/stderr.txt",
            generatedFiles: []
        )

        session.revealLatestOutput()

        XCTAssertTrue(session.errorMessage?.contains("Couldn't find") ?? false)
    }

    func testContextRefreshDebouncesRapidBindingChangesToLatestRequest() async {
        let plot = PlotSession()
        plot.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .index(0)
        plot.selectedTemplateID = "curve"

        let client = MockSidecarClient()
        client.codeConsoleContextHandler = { request in
            try await Task.sleep(nanoseconds: 60_000_000)
            let base = TestPayloads.codeConsoleContext(path: request.inputPath)
            return CodeConsoleContextResponse(
                contextID: base.contextID,
                inputPath: base.inputPath,
                sheet: request.sheet,
                sheetNames: base.sheetNames,
                inspection: base.inspection,
                dataset: base.dataset,
                template: base.template,
                options: base.options,
                promptText: base.promptText,
                starterCode: base.starterCode,
                sourceKind: base.sourceKind,
                sourceLabel: base.sourceLabel
            )
        }

        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())

        session.refreshContext(plot: plot, dataStudio: DataStudioSession())
        session.setSelectedSheet(.name("Strength_Box"))
        session.setSelectedSheet(.name("Representative_Curve"))

        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(client.codeConsoleContextRequests.count, 1)
        XCTAssertEqual(client.codeConsoleContextRequests.last?.sheet, .name("Representative_Curve"))
        XCTAssertEqual(session.contextResponse?.sheet, .name("Representative_Curve"))
    }

    func testSheetPickerSelectionRefreshesBoundContextWithLatestSheet() async {
        let plot = PlotSession()
        plot.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .name("Source")
        plot.selectedTemplateID = "curve"

        let client = MockSidecarClient()
        client.codeConsoleContextHandler = { request in
            let base = TestPayloads.codeConsoleContext(path: request.inputPath)
            return CodeConsoleContextResponse(
                contextID: base.contextID,
                inputPath: base.inputPath,
                sheet: request.sheet,
                sheetNames: ["Source", "Transformed", "Fit"],
                inspection: base.inspection,
                dataset: base.dataset,
                template: base.template,
                options: base.options,
                promptText: base.promptText,
                starterCode: base.starterCode,
                sourceKind: base.sourceKind,
                sourceLabel: base.sourceLabel
            )
        }

        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())
        session.refreshContext(plot: plot, dataStudio: DataStudioSession())
        await session.refreshCurrentContext()

        session.setSelectedSheet(.name("Fit"))
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(session.availableSheets, [.name("Source"), .name("Transformed"), .name("Fit")])
        XCTAssertEqual(client.codeConsoleContextRequests.last?.sheet, .name("Fit"))
        XCTAssertEqual(session.contextResponse?.sheet, .name("Fit"))
        XCTAssertTrue(session.boundContext.contains { $0.id == "sheet" && $0.value == "Fit" })
    }

    func testAsyncLatestTaskCoordinatorExecutesLatestOperationOnly() async {
        let coordinator = AsyncLatestTaskCoordinator()
        var executedRevisions: [Int] = []

        coordinator.schedule(delayNanoseconds: 120_000_000) { revision in
            executedRevisions.append(revision)
        }
        coordinator.schedule { revision in
            executedRevisions.append(revision)
        }

        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(executedRevisions, [2])
    }

    func testKeyedAsyncLatestTaskCoordinatorMaintainsPerKeyLatestWriteWins() async {
        let coordinator = KeyedAsyncLatestTaskCoordinator<String>()
        var events: [String] = []

        coordinator.schedule(for: "alpha", delayNanoseconds: 120_000_000) { key, revision in
            events.append("\(key)-\(revision)")
        }
        coordinator.schedule(for: "alpha") { key, revision in
            events.append("\(key)-\(revision)")
        }
        coordinator.schedule(for: "beta") { key, revision in
            events.append("\(key)-\(revision)")
        }

        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertTrue(events.contains("alpha-2"))
        XCTAssertTrue(events.contains("beta-1"))
        XCTAssertFalse(events.contains("alpha-1"))
    }
}
