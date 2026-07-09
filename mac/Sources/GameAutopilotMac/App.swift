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
