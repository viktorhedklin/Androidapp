import Combine
import SwiftUI

/// Shown inline in the menu bar dropdown until both TCC permissions are
/// granted. There's no permission-change notification, so this polls
/// once a second while visible -- matches the plan's guidance that
/// AXIsProcessTrustedWithOptions's own auto-prompt is unreliable in
/// practice, so the deep-link + poll pattern is used instead.
struct OnboardingView: View {
    @State private var hasAccessibility = Permissions.hasAccessibility()
    @State private var hasScreenRecording = Permissions.hasScreenRecording()

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Grant two permissions to get started:")
                .font(.callout)

            permissionRow(granted: hasScreenRecording, title: "Screen Recording") {
                ScreenCapture.requestPermission()
                Permissions.openScreenRecordingSettings()
            }
            permissionRow(granted: hasAccessibility, title: "Accessibility") {
                _ = AccessibilityReader.isTrusted(promptIfNeeded: true)
                Permissions.openAccessibilitySettings()
            }

            Text("macOS may periodically ask you to re-confirm Screen Recording (roughly monthly) -- that's normal.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onReceive(timer) { _ in
            hasAccessibility = Permissions.hasAccessibility()
            hasScreenRecording = Permissions.hasScreenRecording()
        }
    }

    @ViewBuilder
    private func permissionRow(granted: Bool, title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
            Spacer()
            if !granted {
                Button("Grant...", action: action)
            }
        }
    }
}
