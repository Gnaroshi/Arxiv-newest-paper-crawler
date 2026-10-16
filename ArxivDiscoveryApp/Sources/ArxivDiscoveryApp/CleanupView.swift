import ArxivDiscoveryCore
import SwiftUI

struct CleanupView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup").font(.title2.bold())
            Text("Keep selected topics. Move unrelated, unread Inbox papers to Trash.").foregroundStyle(.secondary)
            ScrollView {
                DiscoveryScopeControls(settings: settings).topicSelection
                    .disabled(model.isDiscovering || model.isCleaning)
            }.frame(height: min(130, CGFloat((settings.researchTopics.count + 1) / 2) * 26 + 36))
            HStack {
                Button { model.previewCleanup() } label: { Label("Refresh preview", systemImage: "arrow.clockwise") }
                    .disabled(settings.selectedTopics.isEmpty || model.isCleaning || model.isDiscovering)
                Spacer()
                Text("\(model.excludedCount) in Trash").foregroundStyle(.secondary)
            }
            if let preview = model.cleanupPreview {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("Matching topics"); Text("\(preview.relatedCount)").monospacedDigit() }
                    GridRow { Text("Reading work protected"); Text("\(preview.protectedCount)").monospacedDigit() }
                    GridRow { Text("Move to Trash").bold(); Text("\(preview.candidates.count)").bold().monospacedDigit() }
                }
                Divider()
                if preview.candidates.isEmpty {
                    VStack(spacing: 8) {
                        Label("All caught up", systemImage: "checkmark.circle").font(.headline).foregroundStyle(AppTheme.teal)
                        Text("No unrelated, unread papers need to be removed.").font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                  List(preview.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title).font(.body.weight(.medium))
                        Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                  }.listStyle(.inset)
                }
            } else {
                ContentUnavailableView("Preview cleanup", systemImage: "line.3.horizontal.decrease.circle", description: Text("Select topics to keep, then refresh the preview."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Saved, reviewed, viewed, annotated, translated or downloaded papers are protected. A backup is saved first. PDFs and notes are never deleted.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.errorMessage ?? model.notice {
                Text(message).font(.callout).foregroundStyle(model.errorMessage == nil ? Color.primary : Color.red)
            }
            HStack {
                Button("Undo last cleanup") { model.restoreLastCleanup() }
                    .disabled(model.cleanupState.latestBatchID == nil || !model.canChangeLibrary)
                Spacer()
                Button { confirming = true } label: {
                    Label(model.isCleaning ? "Moving…" : "Move unrelated to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.cleanupPreview?.candidates.isEmpty != false || !model.canChangeLibrary)
            }
        }
        .padding(20)
        .onAppear { model.previewCleanup() }
        .onChange(of: settings.selectedTopicIDs) { model.previewCleanup() }
        .onChange(of: settings.researchTopics) { model.previewCleanup() }
        .confirmationDialog("Move \(model.cleanupPreview?.candidates.count ?? 0) papers to Trash?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Back up and move to Trash", role: .destructive) { model.applyCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These papers disappear from New and Inbox. Restore them from Trash anytime. PDFs and reading work are kept.")
        }
    }
}
