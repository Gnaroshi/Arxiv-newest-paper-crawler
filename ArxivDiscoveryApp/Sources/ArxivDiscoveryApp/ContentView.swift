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

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } content: {
            candidateColumn
                .navigationSplitViewColumnWidth(min: 430, ideal: 520, max: 720)
        } detail: {
            detailColumn
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
                } label: {
                    Label("Library options", systemImage: "ellipsis.circle")
                }
            }
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
                        .badge(model.papers.count)
                        .tag(LibraryScope.all)
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

                Section("Topics") {
                    ForEach(SmartTopic.allCases) { topic in
                        Label(topic.label, systemImage: topic == .vla ? "figure.walk.motion" : "globe.americas")
                            .badge(model.topicCount(topic))
                            .tag(LibraryScope.topic(topic))
                    }
                }

                if !model.observedSubjects.isEmpty {
                    Section("Subjects") {
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
                Text(settings.geminiModel)
                    .font(.caption)
                    .lineLimit(1)
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

                if model.papers.isEmpty {
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
                            onSave: { model.toggleSaved(paper) }
                        )
                        .tag(paper.shortID)
                        .contextMenu {
                            Button(model.favorites.contains(paper.shortID) ? "Remove from Saved" : "Save for later") {
                                model.toggleSaved(paper)
                            }
                            Button("Mark as reviewed") { model.markReviewed(paper) }
                            Button("Move to Inbox") { model.moveToInbox(paper) }
                            Divider()
                            Button("Open on arXiv") { model.openPaper(paper) }
                        }
                    }
                    .listStyle(.inset)
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
            Button {
                model.scope = .calendar
            } label: {
                Label("Choose dates", systemImage: "calendar")
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
        if model.scope == .calendar {
            ContentUnavailableView(
                "Select dates",
                systemImage: "calendar.badge.clock",
                description: Text("Searched dates show their paper count and last search time.")
            )
        } else if let paper = model.selectedPaper {
            PaperDetailView(model: model, paper: paper)
                .id(paper.shortID + (paper.abstractKO ?? "") + model.progress(for: paper).note)
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
        case let .topic(topic): topic.label
        case .calendar: "Discovery calendar"
        case .all: "All papers"
        case let .subject(subject): subject
        }
    }
}

private struct PaperRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    let progress: PaperProgress
    let onReview: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if progress.firstViewedAt == nil {
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
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 10) {
                Button(action: onSave) {
                    Image(systemName: progress.disposition == .saved ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(progress.disposition == .saved ? (colorScheme == .light ? AppTheme.skyInk : AppTheme.sky) : .secondary)
                .accessibilityLabel(progress.disposition == .saved ? "Remove from Saved" : "Save for later")

                Button(action: onReview) {
                    Image(systemName: progress.disposition == .reviewed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(progress.disposition == .reviewed ? AppTheme.teal : .secondary)
                .accessibilityLabel("Mark as reviewed")
            }
        }
        .padding(.vertical, 6)
    }
}
