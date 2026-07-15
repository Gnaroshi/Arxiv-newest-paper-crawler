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
    static let categories = ["cs.AI", "cs.LG", "cs.CV", "cs.CL", "cs.RO", "cs.NE", "stat.ML"]
    static let defaultGeminiModel = "gemini-3.5-flash"

    @Published var enabledCategories: Set<String> {
        didSet { UserDefaults.standard.set(enabledCategories.sorted(), forKey: "enabledCategories") }
    }

    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    @Published var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "geminiModel") }
    }

    @Published var pdfNameStyle: PDFNameStyle {
        didSet { UserDefaults.standard.set(pdfNameStyle.rawValue, forKey: "pdfNameStyle") }
    }

    @Published var cacheRetentionDays: Int {
        didSet { UserDefaults.standard.set(cacheRetentionDays, forKey: "cacheRetentionDays") }
    }

    init() {
        let storedCategories = UserDefaults.standard.stringArray(forKey: "enabledCategories") ?? []
        enabledCategories = storedCategories.isEmpty ? Set(Self.categories) : Set(storedCategories)
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        geminiModel = UserDefaults.standard.string(forKey: "geminiModel") ?? Self.defaultGeminiModel
        pdfNameStyle = PDFNameStyle(rawValue: UserDefaults.standard.string(forKey: "pdfNameStyle") ?? "") ?? .title
        let retention = UserDefaults.standard.integer(forKey: "cacheRetentionDays")
        cacheRetentionDays = (30...365).contains(retention) ? retention : 60
    }
}
