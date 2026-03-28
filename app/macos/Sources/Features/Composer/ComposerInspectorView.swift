import SwiftUI

struct ComposerInspectorView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Composition") {
                    KeyValueGrid(values: [
                        ("Panels", "\(session.project.panels.count)"),
                        ("Texts", "\(session.project.texts.count)"),
                        ("Regions", "\(session.project.regions.count)"),
                    ])
                }

                if let panel = session.selectedPanel {
                    InspectorSection(title: "Selected Panel") {
                        KeyValueGrid(values: [
                            ("ID", panel.id),
                            ("Kind", panel.kind),
                            ("Path", panel.filePath),
                        ])

                        TextField(
                            "Label",
                            text: Binding(
                                get: { panel.label ?? "" },
                                set: { session.updateSelectedPanel(label: $0) }
                            )
                        )

                        Toggle(
                            "Hidden",
                            isOn: Binding(
                                get: { panel.hidden },
                                set: { session.updateSelectedPanel(hidden: $0) }
                            )
                        )

                        Toggle(
                            "Locked",
                            isOn: Binding(
                                get: { panel.locked },
                                set: { session.updateSelectedPanel(locked: $0) }
                            )
                        )
                    }

                    InspectorSection(title: "Asset Preview") {
                        let fileURL = URL(fileURLWithPath: panel.filePath)
                        if fileURL.pathExtension.lowercased() == "pdf" {
                            PDFPreviewView(url: fileURL)
                                .frame(minHeight: 220)
                        } else {
                            QuickLookThumbnailView(url: fileURL, size: 260)
                                .frame(minHeight: 220)
                        }
                    }
                } else {
                    EmptyStateCard(
                        title: "No panel selected",
                        message: "Select a graph or asset on the Composer canvas to inspect and edit it."
                    )
                }
            }
            .padding(16)
        }
    }
}
