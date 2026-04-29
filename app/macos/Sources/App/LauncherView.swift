import SwiftUI

struct LauncherView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var focusedWorkbench: Workbench = .plot

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            LauncherWelcomeSurface(
                focusedWorkbench: $focusedWorkbench,
                open: { workbench, performPrimaryAction in
                    openWorkbench(workbench, performPrimaryAction: performPrimaryAction)
                }
            )
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .frame(width: 620)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func openWorkbench(_ workbench: Workbench, performPrimaryAction: Bool = false) {
        focusedWorkbench = workbench
        if performPrimaryAction {
            model.beginLauncherPrimaryAction(for: workbench)
        } else {
            model.enterWorkbench(workbench)
        }
        openWindow(id: workbench.windowSceneID)
        AppWindowManager.shared.openWorkbenchAfterSceneAttempt(workbench, model: model)
    }
}

private struct LauncherWelcomeSurface: View {
    @Binding var focusedWorkbench: Workbench
    let open: (Workbench, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 6) {
                ForEach(Workbench.allCases) { workbench in
                    LauncherModuleEntryRow(
                        workbench: workbench,
                        isSelected: focusedWorkbench == workbench,
                        select: {
                            focusedWorkbench = workbench
                        },
                        open: {
                            open(workbench, false)
                        },
                        primaryAction: {
                            open(workbench, true)
                        }
                    )
                }
            }
        }
        .padding(18)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("SciPlot God")
                .font(.title2.weight(.semibold))

            Spacer(minLength: 12)

            Text("Choose a module")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LauncherModuleEntryRow: View {
    let workbench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: workbench.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workbench.title)
                            .font(.callout.weight(.semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { select() })

            primaryButton
        }
        .padding(.vertical, 9)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.08))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: select)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isSelected {
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
        } else {
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
    }

    private var primaryLabel: some View {
        Label(primaryTitle, systemImage: primarySymbol)
            .labelStyle(.titleAndIcon)
            .frame(width: 148)
    }

    private var subtitle: String {
        switch workbench {
        case .plot:
            return "Sheet, plot type, adjust, export"
        case .dataStudio:
            return "Prepare raw data workbooks"
        case .composer:
            return "Arrange graph panels"
        case .codeConsole:
            return "Run code from bound context"
        }
    }

    private var primaryTitle: String {
        switch workbench {
        case .plot:
            return "Import/Open"
        case .dataStudio:
            return "Import Raw"
        case .composer:
            return "Import"
        case .codeConsole:
            return "Bind"
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
}
