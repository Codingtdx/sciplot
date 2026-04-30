import SwiftUI

struct LauncherView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.proWorkspaceTheme) private var theme
    @State private var focusedWorkbench: Workbench = .plot

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            LauncherWelcomeSurface(
                theme: theme,
                focusedWorkbench: $focusedWorkbench,
                close: closeLauncher,
                open: { workbench, performPrimaryAction in
                    openWorkbench(workbench, performPrimaryAction: performPrimaryAction)
                }
            )
            .frame(width: 720)
            .proGlassPanel(
                theme: theme,
                cornerRadius: ProCornerPolicy.launcher,
                showsBorder: false
            )
        }
        .frame(width: 760, height: 460)
        .background(Color.clear)
    }

    private func closeLauncher() {
        dismiss()
        AppWindowManager.shared.closeLauncher()
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
    let theme: ProWorkspaceTheme
    @Binding var focusedWorkbench: Workbench
    let close: () -> Void
    let open: (Workbench, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header

            VStack(spacing: 12) {
                ForEach(Workbench.allCases) { workbench in
                    LauncherModuleEntryRow(
                        workbench: workbench,
                        isSelected: focusedWorkbench == workbench,
                        theme: theme,
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
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 30)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SciPlot God")
                    .font(.largeTitle.weight(.semibold))

                Text("Choose a module")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            LauncherCloseButton(action: close)
        }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }
}

private struct LauncherModuleEntryRow: View {
    let workbench: Workbench
    let isSelected: Bool
    let theme: ProWorkspaceTheme
    let select: () -> Void
    let open: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: open) {
                HStack(spacing: 16) {
                    Image(systemName: workbench.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workbench.title)
                            .font(.title3.weight(.semibold))
                        Text(subtitle)
                            .font(.callout)
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
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.row)
        .contentShape(RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous))
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
            .frame(width: 168)
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

private struct LauncherCloseButton: View {
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(theme.rowFill, in: Circle())
        .clipShape(Circle())
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Close Launcher")
    }
}
