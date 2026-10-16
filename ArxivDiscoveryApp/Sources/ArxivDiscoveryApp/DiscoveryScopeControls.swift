import ArxivDiscoveryCore
import SwiftUI

struct DiscoveryScopeControls: View {
    @ObservedObject var settings: AppSettings
    @State private var managingTopics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Search by", selection: $settings.discoveryMode) {
                ForEach(DiscoveryMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .pickerStyle(.segmented)
            if settings.discoveryMode == .topics {
                topicSelection
                Text("Only papers matching a selected topic in the title or abstract are collected.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(AppSettings.categories, id: \.self) { category in
                        Toggle(category, isOn: Binding(
                            get: { settings.enabledCategories.contains(category) },
                            set: { enabled in
                                if enabled { settings.enabledCategories.insert(category) }
                                else { settings.enabledCategories.remove(category) }
                            }
                        )).toggleStyle(.checkbox)
                    }
                }
                Label("Broad search: collects every paper in the selected categories, including unrelated topics.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    var topicSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(settings.researchTopics) { topic in
                Toggle(topic.name, isOn: Binding(
                    get: { settings.selectedTopicIDs.contains(topic.id) },
                    set: { enabled in
                        if enabled { settings.selectedTopicIDs.insert(topic.id) }
                        else { settings.selectedTopicIDs.remove(topic.id) }
                    }
                )).toggleStyle(.checkbox)
            }
          }
          Button { managingTopics = true } label: { Label("Find or create topics", systemImage: "slider.horizontal.3") }
        }.sheet(isPresented: $managingTopics) { TopicManagerView(settings: settings) }
    }
}
