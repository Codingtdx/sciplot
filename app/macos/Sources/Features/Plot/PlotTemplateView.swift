import SwiftUI

struct PlotTemplateView: View {
    let session: PlotSession

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        if session.inspectionResponse == nil {
            EmptyStateCard(
                title: "Inspect a file first",
                message: "Template selection is driven by the sidecar inspection and recommendation payloads."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    templateSection(
                        title: "Recommended Templates",
                        subtitle: "These templates are compatible with the inspected dataset and come directly from the ranked recommendation payload.",
                        templates: session.recommendedTemplates,
                        isEnabled: true
                    )

                    templateSection(
                        title: "Unavailable Here",
                        subtitle: "These contract-backed templates stay visible, but are disabled because the current inspected model does not recommend them.",
                        templates: session.disabledTemplates,
                        isEnabled: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func templateSection(
        title: String,
        subtitle: String,
        templates: [MetaTemplateSummary],
        isEnabled: Bool
    ) -> some View {
        let templateItems = Array(templates.enumerated())

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(templateItems, id: \.element.id) { _, template in
                    Button {
                        session.chooseTemplate(template.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(template.label)
                                    .font(.headline)
                                Spacer()
                                if session.selectedTemplateID == template.id {
                                    Label("Selected", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }

                            Text(template.description)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)

                            KeyValueGrid(values: [
                                ("ID", template.id),
                                ("Category", template.category),
                                ("Default size", template.defaultSize),
                            ])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(backgroundStyle(for: template, enabled: isEnabled))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private func backgroundStyle(for template: MetaTemplateSummary, enabled: Bool) -> some View {
        let isSelected = session.selectedTemplateID == template.id
        let fillColor = enabled
            ? Color.secondary.opacity(isSelected ? 0.18 : 0.08)
            : Color.secondary.opacity(0.04)
        let strokeColor = enabled ? Color.secondary.opacity(0.16) : Color.clear

        RoundedRectangle(cornerRadius: 18)
            .fill(fillColor)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(strokeColor, lineWidth: 1)
            }
    }
}
