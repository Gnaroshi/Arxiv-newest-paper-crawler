import ArxivDiscoveryCore
import SwiftUI

struct CleanupView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("라이브러리 정리").font(.title2.bold())
            Text("선택한 연구 주제와 관련 없는 미열람 논문을 New·Inbox에서 제외합니다.").foregroundStyle(.secondary)
            DiscoveryScopeControls(settings: settings).topicSelection
                .disabled(model.isDiscovering || model.isCleaning)
            HStack {
                Button { model.previewCleanup() } label: { Label("미리보기 갱신", systemImage: "arrow.clockwise") }
                    .disabled(settings.enabledTopics.isEmpty || model.isCleaning || model.isDiscovering)
                Spacer()
                Text("제외됨 \(model.excludedCount)편").foregroundStyle(.secondary)
            }
            if let preview = model.cleanupPreview {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("관련 논문 유지"); Text("\(preview.relatedCount)편").monospacedDigit() }
                    GridRow { Text("보관·읽기 기록 보호"); Text("\(preview.protectedCount)편").monospacedDigit() }
                    GridRow { Text("제외 예정").bold(); Text("\(preview.candidates.count)편").bold().monospacedDigit() }
                }
                Divider()
                List(preview.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title).font(.body.weight(.medium))
                        Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }.listStyle(.inset)
            } else {
                ContentUnavailableView("정리할 논문 확인", systemImage: "line.3.horizontal.decrease.circle", description: Text("유지할 주제를 선택하고 미리보기를 갱신하세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Saved·Reviewed, 열람·노트·컬렉션·번역·PDF가 있는 논문은 보호됩니다. 원본은 백업되며 제외됨에서 복구할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.errorMessage ?? model.notice {
                Text(message).font(.callout).foregroundStyle(model.errorMessage == nil ? Color.primary : Color.red)
            }
            HStack {
                Button("최근 정리 되돌리기") { model.restoreLastCleanup() }
                    .disabled(model.cleanupState.latestBatchID == nil || model.isDiscovering || ShowcaseMode.isEnabled)
                Spacer()
                Button { confirming = true } label: {
                    Label(model.isCleaning ? "정리 중…" : "관련 없는 논문 제외", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.cleanupPreview?.candidates.isEmpty != false || model.isCleaning || model.isDiscovering || ShowcaseMode.isEnabled)
            }
        }
        .padding(20)
        .onAppear { model.previewCleanup() }
        .onChange(of: settings.enabledTopics) { model.previewCleanup() }
        .confirmationDialog("\(model.cleanupPreview?.candidates.count ?? 0)편을 New·Inbox에서 제외할까요?", isPresented: $confirming, titleVisibility: .visible) {
            Button("백업 후 제외") { model.applyCleanup() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("논문 원본과 PDF는 유지되며 언제든 복구할 수 있습니다.")
        }
    }
}
