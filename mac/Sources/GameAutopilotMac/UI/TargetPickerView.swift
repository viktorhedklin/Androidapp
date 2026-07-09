import SwiftUI

/// Lists capturable windows and lets the user pick one as the autopilot
/// target, plus an optional short prompt. Deliberately avoids List's
/// built-in `selection:` binding (its binding type has to match the `id`
/// keypath's type, not the element type, which is easy to get subtly
/// wrong without being able to build and check it) -- rows are plain
/// Buttons tracking a local `selected` value compared with `==` instead.
struct TargetPickerView: View {
    @Binding var prompt: String
    let onPick: (ScreenCapture.Target) -> Void

    @Environment(\.dismiss) private var dismiss
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

                TextField("What should the AI do? (optional)", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Refresh") { Task { await loadTargets() } }
                Button("Select") {
                    if let selected { onPick(selected) }
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
