//
//  Port_KillerApp.swift
//  Port Killer
//
//  Created by nano on 27/2/2569 BE.
//

import SwiftUI

/// SceneBuilder has no `if #available`, so the macOS 15+ launch behavior (`.suppressed`, the main
/// window must never open by itself at launch or login) needs a separate App type; the entry point
/// picks one at runtime. macOS 14 has no such API, so there AppActivation closes the launch-time
/// window itself.
@main
enum PortKillerLauncher {
    static func main() {
        if #available(macOS 15, *) {
            Port_KillerApp.main()
        } else {
            LegacyPort_KillerApp.main()
        }
    }
}

@available(macOS 15, *)
struct Port_KillerApp: App {
    @StateObject private var viewModel = PortViewModel()

    var body: some Scene {
        Window("Port Killer", id: "main") {
            MainWindowView().environmentObject(viewModel)
        }
        .defaultSize(width: 820, height: 520)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands { PortCommands(viewModel: viewModel) }

        SharedScenes(viewModel: viewModel)
    }
}

struct LegacyPort_KillerApp: App {
    @StateObject private var viewModel = PortViewModel()

    var body: some Scene {
        Window("Port Killer", id: "main") {
            MainWindowView().environmentObject(viewModel)
        }
        .defaultSize(width: 820, height: 520)
        .commands { PortCommands(viewModel: viewModel) }

        SharedScenes(viewModel: viewModel)
    }
}

/// Menu bar popover and Settings, identical on every supported macOS version.
struct SharedScenes: Scene {
    @ObservedObject var viewModel: PortViewModel

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(viewModel)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityLabel("Port Killer")
        }
        .menuBarExtraStyle(.window) // popover-style window instead of a standard menu list

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

/// What the main window exposes to the Ports menu. Published with `focusedSceneValue`, so it is
/// nil (and the commands are disabled) whenever the main window is not the focused window.
struct PortCommandContext {
    let selectedRows: [PortRow]
    /// Main window visible, has a killable selection, and focus is not in the search field.
    let canKill: Bool
}

private struct PortCommandContextKey: FocusedValueKey {
    typealias Value = PortCommandContext
}

extension FocusedValues {
    var portCommandContext: PortCommandContext? {
        get { self[PortCommandContextKey.self] }
        set { self[PortCommandContextKey.self] = newValue }
    }
}

struct PortCommands: Commands {
    @ObservedObject var viewModel: PortViewModel
    @FocusedValue(\.portCommandContext) private var context

    private var singleRow: PortRow? {
        guard let rows = context?.selectedRows, rows.count == 1 else { return nil }
        return rows.first
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Ports") {
            Button("Refresh") { viewModel.refresh() }
                .keyboardShortcut("r")
            Button("Kill Selected") { viewModel.killSelectedPorts(origin: .mainWindow) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(context?.canKill ?? false))
            Divider()
            Button(singleRow?.isPinned == true ? "Unpin" : "Pin") {
                if let row = singleRow { viewModel.togglePin(row) }
            }
            .disabled(singleRow == nil)
            Button("Copy PID") {
                let rows = (context?.selectedRows ?? []).filter(\.isRunning)
                PortActionsMenu.copy(rows.map(\.pid), label: "PID", viewModel, origin: .mainWindow)
            }
            .disabled(!(context?.selectedRows.contains(where: \.isRunning) ?? false))
            Button("Copy port") {
                PortActionsMenu.copy((context?.selectedRows ?? []).map(\.port), label: "port", viewModel, origin: .mainWindow)
            }
            .disabled(context?.selectedRows.isEmpty ?? true)
        }
    }
}
