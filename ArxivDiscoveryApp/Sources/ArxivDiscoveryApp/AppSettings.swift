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
    static let categories = ["cs.AI", "cs.LG", "cs.CV", "cs.CL", "cs.NE", "stat.ML"]

    @Published var days: Int {
        didSet { UserDefaults.standard.set(days, forKey: "discoveryDays") }
    }

    @Published var enabledCategories: Set<String> {
        didSet { UserDefaults.standard.set(enabledCategories.sorted(), forKey: "enabledCategories") }
    }

    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    let geminiModel = "gemini-3.5-flash"

    init() {
        let storedDays = UserDefaults.standard.integer(forKey: "discoveryDays")
        days = [1, 3, 7].contains(storedDays) ? storedDays : 1
        let storedCategories = UserDefaults.standard.stringArray(forKey: "enabledCategories") ?? []
        enabledCategories = storedCategories.isEmpty ? Set(Self.categories) : Set(storedCategories)
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    var discoveryQuery: DiscoveryQuery {
        DiscoveryQuery(days: days, maxResults: 200, categories: enabledCategories.sorted())
    }
}
