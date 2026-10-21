import ArxivDiscoveryCore
import SwiftUI

@MainActor
final class ReadingReviewModel: ObservableObject {
    @Published private(set) var plan: DailyReadingPlan?
    @Published private(set) var state = ReadingReviewState()
    @Published private(set) var isUpdating = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published var bucket: ReadingBucket = .readFirst { didSet { notice = nil } }
    private(set) var byID: [String: ReadingRecommendation] = [:]
    private var bucketIDs: [ReadingBucket: [String]] = [:]
    private let repository: PaperRepository
    private let service: ReadingReviewService
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var canSave = true
    private var context: (papers: [Paper], library: LibraryState, topics: [ResearchTopic], index: PaperSearchIndex)?

    init(repository: PaperRepository) {
        self.repository = repository
        service = ReadingReviewService(repository: repository)
        do { state = try repository.loadReadingReview() } catch {
            self.error = "Reading preferences could not be loaded. They have not been replaced."
            canSave = false
        }
    }

    deinit { task?.cancel() }

    func retry() {
        do {
            state = try repository.loadReadingReview()
            canSave = true
            refresh()
        } catch {
            self.error =
                "Reading preferences still cannot be loaded. Your previous choices and papers are kept. Check local storage, then retry."
        }
    }

    func update(papers: [Paper], library: LibraryState, topics: [ResearchTopic], index: PaperSearchIndex) {
        context = (papers, library, topics, index)
        refresh()
    }

    func refreshIfNewDay(now: Date = Date()) {
        if plan?.localDay != DailyReadingPlan.dayKey(now), !isUpdating { refresh(now: now) }
    }

    func refresh(now: Date = Date()) {
        guard let context, canSave else { return }
        task?.cancel()
        let revision = UUID()
        self.revision = revision
        let state = state
        isUpdating = true
        task = Task { [weak self, service] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                let plan = try await service.refresh(
                    papers: context.papers, library: context.library, topics: context.topics,
                    index: context.index, state: state, now: now)
                guard let self, !Task.isCancelled, self.revision == revision else { return }
                byID = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.paperID, $0) })
                bucketIDs = Dictionary(grouping: plan.items, by: \.bucket).mapValues { $0.map(\.paperID) }
                self.plan = plan
                isUpdating = false
                error = nil
            } catch is CancellationError {} catch {
                guard let self, self.revision == revision else { return }
                isUpdating = false
                self.error =
                    "Reading priorities could not be refreshed. Papers and reading notes are unchanged. Try again."
            }
        }
    }

    func choose(_ choice: ReadingChoice, for id: String) {
        var updated = state
        updated.choose(choice, for: id)
        if save(updated) {
            notice = choice == .automatic ? "Automatic priority restored." : "Priority set: \(choice.label)."
        }
    }

    @discardableResult
    func setPreferences(limit: Int, focus: [String]) -> Bool {
        var updated = state
        updated.dailyLimit = min(20, max(1, limit))
        updated.focusTerms = Array(Set(focus.map(ResearchTopic.normalize).filter { !$0.isEmpty })).sorted()
        return save(updated)
    }

    @discardableResult private func save(_ value: ReadingReviewState) -> Bool {
        guard canSave else { return false }
        do {
            try repository.saveReadingReview(value)
            state = value
            refresh()
            return true
        } catch {
            self.error = "Reading preferences were not saved. Your previous choices and all papers are kept. Try again."
            return false
        }
    }

    func ids(_ bucket: ReadingBucket) -> [String] { bucketIDs[bucket] ?? [] }
    func count(_ bucket: ReadingBucket) -> Int { bucketIDs[bucket]?.count ?? 0 }
}
