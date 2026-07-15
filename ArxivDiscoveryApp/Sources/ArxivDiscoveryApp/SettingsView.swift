import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let repositoryRoot: URL
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var message: String?
    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Discovery categories") {
                ForEach(AppSettings.categories, id: \.self) { category in
                    Toggle(category, isOn: Binding(
                        get: { settings.enabledCategories.contains(category) },
                        set: { enabled in
                            if enabled { settings.enabledCategories.insert(category) }
                            else if settings.enabledCategories.count > 1 { settings.enabledCategories.remove(category) }
                        }
                    ))
                }
                Text("At least one category stays enabled. Changes apply to the next discovery request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Optional Korean translation") {
                SecureField(hasStoredKey ? "Stored in Keychain — enter to replace" : "Gemini API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Model", value: settings.geminiModel)
                Text("Only the selected public title and abstract are sent after you press Translate. The key stays in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save to Keychain") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove key", role: .destructive) { removeKey() }
                        .disabled(!hasStoredKey)
                }
            }

            Section("Local data") {
                Text("Papers, favorites, status, and downloaded PDFs remain in the app-owned Application Support directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open data folder") {
                    try? FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(repositoryRoot)
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 520, height: 620)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear { refreshKeyState() }
    }

    private func refreshKeyState() {
        hasStoredKey = (try? keychain.read())?.isEmpty == false
    }

    private func saveKey() {
        do {
            try keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            hasStoredKey = true
            message = "Gemini key saved to Keychain."
        } catch {
            message = "The key could not be saved. \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        do {
            try keychain.remove()
            apiKey = ""
            hasStoredKey = false
            message = "Gemini key removed."
        } catch {
            message = "The key could not be removed. \(error.localizedDescription)"
        }
    }
}
