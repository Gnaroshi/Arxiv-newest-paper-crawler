import ArxivDiscoveryCore
import SwiftUI

@main
struct ArxivDiscoveryApplication: App {
    @StateObject private var model = DiscoveryModel()

    var body: some Scene {
        WindowGroup("Arxiv Discovery") {
            DiscoveryView(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Settings {
            DiscoverySettingsView(model: model)
                .frame(width: 480)
                .padding(24)
        }
    }
}

@MainActor
final class DiscoveryModel: ObservableObject {
    enum State: Equatable {
        case ready
        case loading
        case loaded(Date)
        case failed(String)
    }

    @Published var categoriesText: String
    @Published var days: Int
    @Published var maxResults: Int
    @Published var search = ""
    @Published var candidates: [ArxivCandidate] = []
    @Published var selection: ArxivCandidate.ID?
    @Published private(set) var state: State = .ready

    private let client = ArxivAPIClient()
    private let defaults = UserDefaults.standard

    init() {
        categoriesText = UserDefaults.standard.string(forKey: "discovery.categories") ?? "cs.AI, cs.CL"
        let storedDays = UserDefaults.standard.integer(forKey: "discovery.days")
        let storedLimit = UserDefaults.standard.integer(forKey: "discovery.maxResults")
        days = storedDays == 0 ? 2 : storedDays
        maxResults = storedLimit == 0 ? 100 : storedLimit
    }

    var filteredCandidates: [ArxivCandidate] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return candidates }
        return candidates.filter { candidate in
            ([candidate.title, candidate.arxivId] + candidate.authors + candidate.categories)
                .joined(separator: " ").lowercased().contains(needle)
        }
    }

    var selectedCandidate: ArxivCandidate? {
        guard let selection else { return nil }
        return candidates.first { $0.id == selection }
    }

    func discover() async {
        guard state != .loading else { return }
        state = .loading
        let query = DiscoveryQuery(
            categories: categoriesText.split(separator: ",").map(String.init),
            days: days,
            maxResults: maxResults
        )
        do {
            candidates = try await client.discover(query)
            selection = candidates.first?.id
            defaults.set(categoriesText, forKey: "discovery.categories")
            defaults.set(days, forKey: "discovery.days")
            defaults.set(maxResults, forKey: "discovery.maxResults")
            state = .loaded(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct DiscoveryView: View {
    @ObservedObject var model: DiscoveryModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                discoveryControls
                Divider()
                candidateList
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
        } detail: {
            if let candidate = model.selectedCandidate {
                CandidateDetail(candidate: candidate)
            } else {
                ContentUnavailableView(
                    model.candidates.isEmpty ? "Discover papers" : "Select a paper",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(model.candidates.isEmpty ? "Choose a discovery window, then fetch recent arXiv metadata. No PDFs are downloaded." : "Choose a candidate to review its abstract and source link.")
                )
            }
        }
        .navigationTitle("Arxiv Discovery")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.discover() } } label: {
                    if model.state == .loading { ProgressView().controlSize(.small) }
                    else { Label("Discover", systemImage: "sparkle.magnifyingglass") }
                }
                .disabled(model.state == .loading)
            }
        }
    }

    private var discoveryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent paper candidates")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Filter title, author, category", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                Text("\(model.filteredCandidates.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 28)
            }
            statusLine
        }
        .padding(14)
    }

    @ViewBuilder private var statusLine: some View {
        switch model.state {
        case .ready:
            Text("Ready · metadata only · no download")
                .foregroundStyle(.secondary)
        case .loading:
            Text("Fetching recent metadata from arXiv…")
                .foregroundStyle(.secondary)
        case .loaded(let date):
            Text("Updated \(date.formatted(date: .omitted, time: .shortened)) · \(model.candidates.count) candidates")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var candidateList: some View {
        List(model.filteredCandidates, selection: $model.selection) { candidate in
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title).fontWeight(.semibold).lineLimit(2)
                Text(candidate.authors.prefix(3).joined(separator: ", "))
                    .foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text(candidate.arxivId).monospaced()
                    Spacer()
                    Text(candidate.categories.prefix(2).joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(candidate.id)
        }
        .overlay {
            if model.candidates.isEmpty && model.state != .loading { Color.clear }
        }
    }
}

private struct CandidateDetail: View {
    let candidate: ArxivCandidate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(candidate.title).font(.title2).fontWeight(.bold).textSelection(.enabled)
                Text(candidate.authors.joined(separator: ", ")).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Label(candidate.arxivId, systemImage: "number")
                    Text(candidate.categories.joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                Text("Abstract").font(.headline)
                Text(candidate.abstract).font(.body).lineSpacing(4).textSelection(.enabled)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Viewing metadata does not download or hand off this paper.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link(destination: candidate.paperUrl) { Label("Open on arXiv", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.bar)
        }
    }
}

private struct DiscoverySettingsView: View {
    @ObservedObject var model: DiscoveryModel

    var body: some View {
        Form {
            TextField("Categories", text: $model.categoriesText)
            Stepper("Discovery window: \(model.days) day\(model.days == 1 ? "" : "s")", value: $model.days, in: 1...31)
            Stepper("Maximum results: \(model.maxResults)", value: $model.maxResults, in: 10...200, step: 10)
            Text("Categories are comma-separated arXiv identifiers such as cs.AI and cs.CL. These settings affect the next discovery only; downloads remain disabled.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
