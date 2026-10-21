import ArxivDiscoveryCore
import SwiftUI

struct TopicManagerView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editingID: String?
    @State private var name = ""
    @State private var anyTerms = ""
    @State private var requiredTerms = ""
    @State private var excludedTerms = ""
    @State private var editorVisible = false
    @FocusState private var nameFocused: Bool
    @State private var savedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Research topics").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(editorVisible)
            }
            TextField("Find a topic", text: $search).textFieldStyle(.roundedBorder)
            List {
                ForEach(settings.researchTopics.filter { search.isEmpty || ($0.name + " " + $0.anyTerms.joined(separator: " ")).localizedCaseInsensitiveContains(search) }) { topic in
                    HStack(alignment: .top) {
                        Toggle(isOn: selection(topic)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.name).font(.headline)
                                Text(topic.anyTerms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }.toggleStyle(.checkbox)
                        Spacer()
                        Button { edit(topic) } label: { Image(systemName: "pencil") }.help("Edit topic")
                            .accessibilityLabel("Edit \(topic.name)")
                        Button(role: .destructive) {
                            settings.selectedTopicIDs.remove(topic.id)
                            settings.researchTopics.removeAll { $0.id == topic.id }
                        } label: { Image(systemName: "trash") }.help("Remove topic rule; papers are kept")
                            .accessibilityLabel("Remove \(topic.name) rule")
                    }.padding(.vertical, 6)
                }
            }.frame(minHeight: 140)
            if editorVisible {
                Divider()
                Form {
                    TextField("Topic name", text: $name).focused($nameFocused)
                    TextField("Match any", text: $anyTerms, prompt: Text("neural ODE, neural CDE"))
                    TextField("Require all", text: $requiredTerms, prompt: Text("Optional words or phrases"))
                    TextField("Exclude any", text: $excludedTerms, prompt: Text("Optional words or phrases"))
                }
                Text("Separate phrases with commas. Rules match titles and abstracts, not references or broad category labels.")
                    .font(.caption).foregroundStyle(.secondary)
                if duplicateName { Text("This topic name is already used.").font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { editorVisible = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save topic") { save() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!draft.isValid || duplicateName)
                }
            } else {
                Button { edit(nil) } label: { Label("New topic", systemImage: "plus") }
                if let savedName { Text("Saved \(savedName)").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(20).frame(width: 580, height: editorVisible ? 600 : 420)
        .interactiveDismissDisabled(editorVisible)
        .onAppear { settings.topicEditorOpened() }
        .onDisappear { settings.topicEditorClosed() }
    }

    private func selection(_ topic: ResearchTopic) -> Binding<Bool> {
        Binding(get: { settings.selectedTopicIDs.contains(topic.id) }, set: {
            if $0 { settings.selectedTopicIDs.insert(topic.id) } else { settings.selectedTopicIDs.remove(topic.id) }
        })
    }
    private var draft: ResearchTopic {
        ResearchTopic(id: editingID ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), anyTerms: terms(anyTerms), requiredTerms: terms(requiredTerms), excludedTerms: terms(excludedTerms))
    }
    private var duplicateName: Bool {
        settings.researchTopics.contains { $0.id != editingID && $0.name.compare(name.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) == .orderedSame }
    }
    private func terms(_ text: String) -> [String] { text.components(separatedBy: ",") }
    private func edit(_ topic: ResearchTopic?) {
        editingID = topic?.id
        name = topic?.name ?? ""
        anyTerms = topic?.anyTerms.joined(separator: ", ") ?? ""
        requiredTerms = topic?.requiredTerms.joined(separator: ", ") ?? ""
        excludedTerms = topic?.excludedTerms.joined(separator: ", ") ?? ""
        editorVisible = true
        nameFocused = true
    }
    private func save() {
        let topic = draft
        guard topic.isValid, !duplicateName else { return }
        if let index = settings.researchTopics.firstIndex(where: { $0.id == topic.id }) { settings.researchTopics[index] = topic }
        else { settings.researchTopics.append(topic) }
        settings.selectedTopicIDs.insert(topic.id)
        savedName = topic.name
        search = ""
        editorVisible = false
    }
}
