import ArxivDiscoveryCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var importingLegacy = false
    @State private var creatingCollection = false
    @State private var collectionName = ""
    @State private var managingTopics = false
    @State private var deletingPaper: Paper?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } detail: {
            if model.scope == .calendar || model.scope == .cleanup {
                candidateColumn
            } else {
                HSplitView {
                    candidateColumn.frame(minWidth: 340, idealWidth: 440, maxWidth: 620)
                    detailColumn.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppTheme.canvas(for: colorScheme))
        .preferredColorScheme(settings.appearance.colorScheme)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Title, author, note, or abstract")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import previous papers.json") { importingLegacy = true }
                    Button("Open data folder") { model.openDataFolder() }
                    Button("Manage research topics") { managingTopics = true }
                } label: {
                    Label("Library options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $managingTopics) { TopicManagerView(settings: settings) }
        .alert("Delete paper metadata?", isPresented: Binding(get: { deletingPaper != nil }, set: { if !$0 { deletingPaper = nil } })) {
            Button("Cancel", role: .cancel) { deletingPaper = nil }
            Button("Delete metadata", role: .destructive) {
                if let paper = deletingPaper { model.deleteTrashedMetadata(paper) }
                deletingPaper = nil
            }
        } message: {
            Text("Removes this paper from Trash. Downloaded PDFs and reading notes are kept. A backup is saved first.")
        }
        .fileImporter(
            isPresented: $importingLegacy,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { model.importLegacy(from: url) }
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .alert("New collection", isPresented: $creatingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) { collectionName = "" }
            Button("Create") {
                if model.createCollection(named: collectionName) { collectionName = "" }
            }
        } message: {
            Text("Group saved papers like a playlist.")
        }
        .onChange(of: model.selectedPaperID) { model.recordSelection() }
        .onChange(of: model.scope) { model.reconcileSelection() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.scope) {
                Section("Discover") {
                    Label("Calendar", systemImage: "calendar")
                        .badge(model.unsearchedRecentCount)
                        .tag(LibraryScope.calendar)
                    Label("Inbox", systemImage: "tray")
                        .badge(model.inboxCount)
                        .tag(LibraryScope.inbox)
                    Label("New", systemImage: "sparkles")
                        .badge(model.newCount)
                        .tag(LibraryScope.new)
                }

                Section("Library") {
                    Label("Saved", systemImage: "bookmark")
                        .badge(model.savedCount)
                        .tag(LibraryScope.saved)
                    Label("Reviewed", systemImage: "checkmark.circle")
                        .badge(model.reviewedCount)
                        .tag(LibraryScope.reviewed)
                    Label("All papers", systemImage: "tray.full")
                        .badge(model.activePapers.count)
                        .tag(LibraryScope.all)
                    Label("Cleanup", systemImage: "line.3.horizontal.decrease.circle")
                        .tag(LibraryScope.cleanup)
                    Label("Trash", systemImage: "trash")
                        .badge(model.excludedCount)
                        .tag(LibraryScope.excluded)
                }

                Section {
                    ForEach(model.library.collections) { collection in
                        Label(collection.name, systemImage: "rectangle.stack")
                            .badge(model.collectionCount(collection.id))
                            .tag(LibraryScope.collection(collection.id))
                    }
                } header: {
                    HStack {
                        Text("Collections")
                        Spacer()
                        Button { creatingCollection = true } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("New collection")
                    }
                }

                Section {
                    ForEach(settings.researchTopics) { topic in
                        Label(topic.name, systemImage: "tag")
                            .badge(model.topicCount(topic))
                            .tag(LibraryScope.topic(topic.id))
                    }
                } header: {
                    HStack {
                        Text("Topics")
                        Spacer()
                        Button { managingTopics = true } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(.plain).help("Find, create or edit topics")
                    }
                }

                if !model.observedSubjects.isEmpty {
                    Section("arXiv categories") {
                        ForEach(model.observedSubjects, id: \.self) { subject in
                            Label(subject, systemImage: "number")
                                .tag(LibraryScope.subject(subject))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            usageFooter
        }
        .navigationTitle("Arxiv Discovery")
    }

    private var usageFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Gemini", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle()
                    .fill(model.geminiConfigured ? AppTheme.teal : Color.secondary)
                    .frame(width: 7, height: 7)
            }
            if model.geminiConfigured {
                Text("Today · \(model.todayUsage.requests) requests · \(model.todayUsage.totalTokens.formatted()) tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add an API key in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var candidateColumn: some View {
        if model.scope == .calendar {
            DiscoveryCalendarView(model: model, settings: settings)
        } else if model.scope == .cleanup {
            CleanupView(model: model, settings: settings)
        } else {
            VStack(spacing: 0) {
                listHeader
                Divider()

                if let errorMessage = model.errorMessage {
                    statusBanner(icon: "exclamationmark.triangle.fill", text: errorMessage, tint: .red) {
                        model.errorMessage = nil
                    }
                } else if let notice = model.notice {
                    statusBanner(icon: "info.circle.fill", text: notice, tint: AppTheme.teal) {
                        model.notice = nil
                    }
                }

                if model.isLoadingTrash {
                    ProgressView("Loading Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.papers.isEmpty && model.scope != .excluded {
                    emptyState
                } else if model.filteredPapers.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another library view or search.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.filteredPapers, selection: $model.selectedPaperID) { paper in
                        PaperRow(
                            paper: paper,
                            progress: model.progress(for: paper),
                            onReview: { model.markReviewed(paper) },
                            onSave: { model.toggleSaved(paper) },
                            isTrashed: model.scope == .excluded,
                            onTrash: { model.moveToTrash(paper) },
                            onRestore: { model.restoreExcluded(paper) }
                        )
                        .disabled(!model.canChangeLibrary)
                        .tag(paper.shortID)
                        .contextMenu {
                          if model.scope == .excluded {
                            Button("Restore to library") { model.restoreExcluded(paper) }
                            Button("Delete metadata…", role: .destructive) { deletingPaper = paper }
                          } else {
                            Button(model.favorites.contains(paper.shortID) ? "Remove from Saved" : "Save for later") {
                                model.toggleSaved(paper)
                            }
                            Button("Mark as reviewed") { model.markReviewed(paper) }
                            Button("Move to Inbox") { model.moveToInbox(paper) }
                            Button("Move to Trash", role: .destructive) { model.moveToTrash(paper) }
                          }
                            Divider()
                            Button("Open on arXiv") { model.openPaper(paper) }
                        }
                    }
                    .listStyle(.inset)
                    .onDeleteCommand {
                        guard let paper = model.selectedPaper else { return }
                        if model.scope == .excluded { deletingPaper = paper } else { model.moveToTrash(paper) }
                    }
                }
            }
            .background(AppTheme.canvas(for: colorScheme))
        }
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scopeTitle)
                    .font(.title2.weight(.bold))
                Text("\(model.filteredPapers.count) papers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.scope != .excluded { Button {
                model.scope = .calendar
            } label: {
                Label("Choose dates", systemImage: "calendar")
            }
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No papers yet", systemImage: "calendar")
        } description: {
            Text("Choose one or more dates to begin.")
        } actions: {
            Button("Open calendar") { model.scope = .calendar }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sky)
                .foregroundStyle(Color.black.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if model.scope == .cleanup {
            ContentUnavailableView("Your reading work is protected", systemImage: "checkmark.shield", description: Text("Cleanup moves unrelated, unread papers to Trash. Saved papers, notes and PDFs are kept."))
        } else if model.scope == .calendar {
            ContentUnavailableView(
                "Select dates",
                systemImage: "calendar.badge.clock",
                description: Text("Searched dates show their paper count and last search time.")
            )
        } else if let paper = model.selectedPaper {
          VStack(spacing: 0) {
            if model.scope == .excluded {
                HStack {
                    Text("In Trash").font(.caption)
                    Spacer()
                    Button("Restore") { model.restoreExcluded(paper) }
                    Button("Delete…", role: .destructive) { deletingPaper = paper }
                }.padding(12)
                Divider()
            }
            PaperDetailView(model: model, paper: paper)
                .id(paper.shortID + (paper.abstractKO ?? "") + model.progress(for: paper).note)
          }
        } else {
            ContentUnavailableView(
                "Select a paper",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Review its abstract, then save it or mark it reviewed.")
            )
        }
    }

    private func statusBanner(icon: String, text: String, tint: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
        }
        .padding(10)
        .background(tint.opacity(0.08))
    }

    private var scopeTitle: String {
        switch model.scope {
        case .inbox: "Inbox"
        case .new: "New"
        case .reviewed: "Reviewed"
        case .saved: "Saved"
        case let .collection(id): model.library.collections.first(where: { $0.id == id })?.name ?? "Collection"
        case let .topic(id): settings.researchTopics.first { $0.id == id }?.name ?? "Topic"
        case .calendar: "Discovery calendar"
        case .all: "All papers"
        case let .subject(subject): subject
        case .cleanup: "Cleanup"
        case .excluded: "Trash"
        }
    }
}

private struct PaperRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    let progress: PaperProgress
    let onReview: () -> Void
    let onSave: () -> Void
    let isTrashed: Bool
    let onTrash: () -> Void
    let onRestore: () -> Void
    private var isSaved: Bool { progress.savedAt != nil || progress.disposition == .saved }
    private var isReviewed: Bool { progress.reviewedAt != nil || progress.disposition == .reviewed }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if progress.firstViewedAt == nil && !isTrashed {
                        Circle()
                            .fill(AppTheme.sky)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("New")
                    }
                    Text(paper.title)
                        .font(.headline)
                        .lineLimit(3)
                }
                Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " +\(paper.authors.count - 3)" : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(paper.subjects.first ?? "Uncategorized")
                    Text(paper.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    if paper.abstractKO != nil { Text("KO") }
                    if !progress.note.isEmpty { Image(systemName: "note.text") }
                    if isSaved { Text("Saved") }
                    if isReviewed { Text("Reviewed") }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 10) {
              if isTrashed {
                Button(action: onRestore) { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Restore to library").accessibilityLabel("Restore to library")
              } else {
                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSaved ? (colorScheme == .light ? AppTheme.skyInk : AppTheme.sky) : .secondary)
                .accessibilityLabel(isSaved ? "Remove from Saved" : "Save for later")
                .help(isSaved ? "Remove bookmark; keep paper and notes" : "Save for later; does not download a PDF")

                Button(action: onReview) {
                    Image(systemName: isReviewed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isReviewed ? AppTheme.teal : .secondary)
                .accessibilityLabel("Mark as reviewed")
                .help("Mark reviewed; keep bookmark, collections and notes")
                Button(role: .destructive, action: onTrash) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Move to Trash; restore anytime").accessibilityLabel("Move to Trash")
              }
            }.frame(width: 24)
        }
        .padding(.vertical, 6)
    }
}
