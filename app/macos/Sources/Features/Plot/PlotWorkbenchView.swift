import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.selectedSourceFilename != nil {
                topSourceBar
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                PlotTemplateView(session: session)
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)

                PlotRefineView(session: session)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotDocumentInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.handleImportedDocument(first)
                }
            case let .failure(error):
                if isUserCancellationError(error) {
                    session.errorMessage = nil
                } else {
                    session.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: bindingForDataWorkbook) {
            PlotDataWorkbookSheet(session: session)
        }
    }

    private var topSourceBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(session.selectedSourceFilename ?? "")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            if session.selectedFileURL != nil {
                Picker("Sheet", selection: selectedSheetBinding) {
                    ForEach(session.availableSheets, id: \.self) { sheet in
                        Text(sheet.displayName).tag(sheet)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
            }

            Button("Data") {
                session.showDataWorkbook()
            }
            .buttonStyle(.bordered)
            .disabled(!session.dataWorkbookAvailability.isEnabled)
            .help(session.dataWorkbookAvailability.reason ?? "Open the Data Workbook.")

            Image(systemName: session.liveStatusSymbol)
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating,
                    value: session.isInspecting || session.isPreviewing
                )
                .font(.headline)
                .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange)
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var bindingForDataWorkbook: Binding<Bool> {
        Binding(
            get: { session.isDataWorkbookPresented },
            set: { session.isDataWorkbookPresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}
