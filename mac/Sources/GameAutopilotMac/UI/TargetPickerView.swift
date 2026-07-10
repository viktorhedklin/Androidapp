import SwiftUI

/// Lists capturable windows and lets the user pick one as the autopilot
/// target. Opened as a real Window (see App.swift) rather than a
/// .sheet(). Deliberately avoids List's built-in `selection:` binding
/// (its binding type has to match the `id` keypath's type, not the
/// element type, which is easy to get subtly wrong without being able to
/// build and check it) -- rows are plain Buttons tracking a local
/// `selected` value compared with `==` instead.
///
/// Selecting a target with an existing TargetProfile goes straight to
/// AutopilotController.selectTarget -- no re-setup. A brand-new target
/// routes to TargetSetupView instead (see Select's action below).
struct TargetPickerView: View {
    @EnvironmentObject private var controller: AutopilotController
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var targets: [ScreenCapture.Target] = []
    @State private var selected: ScreenCapture.Target?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a target").font(.headline)

            if !ScreenCapture.hasPermission() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screen Recording permission is required to list windows.")
                        .font(.callout)
                    Button("Grant Screen Recording Access") {
                        ScreenCapture.requestPermission()
                        Permissions.openScreenRecordingSettings()
                    }
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                List(targets, id: \.windowID) { target in
                    Button {
                        selected = target
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(target.title)
                                if let bundleID = target.bundleIdentifier {
                                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selected == target {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 220)
            }

            HStack {
                Button("Cancel") { dismissWindow(id: "targetPicker") }
                Spacer()
                Button("Refresh") { Task { await loadTargets() } }
                Button("Select") {
                    guard let selected else { return }
                    if let bundleID = selected.bundleIdentifier,
                       let profile = controller.profileStore.get(bundleID) {
                        // Known target -- skip setup entirely, straight to Start-ready.
                        controller.selectTarget(selected, profile: profile)
                    } else {
                        controller.pendingSetupTarget = selected
                        openWindow(id: "targetSetup")
                    }
                    dismissWindow(id: "targetPicker")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding(16)
        .frame(width: 380)
        .task { await loadTargets() }
    }

    private func loadTargets() async {
        guard ScreenCapture.hasPermission() else {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            targets = try await ScreenCapture.listCapturableTargets()
        } catch {
            errorMessage = "Couldn't list windows: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
