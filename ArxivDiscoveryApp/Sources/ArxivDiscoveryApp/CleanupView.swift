import ArxivDiscoveryCore
import SwiftUI

struct CleanupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var confirming = false
    @State private var restoring = false

    var body: some View {
      VStack(spacing: 0) {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header.padding(20)
                if model.isPreviewingCleanup {
                    ProgressView("Checking papers and protected reading work…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if let preview = model.cleanupPreview {
                    if preview.candidates.isEmpty {
                        ContentUnavailableView("All caught up", systemImage: "checkmark.circle",
                            description: Text("No unrelated, unread papers need to be removed."))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(preview.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(candidate.title).font(.body.weight(.medium))
                                Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            Divider()
                        }
                    }
                } else {
                    ContentUnavailableView("Preview cleanup", systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Select topics to keep, then refresh the preview."))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reading work and PDFs are kept. Papers moved to Trash can be restored; a backup is saved first.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let message = model.cleanupError ?? model.cleanupMessage {
                        Text(message).font(.callout)
                            .foregroundStyle(model.cleanupError == nil ? Color.primary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { restoreButton; Spacer(minLength: 16); applyButton }
                        VStack(alignment: .leading, spacing: 10) { restoreButton; applyButton }
                    }
                }.padding([.horizontal, .bottom], 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(AppTheme.canvas(for: colorScheme))
      }
        .background(AppTheme.canvas(for: colorScheme))
        .onAppear { model.previewCleanup() }
        .onChange(of: settings.selectedTopicIDs) { model.previewCleanup() }
        .onChange(of: settings.researchTopics) { model.previewCleanup() }
        .confirmationDialog("Move \(model.cleanupPreview?.candidates.count ?? 0) papers to Trash?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Back up and move to Trash", role: .destructive) { model.applyCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only papers in the current preview are moved. PDFs, notes and other reading work are kept.")
        }
        .confirmationDialog("Restore \(model.lastRemovalCount) papers?", isPresented: $restoring, titleVisibility: .visible) {
            Button("Restore papers") { model.restoreLastCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Undo the latest removal batch. Older Trash papers stay in Trash.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup").font(.title2.bold())
            Text("Keep selected topics. Preview unrelated, unread Inbox papers before moving them to Trash.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DiscoveryScopeControls(settings: settings).topicSelection
                .disabled(model.isDiscovering || (model.isCleaning && !model.isPreviewingCleanup))
            HStack {
                Button { model.previewCleanup() } label: { Label("Refresh preview", systemImage: "arrow.clockwise") }
                    .disabled(settings.selectedTopics.isEmpty || !model.canChangeLibrary)
                Spacer(minLength: 8)
                Text("\(model.excludedCount) in Trash").font(.callout).foregroundStyle(.secondary)
            }
            if let preview = model.cleanupPreview {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("Matching topics"); Text("\(preview.relatedCount)").monospacedDigit() }
                    GridRow { Text("Reading work protected"); Text("\(preview.protectedCount)").monospacedDigit() }
                    GridRow { Text("Move to Trash").bold(); Text("\(preview.candidates.count)").bold().monospacedDigit() }
                }
                Divider()
            }
        }
    }

    private var restoreButton: some View {
        Button("Undo last removal (\(model.lastRemovalCount))") { restoring = true }
            .disabled(model.lastRemovalCount == 0 || !model.canChangeLibrary)
    }

    private var applyButton: some View {
        Button { confirming = true } label: {
            Label(model.isCleaning && !model.isPreviewingCleanup ? "Updating…" : "Move \(model.cleanupPreview?.candidates.count ?? 0) to Trash", systemImage: "trash")
                .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.cleanupPreview?.candidates.isEmpty != false || !model.canChangeLibrary)
    }
}
