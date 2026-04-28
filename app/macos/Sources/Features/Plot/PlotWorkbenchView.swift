import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            GeometryReader { geometry in
                let sourceRailDensity: PlotSourceRailDensity =
                    geometry.size.width < PlotWorkspaceLayoutPolicy.sourceRailCollapseThreshold
                    ? PlotSourceRailDensity.compact
                    : PlotSourceRailDensity.regular

                HSplitView {
                    PlotSourceLibraryView(session: session, density: sourceRailDensity)
                        .frame(
                            minWidth: PlotWorkspaceLayoutPolicy.sourceRailMinWidth(for: sourceRailDensity),
                            idealWidth: PlotWorkspaceLayoutPolicy.sourceRailIdealWidth(for: sourceRailDensity),
                            maxWidth: PlotWorkspaceLayoutPolicy.sourceRailMaxWidth(for: sourceRailDensity),
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .padding(.leading, sourceRailDensity == .compact ? 6 : 10)
                        .padding(.vertical, 10)

                    PlotRefineView(session: session)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
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

}

private enum PlotWorkspaceLayoutPolicy {
    static let sourceRailCollapseThreshold: CGFloat = 980

    static func sourceRailMinWidth(for density: PlotSourceRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 224
        case .compact:
            return 104
        }
    }

    static func sourceRailIdealWidth(for density: PlotSourceRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 250
        case .compact:
            return 116
        }
    }

    static func sourceRailMaxWidth(for density: PlotSourceRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 286
        case .compact:
            return 132
        }
    }
}
