import SwiftUI

/// First-time (or "Edit setup...") target setup: name/info/goal, an
/// optional one-shot AI research pass, an optional single consolidated
/// list of clarifying questions, Save. Opened as a real Window (not
/// .sheet()), consistent with the earlier MenuBarExtra dismiss-bug fix.
///
/// Deliberately NOT a multi-round chat: one research pass produces a
/// summary + at most a few questions; the user can address them via one
/// "anything else" field and re-run research once if needed, rather
/// than an open-ended back-and-forth -- this is a menu-bar utility, not
/// a chat app. Everything here is optional and Save works at any point,
/// matching the original picker's "(optional)" prompt field behavior.
///
/// The target being set up comes from `controller.pendingSetupTarget`,
/// set by whoever opens this window (TargetPickerView for a brand-new
/// target, or MenuBarView's "Edit setup..." for an existing one) --
/// SwiftUI's plain `Window` scene has no built-in way to pass a value in,
/// so a small piece of shared transient state fills that gap.
struct TargetSetupView: View {
    @EnvironmentObject private var controller: AutopilotController
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var target: ScreenCapture.Target?
    @State private var name: String = ""
    @State private var userInfo: String = ""
    @State private var userGoal: String = ""
    @State private var goalMode: GoalMode = .keepRunning
    @State private var researchSummary: String = ""
    @State private var questions: [String] = []
    @State private var isResearching = false
    @State private var researchError: String?
    @State private var researchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up target").font(.headline)

            if let target {
                Text(target.title).font(.subheadline).foregroundStyle(.secondary)
            }

            TextField("Name", text: $name)

            TextField("Anything the AI should know? (optional)", text: $userInfo, axis: .vertical)
                .lineLimit(2...4)

            TextField("What should it do? (optional)", text: $userGoal, axis: .vertical)
                .lineLimit(2...4)

            Picker("Goal type", selection: $goalMode) {
                Text("Keeps going (grind/idle)").tag(GoalMode.keepRunning)
                Text("Finishes and stops").tag(GoalMode.playUntilComplete)
            }
            .pickerStyle(.segmented)

            HStack {
                Button(isResearching ? "Researching..." : "Research") { startResearch() }
                    .disabled(name.isEmpty || isResearching)
                if isResearching {
                    Button("Cancel research") {
                        researchTask?.cancel()
                        isResearching = false
                    }
                }
            }

            if let researchError {
                Text(researchError).font(.caption).foregroundStyle(.red)
            }

            if !researchSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What I found").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(researchSummary).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
            }

            if !questions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A few things that might help (optional, fold into the fields above if useful):")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(questions, id: \.self) { q in
                        Text("• \(q)").font(.caption)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    researchTask?.cancel()
                    dismissWindow(id: "targetSetup")
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil || name.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            loadPending()
            // See SettingsView.swift -- accessory apps need an explicit
            // activate() or secondary Window scenes never become key.
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { researchTask?.cancel() }
    }

    private func loadPending() {
        guard let pending = controller.pendingSetupTarget else { return }
        target = pending
        if let bundleID = pending.bundleIdentifier, let existing = controller.profileStore.get(bundleID) {
            name = existing.displayName
            userInfo = existing.userInfo
            userGoal = existing.userGoal
            goalMode = existing.goalMode
            researchSummary = existing.researchSummary
        } else {
            name = pending.title
        }
    }

    private func startResearch() {
        researchError = nil
        isResearching = true
        researchTask = Task {
            do {
                let apiKey = Keychain.get() ?? ""
                let researchKey = Keychain.get(account: "researchApiKey")
                let result = try await GameResearcher.research(
                    name: name,
                    userInfo: userInfo,
                    settings: controller.settingsStore.settings,
                    gameplayApiKey: apiKey,
                    researchApiKey: researchKey
                )
                if Task.isCancelled { return }
                researchSummary = result.summary
                questions = result.questions
                goalMode = result.suggestedGoalMode
            } catch {
                if !Task.isCancelled {
                    researchError = "Research failed: \(error.localizedDescription)"
                }
            }
            isResearching = false
        }
    }

    private func save() {
        guard let target, let bundleID = target.bundleIdentifier else { return }
        let now = Date()
        let existing = controller.profileStore.get(bundleID)
        let profile = TargetProfile(
            bundleIdentifier: bundleID,
            displayName: name,
            userInfo: userInfo,
            researchSummary: researchSummary,
            userGoal: userGoal,
            goalMode: goalMode,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        controller.profileStore.save(profile)
        controller.selectTarget(target, profile: profile)
        dismissWindow(id: "targetSetup")
    }
}
