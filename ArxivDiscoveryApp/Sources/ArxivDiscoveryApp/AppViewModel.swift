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
    @Published private(set) var library = LibraryState() { didSet { rebuildCounts(); refreshFilteredPapers() } }
    @Published private(set) var discoveryHistory = DiscoveryHistory()
    @Published private(set) var translationUsage = TranslationUsageLedger()
    @Published private(set) var cleanupState = TopicCleanupState()
    @Published private(set) var cleanupPreview: TopicCleanupPreview?
    @Published private(set) var cleanupMessage: String?
    @Published private(set) var cleanupError: String?
    @Published private(set) var isPreviewingCleanup = false
    @Published private(set) var lastRemovalCount = 0
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
    private var preparedIndex: PaperSearchIndex?
    @Published private(set) var isIndexingTopics = false
    private var indexingTask: Task<Void, Never>?
    private var indexRevision = UUID()
    @Published private(set) var localPDFs: [String: URL] = [:]
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
    @Published private(set) var discoveryProgress: String?
    @Published private(set) var discoveryStartedAt: Date?
    @Published private(set) var discoveryCompletedDays = 0
    @Published private(set) var discoveryTotalDays = 0
    @Published private(set) var discoveryReceivedPapers = 0
    @Published private(set) var discoveryReport: DiscoveryRunReport?
    @Published private(set) var discoveryNotice: String?
    @Published private(set) var discoveryError: String?
    private var discoveryTask: Task<Void, Never>?
    @Published private(set) var translatingPaperID: String?
    @Published private(set) var downloadingPaperID: String?
    @Published private(set) var lastRefresh: Date?
    @Published var notice: String?
    @Published var errorMessage: String?

    let settings: AppSettings
    let repository: PaperRepository
    let isVerification: Bool
    let noteDrafts = NoteDraftStore()
    private let client: ArxivSearching
    private let discovery: DiscoverySearch
    private let gemini = GeminiClient()
    private let keychain = KeychainStore()
    private let version: String

    init(
        settings: AppSettings,
        repository: PaperRepository = PaperRepository(),
        client: ArxivSearching = ArxivClient(),
        isVerification: Bool = false,
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
    ) {
        self.settings = settings
        self.repository = repository
        self.isVerification = isVerification
        self.client = client
        self.discovery = DiscoverySearch(repository: repository, client: client)
        self.version = version
        load()
        topicSubscription = settings.$researchTopics.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.reindexTopics() }
    }

    var favorites: Set<String> { library.savedPaperIDs }

    private func rebuildCounts() {
        inboxCount = 0; newCount = 0; reviewedCount = 0; savedCount = 0
        cachedCollectionCounts = [:]
        for paper in activePapers {
            let progress = library.progress(for: paper.shortID)
            if progress.disposition == .inbox { inboxCount += 1; if progress.firstViewedAt == nil { newCount += 1 } }
            if progress.reviewedAt != nil || progress.disposition == .reviewed { reviewedCount += 1 }
            if progress.savedAt != nil || progress.disposition == .saved { savedCount += 1 }
            for id in progress.collectionIDs { cachedCollectionCounts[id, default: 0] += 1 }
        }
    }

    private func refreshFilteredPapers() {
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
        indexingTask?.cancel()
        indexRevision = UUID()
        isIndexingTopics = false
        activePapers = papers.filter { cleanupState.excluded[$0.shortID] == nil }
        byID = Dictionary(activePapers.map { ($0.shortID, $0) }, uniquingKeysWith: { _, last in last })
        searchIndex = preparedIndex ?? PaperSearchIndex(papers: activePapers, topics: settings.researchTopics)
        preparedIndex = nil
        let subjects = Set(activePapers.flatMap(\.subjects))
        observedSubjects = AppSettings.categories.filter { subjects.contains($0) }
        rebuildCounts()
        refreshFilteredPapers()
    }

    private func reindexTopics() {
        indexingTask?.cancel()
        let revision = UUID()
        indexRevision = revision
        let values = activePapers
        let rules = settings.researchTopics
        isIndexingTopics = true
        indexingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let index = await Task.detached(priority: .userInitiated) { PaperSearchIndex(papers: values, topics: rules) }.value
            guard let self, !Task.isCancelled, indexRevision == revision else { return }
            searchIndex = index
            isIndexingTopics = false
            refreshFilteredPapers()
            if scope == .cleanup { previewCleanup() }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshFilteredPapers()
            return
        }
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
        !isDiscovering && !isCleaning && !isLoadingTrash && !isIndexingTopics && translatingPaperID == nil && downloadingPaperID == nil && !ShowcaseMode.isEnabled
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
        guard let selectedPaperID, scope != .excluded, !isCleaning,
              library.papers[selectedPaperID]?.firstViewedAt == nil else { return }
        library.markViewed(selectedPaperID)
        persistLibrary()
    }

    func reconcileSelection() {
        guard let selectedPaperID,
              filteredPapers.contains(where: { $0.shortID == selectedPaperID }) == false
        else { return }
        self.selectedPaperID = nil
    }

    func searchSelectedDates(forceRefresh: Bool = false, only days: [String]? = nil) {
        guard !isVerification else { discoveryError = "The verification library is offline."; return }
        guard canChangeLibrary else {
            discoveryNotice = "Finish the current library operation before starting a search."
            return
        }
        guard settings.discoveryMode != .topics || !settings.selectedTopics.isEmpty else {
            discoveryError = "Select at least one research topic."
            return
        }
        guard settings.discoveryMode != .categories || !settings.enabledCategories.isEmpty else {
            discoveryError = "Select at least one arXiv category."
            return
        }
        let validKeys = Set(days ?? Array(selectedDiscoveryDays))
            .filter { key in
                guard let date = DiscoveryDate.date(from: key) else { return false }
                return date <= Date()
            }
            .sorted()
        guard !validKeys.isEmpty else {
            discoveryError = "Select at least one date."
            return
        }

        isDiscovering = true
        discoveryReport = nil
        discoveryStartedAt = Date()
        discoveryCompletedDays = 0
        discoveryTotalDays = validKeys.count
        discoveryReceivedPapers = 0
        discoveryError = nil
        discoveryNotice = nil
        guard let interval = DiscoveryDate.interval(for: validKeys[0]) else { isDiscovering = false; return }
        let query = DiscoveryQuery(interval: interval, categories: settings.enabledCategories.sorted(), mode: settings.discoveryMode, researchTopics: settings.selectedTopics)
        var policy = DiscoveryPolicy()
        policy.retentionDays = settings.cacheRetentionDays
        discoveryTask = Task { [self] in
            defer { isDiscovering = false; discoveryProgress = nil; discoveryTask = nil }
            do {
                let report = try await discovery.search(days: validKeys, template: query, forceRefresh: forceRefresh, policy: policy) { [weak self] progress in
                    await self?.showDiscoveryProgress(progress)
                }
                discoveryReport = report
                discoveryProgress = "Updating the paper list…"
                let snapshot = try await discovery.snapshot()
                let rules = settings.researchTopics
                let excluded = Set(cleanupState.excluded.keys)
                let index = await Task.detached(priority: .userInitiated) {
                    PaperSearchIndex(papers: snapshot.papers.filter { !excluded.contains($0.shortID) }, topics: rules)
                }.value
                preparedIndex = settings.researchTopics == rules ? index : nil
                papers = snapshot.papers
                discoveryHistory = snapshot.history
                lastRefresh = snapshot.history.days.values.map(\.lastSearchedAt).max()
                let kept = "\(report.receivedPapers) matching papers saved · \(String(format: "%.1f", report.elapsedSeconds))s."
                if report.storageFailed {
                    discoveryError = "\(report.failures.last?.message ?? "Search results could not be fully saved.") Check local storage before retrying."
                } else if report.pendingDays.isEmpty {
                    discoveryNotice = report.requestCount == 0 ? "Using saved results for \(report.cachedDays.count) dates. No network requests." : "Search complete. \(kept)"
                } else if report.cancelled {
                    discoveryNotice = "Search cancelled. \(kept) \(report.pendingDays.count) dates unfinished."
                } else if report.timedOut {
                    discoveryError = "Search stopped at the overall time limit. \(kept) \(report.pendingDays.count) dates unfinished."
                } else {
                    discoveryError = "\(report.failures.first?.message ?? "More results remain; retry unfinished dates.") \(kept) \(report.pendingDays.count) dates unfinished."
                }
                try? writeStatus(availability: report.pendingDays.isEmpty ? "ready" : "partial")
            } catch {
                discoveryError = "The search could not finish. Existing papers are kept. \(error.localizedDescription)"
                try? writeStatus(availability: papers.isEmpty ? "unavailable" : "partial", errorCode: "discovery_save_failed")
            }
        }
    }

    func cancelDiscovery() { discoveryTask?.cancel() }

    func retryUnfinishedDates() {
        guard let report = discoveryReport, !report.pendingDays.isEmpty else { return }
        // Preserve range/page-cache identity; complete dates are reused locally.
        searchSelectedDates(only: report.selectedDays)
    }

    private func showDiscoveryProgress(_ progress: DiscoveryProgress) {
        discoveryProgress = progress.message
        discoveryCompletedDays = progress.completedDays
        discoveryTotalDays = progress.totalDays
        discoveryReceivedPapers = progress.receivedPapers
    }

    func previewCleanup() {
        cleanupPreview = nil
        guard canChangeLibrary else { return }
        cleanupError = nil
        guard !settings.selectedTopics.isEmpty else {
            cleanupError = "Select at least one research topic to keep."
            return
        }
        isCleaning = true
        isPreviewingCleanup = true
        let repository = repository
        let papers = papers
        let library = library
        let state = cleanupState
        let rules = settings.selectedTopics
        Task {
            defer {
                isCleaning = false
                isPreviewingCleanup = false
                if settings.selectedTopics != rules, scope == .cleanup { previewCleanup() }
            }
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try repository.previewTopicCleanup(topics: [], papers: papers, library: library, state: state, researchTopics: rules)
                }.value
                cleanupPreview = settings.selectedTopics == rules ? preview : nil
            } catch { cleanupError = "The preview could not be prepared. Your library is unchanged. \(error.localizedDescription)" }
        }
    }

    func applyCleanup() {
        let rules = settings.selectedTopics
        guard let preview = cleanupPreview, preview.researchTopics == rules,
              !preview.candidates.isEmpty else {
            cleanupError = "The preview changed. Refresh it before moving papers."
            return
        }
        let expectedIDs = Set(preview.candidates.map(\.paperID))
        let version = version
        mutateLibrary { repository in
            let result = try repository.applyTopicCleanup(topics: [], applicationVersion: version, researchTopics: rules, expectedCandidateIDs: expectedIDs)
            return "Moved \(result.excludedCount) unrelated papers to Trash. Restore them anytime."
        }
    }

    func restoreLastCleanup() {
        mutateLibrary { repository in
            let count = try repository.restoreLastTopicCleanup()
            return "Restored \(count) \(count == 1 ? "paper" : "papers") from the last removal."
        }
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
        let rules = settings.researchTopics
        let needsTrash = trashLoaded || scope == .excluded
        let fromCleanup = scope == .cleanup
        cleanupError = nil
        Task {
            var succeeded = false
            defer {
                isCleaning = false
                if succeeded, fromCleanup, scope == .cleanup { previewCleanup() }
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let message = try operation(repository)
                    let trash = needsTrash ? try repository.loadTrashPapers() : []
                    let latest = try repository.loadPapers()
                    let state = try repository.loadCleanupState()
                    return (message, latest, state, trash, PaperSearchIndex(papers: trash, topics: []).textByID,
                            PaperSearchIndex(papers: latest.filter { state.excluded[$0.shortID] == nil }, topics: rules))
                }.value
                cleanupState = result.2
                preparedIndex = settings.researchTopics == rules ? result.5 : nil
                papers = result.1
                if needsTrash {
                    trashPapers = result.3
                    trashSearchText = result.4
                    trashLoaded = true
                }
                excludedCount = cleanupState.excluded.values.filter { $0.metadataDeleted != true }.count
                refreshLastRemovalCount()
                refreshFilteredPapers()
                reconcileSelection()
                cleanupPreview = nil
                notice = result.0
                if fromCleanup { cleanupMessage = result.0 }
                succeeded = true
                try? writeStatus(availability: activePapers.isEmpty ? "empty" : "ready")
            } catch {
                // A partial write is recoverable from the archive/backup. Re-read
                // the live state without changing the user's current view.
                let message = "The library change could not finish. Your backup and PDF files are kept. \(error.localizedDescription)"
                let latest = try? await Task.detached { (try repository.loadPapers(), try repository.loadCleanupState()) }.value
                if let latest { cleanupState = latest.1; papers = latest.0; refreshLastRemovalCount() }
                if fromCleanup { cleanupError = message } else { errorMessage = message }
            }
        }
    }

    func markReviewed(_ paper: Paper) {
        guard canChangeLibrary else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.markReviewed(paper.shortID)
        persistLibrary(notice: "Moved to Reviewed.")
        advance(after: paper)
    }

    func moveToInbox(_ paper: Paper) {
        guard canChangeLibrary else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.moveToInbox(paper.shortID)
        persistLibrary(notice: "Moved to Inbox.")
    }

    func toggleSaved(_ paper: Paper) {
        guard canChangeLibrary else { return }
        guard restoreBeforeKeeping(paper) else { return }
        let progress = library.progress(for: paper.shortID)
        let saving = progress.savedAt == nil && progress.disposition != .saved
        library.setSaved(saving, paperID: paper.shortID)
        persistLibrary(notice: saving ? "Saved for later." : "Bookmark removed. Reading work was kept.")
        if !saving { advance(after: paper) }
    }

    @discardableResult
    func createCollection(named name: String, adding paper: Paper? = nil) -> Bool {
        guard canChangeLibrary else { return false }
        guard let collection = library.createCollection(named: name) else {
            errorMessage = "Use a non-empty, unique collection name."
            return false
        }
        if let paper { library.setCollection(collection.id, contains: paper.shortID, enabled: true) }
        persistLibrary(notice: "Collection created.")
        return true
    }

    func setCollection(_ collectionID: String, contains paper: Paper, enabled: Bool) {
        guard canChangeLibrary else { return }
        guard restoreBeforeKeeping(paper) else { return }
        library.setCollection(collectionID, contains: paper.shortID, enabled: enabled)
        persistLibrary()
    }

    func saveNote(_ note: String, for paper: Paper) {
        guard canChangeLibrary else { return }
        guard restoreBeforeKeeping(paper) else { return }
        var updated = library
        updated.setNote(note, paperID: paper.shortID)
        do {
            try repository.saveLibraryState(updated)
            library = updated
            noteDrafts.values.discard(paper.shortID)
            noteDrafts.errors.removeValue(forKey: paper.shortID)
            try? writeStatus(availability: activePapers.isEmpty ? "empty" : "ready")
        } catch { noteDrafts.errors[paper.shortID] = "The note could not be saved. Your draft is kept. Check local disk access, then try again." }
    }

    private func refreshLastRemovalCount() {
        guard let id = cleanupState.latestBatchID else { lastRemovalCount = 0; return }
        lastRemovalCount = cleanupState.excluded.values.filter { $0.batchID == id && $0.metadataDeleted != true }.count
    }

    func prepareToClose() -> Bool {
        guard !noteDrafts.values.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Unsaved notes"
        alert.informativeText = "Save your drafts before closing, or discard the unsaved changes."
        alert.addButton(withTitle: "Save notes")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard drafts")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard canChangeLibrary else { return false }
            for id in noteDrafts.values.editedIDs {
                guard let paper = byID[id] else { return false }
                saveNote(noteDrafts.values.text(for: id, saved: library.progress(for: id).note), for: paper)
            }
            return noteDrafts.values.isEmpty
        case .alertThirdButtonReturn: noteDrafts.values = NoteDrafts(); return true
        default: return false
        }
    }

    func importLegacy(from url: URL) {
        guard canChangeLibrary else {
            notice = "Finish the current library operation before importing."
            return
        }
        isCleaning = true
        let accessing = url.startAccessingSecurityScopedResource()
        let repository = repository
        let rules = settings.researchTopics
        Task {
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
                isCleaning = false
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let imported = try repository.importLegacy(papers: url)
                    let values = try repository.loadPapers()
                    return (imported, values, try repository.loadLibraryState(), PaperSearchIndex(papers: values, topics: rules))
                }.value
                preparedIndex = settings.researchTopics == rules ? result.3 : nil
                papers = result.1
                library = result.2
                notice = "Imported \(result.0.importedPaperCount) papers and \(result.0.importedFavoriteCount) saved IDs."
                try writeStatus(availability: papers.isEmpty ? "empty" : "ready")
            } catch {
                errorMessage = "The selected JSON could not be imported. \(error.localizedDescription)"
            }
        }
    }

    func translate(_ paper: Paper) {
        guard canChangeLibrary, !isVerification else { return }
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
        guard !isLoadingModels, !isVerification else { return }
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
        guard !isVerification else { return }
        geminiConfigured = (try? keychain.read())?.isEmpty == false
        if geminiConfigured { refreshGeminiModels() }
        else { availableGeminiModels = [] }
    }

    func downloadPDF(_ paper: Paper) {
        guard canChangeLibrary, !isVerification, let url = paper.downloadablePDFURL else { return }
        downloadingPaperID = paper.shortID
        errorMessage = nil
        Task {
            defer { downloadingPaperID = nil }
            do {
                let (temporaryURL, response) = try await BoundedHTTPClient().download(for: URLRequest(url: url))
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard (200...299).contains(response.statusCode)
                else { throw URLError(.badServerResponse) }
                let repository = repository
                let style = settings.pdfNameStyle
                let destination = try await Task.detached(priority: .userInitiated) {
                    let header = try FileHandle(forReadingFrom: temporaryURL)
                    defer { try? header.close() }
                    guard try header.read(upToCount: 5) == Data("%PDF-".utf8) else { throw HTTPTransferError.invalidResponse }
                    return try repository.storeDownloadedPDF(from: temporaryURL, for: paper, style: style)
                }.value
                notice = "PDF downloaded as \(destination.lastPathComponent)."
                localPDFs[paper.shortID] = destination
                NSWorkspace.shared.open(destination)
            } catch {
                errorMessage = "PDF download failed. \(error.localizedDescription)"
            }
        }
    }

    func openPDF(_ paper: Paper) {
        guard !isVerification else { return }
        if let local = localPDFs[paper.shortID] {
            if FileManager.default.fileExists(atPath: local.path) { NSWorkspace.shared.open(local) }
            else {
                localPDFs.removeValue(forKey: paper.shortID)
                errorMessage = "The downloaded PDF is missing. Use Download PDF to retrieve it again."
            }
        } else {
            downloadPDF(paper)
        }
    }

    func hasLocalPDF(_ paper: Paper) -> Bool {
        localPDFs[paper.shortID] != nil
    }

    func openPaper(_ paper: Paper) {
        guard !isVerification, let url = paper.entryURL else { return }
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
            refreshLastRemovalCount()
            papers = try repository.loadPapers()
            localPDFs = try repository.existingPDFURLs(for: papers, preferredStyle: settings.pdfNameStyle)
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
            let loaded = try repository.loadPapers()
            library = try repository.loadLibraryState()
            discoveryHistory = try repository.loadDiscoveryHistory()
            translationUsage = try repository.loadTranslationUsage()
            cleanupState = try repository.loadCleanupState()
            refreshLastRemovalCount()
            excludedCount = cleanupState.excluded.values.filter { $0.metadataDeleted != true }.count
            papers = loaded
            localPDFs = try repository.existingPDFURLs(for: loaded, preferredStyle: settings.pdfNameStyle)
            selectedPaperID = nil
            lastRefresh = try repository.loadStatus()?.lastRefresh
            geminiConfigured = !isVerification && (try? keychain.read())?.isEmpty == false
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
