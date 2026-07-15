import AppKit
import ArxivDiscoveryCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppViewModel
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

            Section("Subjects") {
                ForEach(AppSettings.categories, id: \.self) { category in
                    Toggle(category, isOn: Binding(
                        get: { settings.enabledCategories.contains(category) },
                        set: { enabled in
                            if enabled { settings.enabledCategories.insert(category) }
                            else if settings.enabledCategories.count > 1 { settings.enabledCategories.remove(category) }
                        }
                    ))
                }
            }

            Section("Korean translation") {
                SecureField(hasStoredKey ? "API key stored — enter to replace" : "Gemini API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save key") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) { removeKey() }
                        .disabled(!hasStoredKey)
                    Spacer()
                    Button { model.refreshGeminiModels() } label: {
                        if model.isLoadingModels { ProgressView().controlSize(.small) }
                        else { Label("Refresh models", systemImage: "arrow.clockwise") }
                    }
                    .disabled(!hasStoredKey || model.isLoadingModels)
                }

                if model.availableGeminiModels.isEmpty {
                    LabeledContent("Model", value: settings.geminiModel)
                } else {
                    Picker("Model", selection: $settings.geminiModel) {
                        ForEach(model.availableGeminiModels) { geminiModel in
                            Text(geminiModel.displayName).tag(geminiModel.modelID)
                        }
                    }
                }
                Text("Model availability comes from the saved key. Only this app's request and token totals are tracked locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("PDF downloads") {
                Picker("Filename", selection: $settings.pdfNameStyle) {
                    Text("Original paper title").tag(PDFNameStyle.title)
                    Text("arXiv ID").tag(PDFNameStyle.arxivID)
                }
                Text("Titles are automatically made safe for macOS filenames.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local storage") {
                Stepper("Keep ordinary papers for \(settings.cacheRetentionDays) days", value: $settings.cacheRetentionDays, in: 30...365, step: 30)
                Text("Saved papers, collections, notes, and translations are always kept.")
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
        .frame(width: 560, height: 760)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear {
            refreshKeyState()
            if hasStoredKey && model.availableGeminiModels.isEmpty { model.refreshGeminiModels() }
        }
    }

    private func refreshKeyState() {
        hasStoredKey = (try? keychain.read())?.isEmpty == false
    }

    private func saveKey() {
        do {
            try keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            hasStoredKey = true
            message = "API key saved to Keychain."
            model.geminiKeyDidChange()
        } catch {
            message = "The key could not be saved. \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        do {
            try keychain.remove()
            apiKey = ""
            hasStoredKey = false
            message = "API key removed."
            model.geminiKeyDidChange()
        } catch {
            message = "The key could not be removed. \(error.localizedDescription)"
        }
    }
}
