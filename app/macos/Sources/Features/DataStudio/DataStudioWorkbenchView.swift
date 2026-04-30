import SwiftUI
import UniformTypeIdentifiers

struct DataStudioWorkbenchView: View {
    @Bindable var session: DataStudioSession
    var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            DataStudioGroupRailView(session: session)
                .frame(width: ProWorkspaceMetrics.leftRailIdealWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 12)
                .padding(.vertical, 12)

            DataStudioPreviewWorkspaceView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            if isInspectorPresented {
                DataStudioPreparationInspectorView(session: session)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 10)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(MotionTokens.selection, value: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.rootBackground)
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .task {
            if session.templates.isEmpty {
                await session.refreshTemplates()
            }
        }
        .fileImporter(
            isPresented: importerBinding,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            session.handleImportPanelResult(result)
        }
        .sheet(isPresented: importWizardBinding) {
            DataStudioImportWizardSheet(session: session)
        }
        .sheet(isPresented: analysisBinding) {
            DataStudioAnalysisSheet(session: session)
        }
    }

    private var allowedImportTypes: [UTType] {
        switch session.pendingImportKind {
        case .rawFiles:
            return FileTypeCatalog.dataStudioRawInputs
        case .existingWorkbook:
            return FileTypeCatalog.dataStudioWorkbookInputs + [FileTypeCatalog.plotProject]
        }
    }

    private var importerBinding: Binding<Bool> {
        Binding(
            get: { session.importFlow.isImporterPresented },
            set: { _ in }
        )
    }

    private var importWizardBinding: Binding<Bool> {
        Binding(
            get: { session.importFlow.isWizardPresented },
            set: { isPresented in
                if isPresented {
                    session.beginImportFlow()
                } else {
                    session.dismissImportWizard()
                }
            }
        )
    }

    private var analysisBinding: Binding<Bool> {
        Binding(
            get: { session.isAnalysisPresented },
            set: { isPresented in
                if isPresented {
                    session.showAnalysis()
                } else {
                    session.dismissAnalysis()
                }
            }
        )
    }

}
