import AppKit
import ArxivDiscoveryCore
import Foundation
import Combine

enum LibraryScope: Hashable {
    case inbox
    case new
    case reviewed
    case saved
    case collection(String)
    case topic(String)
    case calendar
    case all
    case subject(String)
    case cleanup
    case excluded
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var papers: [Paper] = [] { didSet { rebuildIndex() } }
    @Published private(set) var library = LibraryState() { didSet { refreshFilteredPapers() } }
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
    @Published var scope: LibraryScope = .inbox { didSet { scopeDidChange() } }
    @Published var searchText = "" { didSet { scheduleSearch() } }
    @Published private(set) var filteredPapers: [Paper] = []
    @Published private(set) var activePapers: [Paper] = []
    @Published private(set) var isLoadingTrash = false
    private var trashPapers: [Paper] = []
    private var trashSearchText: [String: String] = [:]
    private var trashLoaded = false
    private var searchIndex = PaperSearchIndex(papers: [], topics: [])
    private var byID: [String: Paper] = [:]
    private var cachedCollectionCounts: [String: Int] = [:]
    @Published private(set) var inboxCount = 0
    @Published private(set) var newCount = 0
    @Published private(set) var reviewedCount = 0
    @Published private(set) var savedCount = 0
    @Published private(set) var excludedCount = 0
    @Published private(set) var observedSubjects: [String] = []
    private var topicSubscription: AnyCancellable?
    private var searchTask: Task<Void, Never>?
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
        topicSubscription = settings.$researchTopics.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuildIndex() }
    }

    var favorites: Set<String> { library.savedPaperIDs }

    private func refreshFilteredPapers() {
        inboxCount = 0; newCount = 0; reviewedCount = 0; savedCount = 0
        cachedCollectionCounts = [:]
        for paper in activePapers {
            let progress = library.progress(for: paper.shortID)
            if progress.disposition == .inbox { inboxCount += 1; if progress.firstViewedAt == nil { newCount += 1 } }
            if progress.reviewedAt != nil || progress.disposition == .reviewed { reviewedCount += 1 }
            if progress.savedAt != nil || progress.disposition == .saved { savedCount += 1 }
            for id in progress.collectionIDs { cachedCollectionCounts[id, default: 0] += 1 }
        }
        let source = scope == .excluded ? trashPapers : activePapers
        let query = ResearchTopic.normalize(searchText)
        filteredPapers = source.filter { paper in
            let excluded = cleanupState.excluded[paper.shortID] != nil
            if scope != .excluded && excluded { return false }
            let progress = library.progress(for: paper.shortID)
            let matchesScope: Bool
            switch scope {
            case .inbox: matchesScope = progress.disposition == .inbox
            case .new: matchesScope = progress.disposition == .inbox && progress.firstViewedAt == nil
            case .reviewed: matchesScope = progress.reviewedAt != nil || progress.disposition == .reviewed
            case .saved: matchesScope = progress.savedAt != nil || progress.disposition == .saved
            case let .collection(id): matchesScope = progress.collectionIDs.contains(id)
            case let .topic(topic): matchesScope = searchIndex.topicIDsByPaper[paper.shortID]?.contains(topic) == true
            case .calendar: matchesScope = false
            case .all: matchesScope = true
            case let .subject(subject): matchesScope = paper.subjects.contains(subject)
            case .cleanup: matchesScope = false
            case .excluded: matchesScope = excluded
            }
            guard matchesScope else { return false }
            guard !query.isEmpty else { return true }
            let text = searchIndex.textByID[paper.shortID] ?? trashSearchText[paper.shortID] ?? ""
            return text.contains(query) || ResearchTopic.normalize(progress.note).contains(query)
        }
    }

    private func rebuildIndex() {
        activePapers = papers.filter { cleanupState.excluded[$0.shortID] == nil }
        byID = Dictionary(activePapers.map { ($0.shortID, $0) }, uniquingKeysWith: { _, last in last })
        searchIndex = PaperSearchIndex(papers: activePapers, topics: settings.researchTopics)
        let subjects = Set(activePapers.flatMap(\.subjects))
        observedSubjects = AppSettings.categories.filter { subjects.contains($0) }
        refreshFilteredPapers()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.refreshFilteredPapers()
        }
    }

    private func scopeDidChange() {
        refreshFilteredPapers()
        guard scope == .excluded, !isLoadingTrash, !trashLoaded else { return }
        isLoadingTrash = true
        let repository = repository
        Task {
            defer { isLoadingTrash = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let values = try repository.loadTrashPapers()
                    return (values, PaperSearchIndex(papers: values, topics: []).textByID)
                }.value
                trashPapers = result.0
                trashSearchText = result.1
                trashLoaded = true
                excludedCount = trashPapers.count
                refreshFilteredPapers()
            } catch { errorMessage = "Trash could not be loaded. \(error.localizedDescription)" }
        }
    }

    var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return byID[selectedPaperID] ?? trashPapers.first { $0.shortID == selectedPaperID }
    }

    var todayUsage: TranslationUsageRecord {
        translationUsage.summary(for: DiscoveryDate.key(for: Date()))
    }

    var canChangeLibrary: Bool {
        !isDiscovering && !isCleaning && !isLoadingTrash && translatingPaperID == nil && downloadingPaperID == nil && !ShowcaseMode.isEnabled
    }

    var unsearchedRecentCount: Int {
        let categories = settings.enabledCategories
        return DiscoveryDate.recentKeys(count: 30).filter { key in
            discoveryHistory.days[key]?.covers(mode: settings.discoveryMode, categories: categories, researchTopics: settings.selectedTopics) != true
        }.count
    }

    func progress(for paper: Paper) -> PaperProgress {
        library.progress(for: paper.shortID)
    }

    func collectionCount(_ collectionID: String) -> Int {
        cachedCollectionCounts[collectionID, default: 0]
    }

    func topicCount(_ topic: ResearchTopic) -> Int {
        searchIndex.topicCounts[topic.id, default: 0]
    }

    func recordSelection() {
        guard let selectedPaperID, scope != .excluded else { return }
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
        guard settings.discoveryMode != .topics || !settings.selectedTopics.isEmpty else {
            errorMessage = "Select at least one research topic."
            return
        }
        guard settings.discoveryMode != .categories || !settings.enabledCategories.isEmpty else {
            errorMessage = "Select at least one arXiv category."
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
        let researchTopics = settings.selectedTopics
        Task {
            var merged = papers
            var updatedHistory = discoveryHistory
            var totalFound = 0
            var failures: [String] = []
            for key in validKeys {
                guard let interval = DiscoveryDate.interval(for: key) else { continue }
                let query = DiscoveryQuery(interval: interval, maxResults: 500, categories: categories, mode: mode, topics: topics, researchTopics: researchTopics)
                do {
                    let searchedAt = Date()
                    let batch = try await client.discoverBatch(query: query, now: searchedAt)
                    let discovered = batch.papers.filter { cleanupState.excluded[$0.shortID] == nil }
                    merged = repository.merge(existing: merged, discovered: discovered)
                    totalFound += discovered.count
                    updatedHistory.record(.init(
                        day: key,
                        lastSearchedAt: searchedAt,
                        paperCount: discovered.count,
                        categories: categories,
                        isComplete: batch.isComplete,
                        mode: mode,
                        topics: topics,
                        researchTopics: researchTopics
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
                state: cleanupState,
                researchTopics: settings.selectedTopics
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyCleanup() {
        let rules = settings.selectedTopics
        let version = version
        mutateLibrary { repository in
            let result = try repository.applyTopicCleanup(topics: [], applicationVersion: version, researchTopics: rules)
            return "Moved \(result.excludedCount) unrelated papers to Trash. Restore them anytime."
        }
    }

    func restoreLastCleanup() {
        mutateLibrary { repository in "Restored \(try repository.restoreLastTopicCleanup()) papers from the last cleanup." }
    }

    func restoreExcluded(_ paper: Paper) {
        mutateLibrary { repository in
            try repository.restoreExcludedPaper(paper.shortID)
            return "Restored to your library."
        }
    }

    func moveToTrash(_ paper: Paper) {
        mutateLibrary { repository in
            try repository.trashPaper(paper)
            return "Moved to Trash. PDF files and notes were kept."
        }
    }

    func deleteTrashedMetadata(_ paper: Paper) {
        mutateLibrary { repository in
            try repository.deleteTrashedMetadata(paper.shortID)
            return "Paper metadata deleted. Downloaded PDFs and notes were not deleted."
        }
    }

    private func mutateLibrary(_ operation: @escaping @Sendable (PaperRepository) throws -> String) {
        guard canChangeLibrary else {
            notice = "Finish the current search, download or translation before changing the library."
            return
        }
        isCleaning = true
        let repository = repository
        Task {
            defer { isCleaning = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let message = try operation(repository)
                    let trash = try repository.loadTrashPapers()
                    return (message, try repository.loadPapers(), try repository.loadCleanupState(), trash, PaperSearchIndex(papers: trash, topics: []).textByID)
                }.value
                cleanupState = result.2
                papers = result.1
                trashPapers = result.3
                trashSearchText = result.4
                trashLoaded = true
                excludedCount = trashPapers.count
                refreshFilteredPapers()
                reconcileSelection()
                if scope == .cleanup { previewCleanup() }
                notice = result.0
                try? writeStatus(availability: activePapers.isEmpty ? "empty" : "ready")
            } catch {
                // A partial write is recoverable from the archive/backup. Re-read
                // the live state without changing the user's current view.
                if let state = try? repository.loadCleanupState() { cleanupState = state }
                if let latest = try? repository.loadPapers() { papers = latest }
                errorMessage = "The library change could not finish. Your backup and PDF files are kept. \(error.localizedDescription)"
            }
        }
    }

    func markReviewed(_ paper: Paper) {
        guard !isCleaning else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.markReviewed(paper.shortID)
        persistLibrary(notice: "Moved to Reviewed.")
        advance(after: paper)
    }

    func moveToInbox(_ paper: Paper) {
        guard !isCleaning else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.moveToInbox(paper.shortID)
        persistLibrary(notice: "Moved to Inbox.")
    }

    func toggleSaved(_ paper: Paper) {
        guard !isCleaning else { return }
        guard restoreBeforeKeeping(paper) else { return }
        let progress = library.progress(for: paper.shortID)
        let saving = progress.savedAt == nil && progress.disposition != .saved
        library.setSaved(saving, paperID: paper.shortID)
        persistLibrary(notice: saving ? "Saved for later." : "Bookmark removed. Reading work was kept.")
        if !saving { advance(after: paper) }
    }

    @discardableResult
    func createCollection(named name: String, adding paper: Paper? = nil) -> Bool {
        guard !isCleaning else { return false }
        guard let collection = library.createCollection(named: name) else {
            errorMessage = "Use a non-empty, unique collection name."
            return false
        }
        if let paper { library.setCollection(collection.id, contains: paper.shortID, enabled: true) }
        persistLibrary(notice: "Collection created.")
        return true
    }

    func setCollection(_ collectionID: String, contains paper: Paper, enabled: Bool) {
        guard !isCleaning else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.setCollection(collectionID, contains: paper.shortID, enabled: enabled)
        persistLibrary()
    }

    func saveNote(_ note: String, for paper: Paper) {
        guard !isCleaning else { return }
        guard restoreBeforeKeeping(paper) else { return }
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
        guard translatingPaperID == nil, !isCleaning, !isDiscovering else { return }
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
        guard downloadingPaperID == nil, !isCleaning, let url = paper.downloadablePDFURL else { return }
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
            papers = try repository.loadPapers()
            trashPapers.removeAll { $0.shortID == paper.shortID }
            excludedCount = max(0, excludedCount - 1)
            return true
        } catch {
            errorMessage = "The paper could not be restored. \(error.localizedDescription)"
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
            excludedCount = cleanupState.excluded.values.filter { $0.metadataDeleted != true }.count
            rebuildIndex()
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
