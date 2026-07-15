import ArxivDiscoveryCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var importingLegacy = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } content: {
            candidateColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppTheme.canvas(for: colorScheme))
        .preferredColorScheme(settings.appearance.colorScheme)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Title, author, subject, or abstract")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    importingLegacy = true
                } label: {
                    Label("Import legacy JSON", systemImage: "square.and.arrow.down")
                }
                .help("Import a previous papers.json without modifying it")

                Button {
                    model.openDataFolder()
                } label: {
                    Label("Open data folder", systemImage: "folder")
                }
                .help("Open the app-owned local data folder")
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
    }

    private var sidebar: some View {
        List(selection: $model.scope) {
            Section("Library") {
                Label("All papers", systemImage: "tray.full")
                    .badge(model.papers.count)
                    .tag(LibraryScope.all)
                Label("Saved", systemImage: "bookmark")
                    .badge(model.favorites.count)
                    .tag(LibraryScope.saved)
            }

            if !model.observedSubjects.isEmpty {
                Section("Subjects") {
                    ForEach(model.observedSubjects, id: \.self) { subject in
                        Label(subject, systemImage: "number")
                            .tag(LibraryScope.subject(subject))
                    }
                }
            }

            Section("Discovery") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Public arXiv metadata", systemImage: "network")
                        .font(.caption.weight(.semibold))
                    Text("PDF · translation: manual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Arxiv Discovery")
    }

    private var candidateColumn: some View {
        VStack(spacing: 0) {
            discoveryHeader
            Divider()

            if let errorMessage = model.errorMessage {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: errorMessage,
                    tint: .red,
                    dismiss: { model.errorMessage = nil }
                )
            } else if let notice = model.notice {
                statusBanner(
                    icon: "info.circle.fill",
                    text: notice,
                    tint: AppTheme.teal,
                    dismiss: { model.notice = nil }
                )
            }

            if model.papers.isEmpty {
                emptyState
            } else if model.filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No matching papers",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the library filter or search text.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.filteredPapers, selection: $model.selectedPaperID) { paper in
                    PaperRow(
                        paper: paper,
                        isSaved: model.favorites.contains(paper.shortID)
                    )
                    .tag(paper.shortID)
                    .contextMenu {
                        Button(model.favorites.contains(paper.shortID) ? "Remove from Saved" : "Save Paper") {
                            model.toggleFavorite(paper)
                        }
                        Button("Open on arXiv") { model.openPaper(paper) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(AppTheme.canvas(for: colorScheme))
    }

    private var discoveryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(scopeTitle)
                        .font(.title2.weight(.bold))
                    Text(refreshSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("Recent window", selection: Binding(
                    get: { settings.days },
                    set: { settings.days = $0 }
                )) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                }
                .labelsHidden()
                .frame(width: 94)
                .disabled(model.isDiscovering || ShowcaseMode.isEnabled)
            }

            Button {
                model.discover()
            } label: {
                HStack {
                    if model.isDiscovering {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    Text(model.isDiscovering ? "Finding papers…" : "Find recent papers")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.sky)
            .foregroundStyle(Color.black.opacity(0.82))
            .disabled(model.isDiscovering || ShowcaseMode.isEnabled)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No papers yet", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("Find a bounded list of public arXiv metadata. Discovery does not download PDFs or call Gemini.")
        } actions: {
            Button("Find recent papers") { model.discover() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sky)
                .foregroundStyle(Color.black.opacity(0.82))
            Button("Import previous papers.json") { importingLegacy = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let paper = model.selectedPaper {
            PaperDetailView(model: model, paper: paper)
                .id(paper.shortID + (paper.abstractKO ?? ""))
        } else {
            ContentUnavailableView(
                "Select a paper",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose one candidate to inspect its metadata and abstract.")
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
        case .all: "All papers"
        case .saved: "Saved papers"
        case let .subject(subject): subject
        }
    }

    private var refreshSummary: String {
        if model.isDiscovering { return "Requesting public metadata from arXiv" }
        if let lastRefresh = model.lastRefresh {
            return "\(model.filteredPapers.count) visible · refreshed \(lastRefresh.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(model.filteredPapers.count) visible · not refreshed in this app yet"
    }
}

private struct PaperRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(3)
                Spacer(minLength: 4)
                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(colorScheme == .light ? AppTheme.skyInk : AppTheme.sky)
                        .accessibilityLabel("Saved")
                }
            }
            Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " +\(paper.authors.count - 3)" : ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(paper.subjects.first ?? "Uncategorized")
                Text(paper.publishedAt.formatted(date: .abbreviated, time: .omitted))
                if paper.abstractKO != nil { Text("KO") }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
