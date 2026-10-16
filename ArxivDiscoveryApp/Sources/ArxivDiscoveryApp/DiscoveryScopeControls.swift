import ArxivDiscoveryCore
import SwiftUI

struct DiscoveryScopeControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("가져오기 기준", selection: $settings.discoveryMode) {
                ForEach(DiscoveryMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .pickerStyle(.segmented)
            if settings.discoveryMode == .topics {
                topicSelection
                Text("선택한 주제 중 하나가 제목·초록에 확인되는 논문만 가져옵니다.")
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
                Label("분야 전체 수집: VLA·World Models 이외의 논문도 가져옵니다.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    var topicSelection: some View {
        HStack(spacing: 20) {
            ForEach(SmartTopic.allCases) { topic in
                Toggle(topic.label, isOn: Binding(
                    get: { settings.enabledTopics.contains(topic) },
                    set: { enabled in
                        if enabled { settings.enabledTopics.insert(topic) }
                        else { settings.enabledTopics.remove(topic) }
                    }
                )).toggleStyle(.checkbox)
            }
        }
    }
}
