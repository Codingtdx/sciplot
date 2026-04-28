import SwiftUI

struct LauncherView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var focusedWorkbench: Workbench = .plot

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                LauncherModuleSelectionView(
                    focusedWorkbench: $focusedWorkbench,
                    open: { workbench, performPrimaryAction in
                        openWorkbench(workbench, performPrimaryAction: performPrimaryAction)
                    }
                )
                .frame(width: 340)
                .launcherGlassSurface()

                LauncherActionPanel(
                    workbench: focusedWorkbench,
                    primaryAction: {
                        openWorkbench(focusedWorkbench, performPrimaryAction: true)
                    },
                    openAction: {
                        openWorkbench(focusedWorkbench)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .launcherGlassSurface()
            }
            .padding(30)
            .frame(maxWidth: 980, maxHeight: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(nsColor: .underPageBackgroundColor)
                .overlay(.black.opacity(0.40))
                .ignoresSafeArea()
        }
    }

    private func openWorkbench(_ workbench: Workbench, performPrimaryAction: Bool = false) {
        focusedWorkbench = workbench
        if performPrimaryAction {
            model.beginLauncherPrimaryAction(for: workbench)
        } else {
            model.enterWorkbench(workbench)
        }
        openWindow(id: workbench.windowSceneID)
    }
}

private struct LauncherModuleSelectionView: View {
    @Binding var focusedWorkbench: Workbench
    let open: (Workbench, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SciPlot God")
                    .font(.title.weight(.semibold))
                Text("Choose a module")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                ForEach(Workbench.allCases) { workbench in
                    LauncherModuleRow(
                        workbench: workbench,
                        isSelected: focusedWorkbench == workbench
                    ) {
                        focusedWorkbench = workbench
                    }
                    .onTapGesture(count: 2) {
                        open(workbench, false)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }
}

private struct LauncherModuleRow: View {
    let workbench: Workbench
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: workbench.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workbench.title)
                        .font(.callout.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 11)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            }
        }
    }

    private var subtitle: String {
        switch workbench {
        case .plot:
            return "Plot, refine, and export figures"
        case .dataStudio:
            return "Prepare raw data workbooks"
        case .composer:
            return "Compose graph panels"
        case .codeConsole:
            return "Run contextual plotting code"
        }
    }
}

private struct LauncherActionPanel: View {
    let workbench: Workbench
    let primaryAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(workbench.title, systemImage: workbench.systemImage)
                .font(.title2.weight(.semibold))

            Text(statusText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button(action: openAction) {
                    Label("Open Module", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(22)
        .controlSize(.large)
    }

    private var primaryTitle: String {
        switch workbench {
        case .plot:
            return "Import or Open"
        case .dataStudio:
            return "Import Raw Data"
        case .composer:
            return "Import Graphs"
        case .codeConsole:
            return "Bind Context"
        }
    }

    private var primarySymbol: String {
        switch workbench {
        case .plot:
            return "tray.and.arrow.down"
        case .dataStudio:
            return "tablecells.badge.ellipsis"
        case .composer:
            return "photo.on.rectangle.angled"
        case .codeConsole:
            return "link"
        }
    }

    private var statusText: String {
        switch workbench {
        case .plot:
            return "Open Plot as its own workspace window and start from source data or a saved project."
        case .dataStudio:
            return "Open Data Studio as a data-preparation window for raw tables and workbooks."
        case .composer:
            return "Open Composer as a layout window for graph panels and exported assets."
        case .codeConsole:
            return "Open Code Console as a focused coding window bound to current project context."
        }
    }
}

private extension View {
    func launcherGlassSurface() -> some View {
        self
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
