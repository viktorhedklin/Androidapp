import SwiftUI

/// Root content of the menu bar dropdown: target picker, status, Start/
/// Stop, settings. Mirrors the Android overlay control chip + Settings/
/// AddGame screens folded into one compact view, matching the "menu bar
/// utility, not a full app" v1 scope decision.
///
/// Settings/target picking/setup open as real windows (see App.swift)
/// rather than .sheet()s, so they don't get caught up in the
/// MenuBarExtra popover's own auto-dismiss-on-outside-click behavior.
struct MenuBarView: View {
    @EnvironmentObject private var controller: AutopilotController
    @Environment(\.openWindow) private var openWindow
    @State private var showResetMemoryConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Autopilot")
                .font(.headline)

            if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
                OnboardingView()
            } else {
                targetSection
                Divider()
                statusSection
                Divider()
                controlsSection
            }

            Divider()
            HStack {
                Button("Settings...") { openWindow(id: "settings") }
                Spacer()
                Button("Quit App") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .alert("Reset memory?", isPresented: $showResetMemoryConfirm) {
            Button("Reset", role: .destructive) {
                if let bundleID = controller.currentTarget?.bundleIdentifier {
                    controller.resetMemory(for: bundleID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forget everything the AI has learned about this target's progress? This cannot be undone.")
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        if let target = controller.currentTarget {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.title).font(.subheadline).bold()
                if let bundleID = target.bundleIdentifier {
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                }
                if let profile = controller.currentProfile, !profile.userGoal.isEmpty {
                    Text("Goal: \(profile.userGoal)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Change target...") { openWindow(id: "targetPicker") }
                Button("Edit setup...") {
                    controller.pendingSetupTarget = target
                    openWindow(id: "targetSetup")
                }
                Button("Reset memory") { showResetMemoryConfirm = true }
            }
        } else {
            Text("No target selected").foregroundStyle(.secondary)
            Button("Pick target...") { openWindow(id: "targetPicker") }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.caption)
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        HStack {
            if isRunning {
                Button("Stop") { controller.stop() }
            } else {
                Button("Start") { _ = controller.start(apiKey: Keychain.get() ?? "") }
                    .disabled(controller.currentTarget == nil || !Keychain.hasValue())
            }
            Spacer()
            if controller.currentTarget != nil {
                Button("Release target") { controller.quit() }
            }
        }
    }

    private var isRunning: Bool {
        if case .running = controller.state { return true }
        return false
    }

    private var statusColor: Color {
        switch controller.state {
        case .idle, .ready:
            return .gray
        case .running(let phase, _):
            switch phase {
            case .idle: return .gray
            case .thinking: return .yellow
            case .acting: return .green
            case .error: return .red
            case .completed: return .gray
            }
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch controller.state {
        case .idle(let note):
            return (note?.isEmpty == false) ? note! : "Idle"
        case .ready:
            return "Ready"
        case .running(let phase, let note):
            if let note, !note.isEmpty { return note }
            switch phase {
            case .idle: return "Running"
            case .thinking: return "Thinking..."
            case .acting: return "Acting"
            case .error: return "Error"
            case .completed: return "Goal complete!"
            }
        case .error(let message):
            return message
        }
    }
}
