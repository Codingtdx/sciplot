import SwiftUI

struct PlotWorkbenchView: View {
    let session: PlotSession
    let bootstrapErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Plot stage", selection: bindingForStage) {
                    ForEach(PlotStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if let bootstrapErrorMessage {
                    ErrorStateCard(
                        title: "Sidecar bootstrap issue",
                        message: bootstrapErrorMessage,
                        retryTitle: nil,
                        retryAction: nil
                    )
                }

                switch session.stage {
                case .importData:
                    PlotImportView(session: session)
                case .template:
                    PlotTemplateView(session: session)
                case .refineExport:
                    PlotRefineView(session: session)
                }
            }
            .padding(24)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.handleImportedFile(first)
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var bindingForStage: Binding<PlotStage> {
        Binding(
            get: { session.stage },
            set: { session.stage = $0 }
        )
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }
}
