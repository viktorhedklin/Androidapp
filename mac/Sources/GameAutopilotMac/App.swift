import SwiftUI

/// Entry point. Menu-bar-only (no Dock icon, see Info.plist LSUIElement).
/// .window style (not .menu) since the content below needs real controls
/// (Picker, TextField, List) that a plain menu-item-style dropdown can't
/// reliably host.
@main
struct GameAutopilotMacApp: App {
    @StateObject private var controller = AutopilotController.shared

    var body: some Scene {
        MenuBarExtra("Game Autopilot", systemImage: statusIcon) {
            MenuBarView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)

        // Settings and the target picker are real windows, not .sheet()s
        // presented from the MenuBarExtra popover -- a MenuBarExtra(.window)
        // auto-dismisses on any click it considers "outside" itself, which
        // in practice includes interacting with a sheet's own controls
        // (typing in a field, opening a Picker). Independent Window scenes
        // sidestep that entirely.
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)

        Window("Pick Target", id: "targetPicker") {
            TargetPickerView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
    }

    private var statusIcon: String {
        switch controller.state {
        case .idle, .ready:
            return "gamecontroller"
        case .running(let phase, _):
            switch phase {
            case .idle: return "gamecontroller.fill"
            case .thinking: return "hourglass"
            case .acting: return "bolt.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
