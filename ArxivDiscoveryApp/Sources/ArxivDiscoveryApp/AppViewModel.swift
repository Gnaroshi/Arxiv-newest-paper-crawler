import AppKit
import ArxivDiscoveryCore
import Foundation

enum LibraryScope: Hashable {
    case inbox
    case new
    case reviewed
    case saved
    case collection(String)
    case topic(SmartTopic)
    case calendar
    case all
    case subject(String)
    case cleanup
    case excluded
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var papers: [Paper] = []
    @Published private(set) var library = LibraryState()
    @Published private(set) var discoveryHistory = DiscoveryHistory()
    @Published private(set) var translationUsage = TranslationUsageLedger()
    @Published private(set) var cleanupState = TopicCleanupState()
    @Published private(set) var cleanupPreview: TopicCleanupPreview?
    @Published private(set) var isCleaning = false
    @Published private(set) var availableGeminiModels: [GeminiModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var geminiConfigured = false
    @Published var selectedPaperID: String?
    @Published var selectedDiscoveryDays: Set<String> = [DiscoveryDate.key(for: Date())]
    @Published var scope: LibraryScope = .inbox
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
    private let gemini = GeminiClient()
    private let keychain = KeychainStore()
    private let version: String

    init(
        settings: AppSettings,
        repository: PaperRepository = PaperRepository(),
        client: ArxivSearching = ArxivClient(),
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
    ) {
        self.settings = settings
        self.repository = repository
        self.client = client
        self.version = version
        load()
    }

    var favorites: Set<String> { library.savedPaperIDs }

    var filteredPapers: [Paper] {
        papers.filter { paper in
            let excluded = cleanupState.excluded[paper.shortID] != nil
            if scope != .excluded && excluded { return false }
            let progress = library.progress(for: paper.shortID)
            let matchesScope: Bool
            switch scope {
            case .inbox: matchesScope = progress.disposition == .inbox
            case .new: matchesScope = progress.disposition == .inbox && progress.firstViewedAt == nil
            case .reviewed: matchesScope = progress.disposition == .reviewed
            case .saved: matchesScope = progress.disposition == .saved
            case let .collection(id): matchesScope = progress.collectionIDs.contains(id)
            case let .topic(topic): matchesScope = topic.matches(paper)
            case .calendar: matchesScope = false
            case .all: matchesScope = true
            case let .subject(subject): matchesScope = paper.subjects.contains(subject)
            case .cleanup: matchesScope = false
            case .excluded: matchesScope = excluded
            }
            guard matchesScope else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return paper.title.localizedCaseInsensitiveContains(query)
                || paper.authors.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || paper.abstract.localizedCaseInsensitiveContains(query)
                || progress.note.localizedCaseInsensitiveContains(query)
                || paper.subjects.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var observedSubjects: [String] {
        let observed = Set(activePapers.flatMap(\.subjects))
        return AppSettings.categories.filter { observed.contains($0) }
    }

    var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return papers.first(where: { $0.shortID == selectedPaperID })
    }

    var activePapers: [Paper] { papers.filter { cleanupState.excluded[$0.shortID] == nil } }
    var excludedCount: Int { papers.count - activePapers.count }
    var inboxCount: Int { count { $0.disposition == .inbox } }
    var newCount: Int { activePapers.lazy.filter { self.library.progress(for: $0.shortID).disposition == .inbox && self.library.progress(for: $0.shortID).firstViewedAt == nil }.count }
    var reviewedCount: Int { count { $0.disposition == .reviewed } }
    var savedCount: Int { count { $0.disposition == .saved } }

    var todayUsage: TranslationUsageRecord {
        translationUsage.summary(for: DiscoveryDate.key(for: Date()))
    }

    var unsearchedRecentCount: Int {
        let categories = settings.enabledCategories
        return DiscoveryDate.recentKeys(count: 30).filter { key in
            discoveryHistory.days[key]?.covers(mode: settings.discoveryMode, categories: categories, topics: settings.enabledTopics) != true
        }.count
    }

    func progress(for paper: Paper) -> PaperProgress {
        library.progress(for: paper.shortID)
    }

    func collectionCount(_ collectionID: String) -> Int {
        activePapers.lazy.filter { self.library.progress(for: $0.shortID).collectionIDs.contains(collectionID) }.count
    }

    func topicCount(_ topic: SmartTopic) -> Int {
        activePapers.lazy.filter(topic.matches).count
    }

    func recordSelection() {
        guard let selectedPaperID else { return }
        let before = library.progress(for: selectedPaperID).firstViewedAt
        library.markViewed(selectedPaperID)
        if before == nil { persistLibrary() }
    }

    func reconcileSelection() {
        guard let selectedPaperID,
              filteredPapers.contains(where: { $0.shortID == selectedPaperID }) == false
        else { return }
        self.selectedPaperID = nil
    }

    func searchSelectedDates() {
        guard !isDiscovering, !isCleaning, !ShowcaseMode.isEnabled else { return }
        guard settings.discoveryMode != .topics || !settings.enabledTopics.isEmpty else {
            errorMessage = "가져올 연구 주제를 하나 이상 선택하세요."
            return
        }
        guard settings.discoveryMode != .categories || !settings.enabledCategories.isEmpty else {
            errorMessage = "가져올 arXiv 분야 태그를 하나 이상 선택하세요."
            return
        }
        let validKeys = selectedDiscoveryDays
            .filter { key in
                guard let date = DiscoveryDate.date(from: key) else { return false }
                return date <= Date()
            }
            .sorted()
        guard !validKeys.isEmpty else {
            errorMessage = "Select at least one date."
            return
        }

        isDiscovering = true
        errorMessage = nil
        notice = nil
        let categories = settings.enabledCategories.sorted()
        let mode = settings.discoveryMode
        let topics = settings.enabledTopics.sorted { $0.rawValue < $1.rawValue }
        Task {
            var merged = papers
            var updatedHistory = discoveryHistory
            var totalFound = 0
            var failures: [String] = []
            for key in validKeys {
                guard let interval = DiscoveryDate.interval(for: key) else { continue }
                let query = DiscoveryQuery(interval: interval, maxResults: 500, categories: categories, mode: mode, topics: topics)
                do {
                    let searchedAt = Date()
                    let batch = try await client.discoverBatch(query: query, now: searchedAt)
                    let discovered = batch.papers
                    merged = repository.merge(existing: merged, discovered: discovered)
                    totalFound += discovered.count
                    updatedHistory.record(.init(
                        day: key,
                        lastSearchedAt: searchedAt,
                        paperCount: discovered.count,
                        categories: categories,
                        isComplete: batch.isComplete,
                        mode: mode,
                        topics: topics
                    ))
                } catch {
                    failures.append(key)
                }
            }
            do {
                updatedHistory.prune()
                merged = repository.prunedPapers(
                    merged,
                    library: library,
                    retentionDays: settings.cacheRetentionDays,
                    excludedIDs: Set(cleanupState.excluded.keys)
                )
                try repository.savePapers(merged)
                try repository.saveDiscoveryHistory(updatedHistory)
                papers = merged
                discoveryHistory = updatedHistory
                lastRefresh = Date()
                if failures.isEmpty {
                    notice = "Found \(totalFound) papers across \(validKeys.count) selected date\(validKeys.count == 1 ? "" : "s")."
                } else {
                    errorMessage = "Search finished, but \(failures.joined(separator: ", ")) could not be fetched."
                }
                try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
            } catch {
                errorMessage = "Local data could not be updated. \(error.localizedDescription)"
                try? writeStatus(availability: papers.isEmpty ? "unavailable" : "partial", errorCode: "discovery_save_failed")
            }
            isDiscovering = false
        }
    }

    func previewCleanup() {
        cleanupPreview = nil
        do {
            cleanupPreview = try repository.previewTopicCleanup(
                topics: settings.enabledTopics.sorted { $0.rawValue < $1.rawValue },
                papers: papers,
                library: library,
                state: cleanupState
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyCleanup() {
        guard !isDiscovering, !isCleaning, !ShowcaseMode.isEnabled else { return }
        isCleaning = true
        defer { isCleaning = false }
        do {
            let result = try repository.applyTopicCleanup(
                topics: settings.enabledTopics.sorted { $0.rawValue < $1.rawValue },
                applicationVersion: version
            )
            cleanupState = try repository.loadCleanupState()
            reconcileSelection()
            previewCleanup()
            notice = "관련 없는 미열람 논문 \(result.excludedCount)편을 제외했습니다. 제외됨에서 복구할 수 있습니다."
            try? writeStatus(availability: activePapers.isEmpty ? "empty" : "ready")
        } catch { errorMessage = "정리를 완료하지 못했습니다. \(error.localizedDescription)" }
    }

    func restoreLastCleanup() {
        guard !isDiscovering, !isCleaning, !ShowcaseMode.isEnabled else { return }
        do {
            let count = try repository.restoreLastTopicCleanup()
            cleanupState = try repository.loadCleanupState()
            previewCleanup()
            notice = "최근 정리에서 제외한 \(count)편을 복구했습니다."
            try? writeStatus(availability: activePapers.isEmpty ? "empty" : "ready")
        } catch { errorMessage = "복구하지 못했습니다. \(error.localizedDescription)" }
    }

    func restoreExcluded(_ paper: Paper) {
        do {
            try repository.restoreExcludedPaper(paper.shortID)
            cleanupState = try repository.loadCleanupState()
            notice = "Inbox에 복구했습니다."
            reconcileSelection()
            try? writeStatus(availability: "ready")
        } catch { errorMessage = "복구하지 못했습니다. \(error.localizedDescription)" }
    }

    func markReviewed(_ paper: Paper) {
        guard restoreBeforeKeeping(paper) else { return }
        library.markReviewed(paper.shortID)
        persistLibrary(notice: "Moved to Reviewed.")
        advance(after: paper)
    }

    func moveToInbox(_ paper: Paper) {
        guard restoreBeforeKeeping(paper) else { return }
        library.moveToInbox(paper.shortID)
        persistLibrary(notice: "Moved to Inbox.")
    }

    func toggleSaved(_ paper: Paper) {
        guard restoreBeforeKeeping(paper) else { return }
        let saving = library.progress(for: paper.shortID).disposition != .saved
        library.setSaved(saving, paperID: paper.shortID)
        persistLibrary(notice: saving ? "Saved for later." : "Moved to Inbox.")
        if !saving { advance(after: paper) }
    }

    @discardableResult
    func createCollection(named name: String, adding paper: Paper? = nil) -> Bool {
        guard let collection = library.createCollection(named: name) else {
            errorMessage = "Use a non-empty, unique collection name."
            return false
        }
        if let paper { library.setCollection(collection.id, contains: paper.shortID, enabled: true) }
        persistLibrary(notice: "Collection created.")
        return true
    }

    func setCollection(_ collectionID: String, contains paper: Paper, enabled: Bool) {
        library.setCollection(collectionID, contains: paper.shortID, enabled: enabled)
        persistLibrary()
    }

    func saveNote(_ note: String, for paper: Paper) {
        library.setNote(note, paperID: paper.shortID)
        persistLibrary(notice: "Note saved.")
    }

    func importLegacy(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try repository.importLegacy(papers: url)
            papers = try repository.loadPapers()
            library = try repository.loadLibraryState()
            notice = "Imported \(result.importedPaperCount) papers and \(result.importedFavoriteCount) saved IDs."
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
            let selectedModel = settings.geminiModel
            Task {
                defer { translatingPaperID = nil }
                do {
                    let result = try await gemini.translate(paper, model: selectedModel, apiKey: apiKey)
                    guard let index = papers.firstIndex(where: { $0.shortID == paper.shortID }) else { return }
                    papers[index].abstractKO = result.text
                    translationUsage.record(model: selectedModel, usage: result.usage)
                    try repository.savePapers(papers)
                    try repository.saveTranslationUsage(translationUsage)
                    notice = "Korean abstract saved locally."
                } catch {
                    errorMessage = "Translation failed. \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "The Gemini key could not be read from Keychain."
        }
    }

    func refreshGeminiModels() {
        guard !isLoadingModels else { return }
        do {
            guard let apiKey = try keychain.read(), !apiKey.isEmpty else {
                geminiConfigured = false
                availableGeminiModels = []
                return
            }
            geminiConfigured = true
            isLoadingModels = true
            Task {
                defer { isLoadingModels = false }
                do {
                    availableGeminiModels = try await gemini.listModels(apiKey: apiKey)
                    if !availableGeminiModels.contains(where: { $0.modelID == settings.geminiModel }),
                       let first = availableGeminiModels.first {
                        settings.geminiModel = first.modelID
                    }
                } catch {
                    errorMessage = "Models could not be loaded. \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "The Gemini key could not be read from Keychain."
        }
    }

    func geminiKeyDidChange() {
        geminiConfigured = (try? keychain.read())?.isEmpty == false
        if geminiConfigured { refreshGeminiModels() }
        else { availableGeminiModels = [] }
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
                let destination = try repository.storeDownloadedPDF(
                    from: temporaryURL,
                    for: paper,
                    style: settings.pdfNameStyle
                )
                notice = "PDF downloaded as \(destination.lastPathComponent)."
                NSWorkspace.shared.open(destination)
            } catch {
                errorMessage = "PDF download failed. \(error.localizedDescription)"
            }
        }
    }

    func openPDF(_ paper: Paper) {
        if let local = repository.existingPDFURL(for: paper, preferredStyle: settings.pdfNameStyle) {
            NSWorkspace.shared.open(local)
        } else {
            downloadPDF(paper)
        }
    }

    func hasLocalPDF(_ paper: Paper) -> Bool {
        repository.existingPDFURL(for: paper, preferredStyle: settings.pdfNameStyle) != nil
    }

    func openPaper(_ paper: Paper) {
        guard let url = paper.entryURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(repository.rootURL)
    }

    private func count(where predicate: @escaping (PaperProgress) -> Bool) -> Int {
        activePapers.lazy.filter { predicate(self.library.progress(for: $0.shortID)) }.count
    }

    private func persistLibrary(notice: String? = nil) {
        do {
            try repository.saveLibraryState(library)
            if let notice { self.notice = notice }
            try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
        } catch {
            errorMessage = "Your library could not be updated. \(error.localizedDescription)"
        }
    }

    private func restoreBeforeKeeping(_ paper: Paper) -> Bool {
        guard cleanupState.excluded[paper.shortID] != nil else { return true }
        do {
            try repository.restoreExcludedPaper(paper.shortID)
            cleanupState = try repository.loadCleanupState()
            return true
        } catch {
            errorMessage = "논문을 복구하지 못했습니다. \(error.localizedDescription)"
            return false
        }
    }

    private func advance(after paper: Paper) {
        guard selectedPaperID == paper.shortID else { return }
        selectedPaperID = filteredPapers.first(where: { $0.shortID != paper.shortID })?.shortID
        recordSelection()
    }

    private func load() {
        if ShowcaseMode.isEnabled {
            papers = ShowcaseMode.papers
            library.setSaved(true, paperID: ShowcaseMode.papers[1].shortID)
            library.markViewed(ShowcaseMode.papers[0].shortID)
            selectedPaperID = ShowcaseMode.papers.first?.shortID
            lastRefresh = ShowcaseMode.papers.first?.crawledAt
            return
        }
        do {
            papers = try repository.loadPapers()
            library = try repository.loadLibraryState()
            discoveryHistory = try repository.loadDiscoveryHistory()
            translationUsage = try repository.loadTranslationUsage()
            cleanupState = try repository.loadCleanupState()
            selectedPaperID = nil
            lastRefresh = try repository.loadStatus()?.lastRefresh
            geminiConfigured = (try? keychain.read())?.isEmpty == false
            try repository.saveLibraryState(library)
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
                paperCount: activePapers.count,
                favoriteCount: savedCount,
                availability: availability,
                lastErrorCode: errorCode
            )
        )
    }
}
