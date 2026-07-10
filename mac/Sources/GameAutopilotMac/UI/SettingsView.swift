import SwiftUI

/// Provider + connection + safety settings, opened as a real Window (see
/// App.swift) rather than a .sheet(). The API key is Keychain-backed
/// (Util/Keychain.swift) and never touches Settings/UserDefaults; the
/// text field never echoes back a stored key, matching the Android
/// Settings screen's "never echo back stored key" behavior.
struct SettingsView: View {
    @EnvironmentObject private var controller: AutopilotController
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var provider: BrainProvider
    @State private var baseUrl: String
    @State private var model: String
    @State private var maxActionsPerMinute: String
    @State private var tickIntervalMs: String
    @State private var onlyActOnTarget: Bool
    @State private var useSetOfMarks: Bool
    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey: Bool

    init() {
        let s = AutopilotController.shared.settingsStore.settings
        _provider = State(initialValue: s.provider)
        _baseUrl = State(initialValue: s.baseUrl)
        _model = State(initialValue: s.model)
        _maxActionsPerMinute = State(initialValue: String(s.maxActionsPerMinute))
        _tickIntervalMs = State(initialValue: String(s.tickIntervalMs))
        _onlyActOnTarget = State(initialValue: s.onlyActOnTarget)
        _useSetOfMarks = State(initialValue: s.useSetOfMarks)
        _hasStoredKey = State(initialValue: Keychain.hasValue())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            Picker("Provider", selection: $provider) {
                ForEach(BrainProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, newProvider in applyProviderDefaults(newProvider) }

            TextField("Base URL", text: $baseUrl)
            TextField("Model", text: $model)

            VStack(alignment: .leading, spacing: 4) {
                SecureField(hasStoredKey ? "API key (set -- leave blank to keep)" : "API key", text: $apiKeyInput)
                if hasStoredKey {
                    Button("Clear API key") {
                        Keychain.delete()
                        hasStoredKey = false
                    }
                    .foregroundStyle(.red)
                }
            }

            HStack {
                Text("Max actions/min")
                TextField("", text: $maxActionsPerMinute).frame(width: 50)
                Spacer()
                Text("Tick interval (ms)")
                TextField("", text: $tickIntervalMs).frame(width: 70)
            }

            Toggle("Only act when target is frontmost", isOn: $onlyActOnTarget)
            Toggle("Use set-of-marks prompting (recommended)", isOn: $useSetOfMarks)

            HStack {
                Button("Cancel") { dismissWindow(id: "settings") }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    /// Only flips defaults when the user hasn't customized them yet --
    /// mirrors SettingsActivity.kt's provider-switch behavior.
    private func applyProviderDefaults(_ newProvider: BrainProvider) {
        let knownUrls: Set<String> = [Settings.defaultOpenAIUrl, Settings.defaultNvidiaUrl, Settings.defaultGeminiUrl]
        let knownModels: Set<String> = [Settings.defaultOpenAIModel, Settings.defaultNvidiaModel, Settings.defaultGeminiModel]
        if baseUrl.isEmpty || knownUrls.contains(baseUrl) {
            baseUrl = Settings.defaultUrl(for: newProvider)
        }
        if model.isEmpty || knownModels.contains(model) {
            model = Settings.defaultModel(for: newProvider)
        }
    }

    private func save() {
        if !apiKeyInput.isEmpty {
            Keychain.set(apiKeyInput, account: "apiKey")
            hasStoredKey = true
        }
        let merged = Settings(
            provider: provider,
            baseUrl: baseUrl,
            model: model,
            maxActionsPerMinute: Int(maxActionsPerMinute) ?? 30,
            onlyActOnTarget: onlyActOnTarget,
            useSetOfMarks: useSetOfMarks,
            tickIntervalMs: Int(tickIntervalMs) ?? 1500
        )
        controller.settingsStore.save(merged)
        dismissWindow(id: "settings")
    }
}
