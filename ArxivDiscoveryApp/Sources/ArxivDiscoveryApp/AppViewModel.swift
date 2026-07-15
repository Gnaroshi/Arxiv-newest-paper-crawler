import AppKit
import ArxivDiscoveryCore
import Foundation

enum LibraryScope: Hashable {
    case all
    case saved
    case subject(String)
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var papers: [Paper] = []
    @Published private(set) var favorites: Set<String> = []
    @Published var selectedPaperID: String?
    @Published var scope: LibraryScope = .all
    @Published var searchText = ""
    @Published private(set) var isDiscovering = false
    @Published private(set) var translatingPaperID: String?
    @Published private(set) var downloadingPaperID: String?
    @Published private(set) var lastRefresh: Date?
    @Published var notice: String?
    @Published var errorMessage: String?

    let settings: AppSettings
    let repository: PaperRepository
    private let client: ArxivSearching
    private let keychain = KeychainStore()
    private let version: String

    init(
        settings: AppSettings,
        repository: PaperRepository = PaperRepository(),
        client: ArxivSearching = ArxivClient(),
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
    ) {
        self.settings = settings
        self.repository = repository
        self.client = client
        self.version = version
        load()
    }

    var filteredPapers: [Paper] {
        papers.filter { paper in
            let matchesScope: Bool
            switch scope {
            case .all: matchesScope = true
            case .saved: matchesScope = favorites.contains(paper.shortID)
            case let .subject(subject): matchesScope = paper.subjects.contains(subject)
            }
            guard matchesScope else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return paper.title.localizedCaseInsensitiveContains(query)
                || paper.authors.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || paper.abstract.localizedCaseInsensitiveContains(query)
                || paper.subjects.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var observedSubjects: [String] {
        let observed = Set(papers.flatMap(\.subjects))
        return AppSettings.categories.filter { observed.contains($0) }
    }

    var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return papers.first(where: { $0.shortID == selectedPaperID })
    }

    func discover() {
        guard !isDiscovering, !ShowcaseMode.isEnabled else { return }
        isDiscovering = true
        errorMessage = nil
        notice = nil
        let query = settings.discoveryQuery
        Task {
            do {
                let discovered = try await client.discover(query: query, now: Date())
                let merged = repository.merge(existing: papers, discovered: discovered)
                try repository.savePapers(merged)
                papers = merged
                lastRefresh = Date()
                if selectedPaperID == nil { selectedPaperID = discovered.first?.shortID ?? merged.first?.shortID }
                notice = discovered.isEmpty
                    ? "No papers were published in the selected window. Existing local papers were kept."
                    : "Found \(discovered.count) paper\(discovered.count == 1 ? "" : "s") in the selected window."
                try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
            } catch {
                errorMessage = error.localizedDescription
                try? writeStatus(availability: papers.isEmpty ? "unavailable" : "partial", errorCode: "discovery_failed")
            }
            isDiscovering = false
        }
    }

    func toggleFavorite(_ paper: Paper) {
        if favorites.contains(paper.shortID) {
            favorites.remove(paper.shortID)
        } else {
            favorites.insert(paper.shortID)
        }
        do {
            try repository.saveFavorites(favorites)
            try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
        } catch {
            errorMessage = "The saved-paper list could not be updated. \(error.localizedDescription)"
        }
    }

    func importLegacy(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try repository.importLegacy(papers: url)
            papers = try repository.loadPapers()
            favorites = try repository.loadFavorites()
            if selectedPaperID == nil { selectedPaperID = papers.first?.shortID }
            notice = "Imported \(result.importedPaperCount) new papers and \(result.importedFavoriteCount) saved IDs."
            try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
        } catch {
            errorMessage = "The selected JSON could not be imported. \(error.localizedDescription)"
        }
    }

    func translate(_ paper: Paper) {
        guard translatingPaperID == nil else { return }
        do {
            guard let apiKey = try keychain.read(), !apiKey.isEmpty else {
                errorMessage = "Add a Gemini API key in Settings before translating."
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                return
            }
            translatingPaperID = paper.shortID
            errorMessage = nil
            Task {
                defer { translatingPaperID = nil }
                do {
                    let translation = try await GeminiTranslator(model: settings.geminiModel).translate(paper, apiKey: apiKey)
                    guard let index = papers.firstIndex(where: { $0.shortID == paper.shortID }) else { return }
                    papers[index].abstractKO = translation
                    try repository.savePapers(papers)
                    notice = "Korean abstract saved locally."
                } catch {
                    errorMessage = "Translation failed. \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "The Gemini key could not be read from Keychain."
        }
    }

    func downloadPDF(_ paper: Paper) {
        guard downloadingPaperID == nil, let url = paper.downloadablePDFURL else { return }
        downloadingPaperID = paper.shortID
        errorMessage = nil
        Task {
            defer { downloadingPaperID = nil }
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode)
                else { throw URLError(.badServerResponse) }
                let destination = try repository.storeDownloadedPDF(from: temporaryURL, for: paper)
                notice = "PDF downloaded."
                NSWorkspace.shared.open(destination)
            } catch {
                errorMessage = "PDF download failed. \(error.localizedDescription)"
            }
        }
    }

    func openPDF(_ paper: Paper) {
        let local = repository.pdfURL(for: paper)
        if FileManager.default.fileExists(atPath: local.path) {
            NSWorkspace.shared.open(local)
        } else {
            downloadPDF(paper)
        }
    }

    func hasLocalPDF(_ paper: Paper) -> Bool {
        FileManager.default.fileExists(atPath: repository.pdfURL(for: paper).path)
    }

    func openPaper(_ paper: Paper) {
        guard let url = paper.entryURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(repository.rootURL)
    }

    private func load() {
        if ShowcaseMode.isEnabled {
            papers = ShowcaseMode.papers
            favorites = [ShowcaseMode.papers[1].shortID]
            selectedPaperID = ShowcaseMode.papers.first?.shortID
            lastRefresh = ShowcaseMode.papers.first?.crawledAt
            notice = "Showcase data · no network requests or downloads"
            return
        }
        do {
            papers = try repository.loadPapers()
            favorites = try repository.loadFavorites()
            selectedPaperID = papers.first?.shortID
            lastRefresh = try repository.loadStatus()?.lastRefresh
            try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
        } catch {
            errorMessage = "Local data could not be loaded. \(error.localizedDescription)"
            try? writeStatus(availability: "unavailable", errorCode: "local_data_unreadable")
        }
    }

    private func writeStatus(availability: String, errorCode: String? = nil) throws {
        try repository.saveStatus(
            IntegrationSnapshot(
                providerVersion: version,
                lastRefresh: lastRefresh,
                paperCount: papers.count,
                favoriteCount: favorites.count,
                availability: availability,
                lastErrorCode: errorCode
            )
        )
    }
}
