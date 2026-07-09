import SwiftUI

/// Entry point. Menu-bar-only (no Dock icon, see Info.plist LSUIElement).
/// This is a minimal placeholder wired up in the skeleton commit -- the
/// real menu content (target picker, Start/Stop, settings, onboarding)
/// lands in UI/MenuBarView.swift and gets swapped in here.
@main
struct GameAutopilotMacApp: App {
    var body: some Scene {
        MenuBarExtra("Game Autopilot", systemImage: "gamecontroller") {
            Text("Game Autopilot")
                .font(.headline)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
