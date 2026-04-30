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
                open: { workbench in
                    openWorkbench(workbench)
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

    private func openWorkbench(_ workbench: Workbench) {
        focusedWorkbench = workbench
        model.enterWorkbench(workbench)
        openWindow(id: workbench.windowSceneID)
        AppWindowManager.shared.openWorkbenchAfterSceneAttempt(workbench, model: model)
    }
}

private struct LauncherWelcomeSurface: View {
    let theme: ProWorkspaceTheme
    @Binding var focusedWorkbench: Workbench
    let close: () -> Void
    let open: (Workbench) -> Void

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
                            open(workbench)
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

    var body: some View {
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
            .padding(.vertical, 14)
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .contentShape(RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.row)
        .simultaneousGesture(TapGesture().onEnded { select() })
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
