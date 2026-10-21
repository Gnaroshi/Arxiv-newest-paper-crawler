import ArxivDiscoveryCore
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var openTopicEditors = 0
    var isManagingTopics: Bool { openTopicEditors > 0 }
    func topicEditorOpened() { openTopicEditors += 1 }
    func topicEditorClosed() { openTopicEditors = max(0, openTopicEditors - 1) }
    static let categories = ["cs.AI", "cs.LG", "cs.CV", "cs.CL", "cs.RO", "cs.NE", "stat.ML"]
    static let defaultGeminiModel = "gemini-3.5-flash"

    @Published var discoveryMode: DiscoveryMode {
        didSet { defaults.set(discoveryMode.rawValue, forKey: "discoveryMode") }
    }

    @Published var enabledTopics: Set<SmartTopic> {
        didSet { defaults.set(enabledTopics.map(\.rawValue).sorted(), forKey: "enabledTopics") }
    }

    @Published var researchTopics: [ResearchTopic] {
        didSet {
            if let data = try? JSONEncoder().encode(researchTopics) { defaults.set(data, forKey: "researchTopics") }
        }
    }
    @Published var selectedTopicIDs: Set<String> {
        didSet { defaults.set(selectedTopicIDs.sorted(), forKey: "selectedTopicIDs") }
    }
    var selectedTopics: [ResearchTopic] { researchTopics.filter { selectedTopicIDs.contains($0.id) } }

    @Published var enabledCategories: Set<String> {
        didSet { defaults.set(enabledCategories.sorted(), forKey: "enabledCategories") }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    @Published var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: "geminiModel") }
    }

    @Published var pdfNameStyle: PDFNameStyle {
        didSet { defaults.set(pdfNameStyle.rawValue, forKey: "pdfNameStyle") }
    }

    @Published var cacheRetentionDays: Int {
        didSet { defaults.set(cacheRetentionDays, forKey: "cacheRetentionDays") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        discoveryMode = DiscoveryMode(rawValue: defaults.string(forKey: "discoveryMode") ?? "") ?? .topics
        let storedTopics = defaults.stringArray(forKey: "enabledTopics")
        enabledTopics = storedTopics.map { Set($0.compactMap(SmartTopic.init(rawValue:))) } ?? Set(SmartTopic.allCases)
        let storedRules = defaults.data(forKey: "researchTopics").flatMap { try? JSONDecoder().decode([ResearchTopic].self, from: $0) } ?? ResearchTopic.defaults
        let oldWorldTerms = Set(["world model", "world models", "world modelling", "world modeling", "world action model"])
        researchTopics = storedRules.map { rule in
            guard rule.id == SmartTopic.worldModels.rawValue, Set(rule.anyTerms) == oldWorldTerms,
                  let updated = ResearchTopic.defaults.first(where: { $0.id == rule.id }) else { return rule }
            var migrated = rule
            migrated.anyTerms = updated.anyTerms
            return migrated
        }
        selectedTopicIDs = Set(defaults.stringArray(forKey: "selectedTopicIDs") ?? storedTopics ?? SmartTopic.allCases.map(\.rawValue))
        let storedCategories = defaults.stringArray(forKey: "enabledCategories")
        enabledCategories = storedCategories.map(Set.init) ?? Set(Self.categories)
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        geminiModel = defaults.string(forKey: "geminiModel") ?? Self.defaultGeminiModel
        pdfNameStyle = PDFNameStyle(rawValue: defaults.string(forKey: "pdfNameStyle") ?? "") ?? .title
        let retention = defaults.integer(forKey: "cacheRetentionDays")
        cacheRetentionDays = (30...365).contains(retention) ? retention : 60
    }
}
