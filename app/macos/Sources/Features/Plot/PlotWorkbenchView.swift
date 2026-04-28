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
                let templateRailDensity: PlotTemplateRailDensity =
                    geometry.size.width < PlotWorkspaceLayoutPolicy.templateRailCollapseThreshold
                    ? PlotTemplateRailDensity.compact
                    : PlotTemplateRailDensity.regular

                HSplitView {
                    PlotTemplateLibraryView(session: session, density: templateRailDensity)
                        .frame(
                            minWidth: PlotWorkspaceLayoutPolicy.templateRailMinWidth(for: templateRailDensity),
                            idealWidth: PlotWorkspaceLayoutPolicy.templateRailIdealWidth(for: templateRailDensity),
                            maxWidth: PlotWorkspaceLayoutPolicy.templateRailMaxWidth(for: templateRailDensity),
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .padding(.leading, templateRailDensity == .compact ? 6 : 10)
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
    static let templateRailCollapseThreshold: CGFloat = 980

    static func templateRailMinWidth(for density: PlotTemplateRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 188
        case .compact:
            return 70
        }
    }

    static func templateRailIdealWidth(for density: PlotTemplateRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 214
        case .compact:
            return 78
        }
    }

    static func templateRailMaxWidth(for density: PlotTemplateRailDensity) -> CGFloat {
        switch density {
        case .regular:
            return 246
        case .compact:
            return 88
        }
    }
}
