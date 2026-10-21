import AppKit
import ArxivDiscoveryCore
import SwiftUI

/// Runs the product views/model on an explicitly selected offline fixture.
/// Fixture generation belongs to CoreChecks, not to the application target.
@MainActor
final class VerificationWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: AppViewModel?
    private var settings: AppSettings?
    private var suiteName: String?
    var isFrontmost: Bool { window != nil && NSApp.keyWindow === window }

    func chooseLibrary(appearance: AppAppearance, publicDiscovery: Bool = false) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "Open isolated verification library"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = VerificationLibrary.baseURL
        guard panel.runModal() == .OK, let root = panel.url, VerificationLibrary.isValid(root) else { return }
        let name = "dev.gnaroshi.ArxivDiscovery.verification." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { return }
        let settings = AppSettings(defaults: defaults)
        settings.appearance = appearance
        if let data = try? Data(contentsOf: root.appendingPathComponent("verification-preferences.json")),
           let preferences = try? JSONDecoder().decode(Preferences.self, from: data) {
            settings.researchTopics = preferences.topics
            settings.selectedTopicIDs = preferences.selected
            settings.discoveryMode = preferences.mode
        }
        let model = AppViewModel(settings: settings, repository: PaperRepository(rootURL: root), isVerification: true,
                                 allowPublicVerificationDiscovery: publicDiscovery)
        model.scope = .all
        let content = VStack(spacing: 0) {
            Label(publicDiscovery ? "Verification library · public arXiv only · original library unchanged" : "Verification library · offline · original library unchanged", systemImage: "testtube.2")
                .font(.caption).frame(maxWidth: .infinity).padding(8)
                .background(Color.orange.opacity(0.12))
            ContentView(model: model, settings: settings)
        }.frame(minWidth: 900, minHeight: 620).tint(AppTheme.sky)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Arxiv Discovery — Verification"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = NSSize(width: 900, height: 620)
        window.delegate = self
        self.window = window; self.model = model; self.settings = settings; suiteName = name
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func resize(width: CGFloat, height: CGFloat) {
        guard let window else { return }
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
    }

    func toggleAppearance() {
        guard let settings else { return }
        settings.appearance = settings.appearance == .light ? .dark : .light
    }

    func exportGeometry() {
        guard let window, let model, let view = window.contentView else { return }
        func hierarchy(_ view: NSView, depth: Int = 0) -> [String] {
            guard depth < 10 else { return [] }
            return ["\(String(repeating: " ", count: depth))\(type(of: view)): \(NSStringFromRect(view.frame)) visible=\(NSStringFromRect(view.visibleRect))"] + view.subviews.flatMap { hierarchy($0, depth: depth + 1) }
        }
        let values = ["window": NSStringFromRect(window.frame), "content": NSStringFromRect(view.frame),
                      "bounds": NSStringFromRect(view.bounds), "layout": NSStringFromRect(window.contentLayoutRect),
                      "minimum": NSStringFromSize(window.contentMinSize),
                      "visible": NSStringFromRect(window.screen?.visibleFrame ?? .zero), "views": hierarchy(view).joined(separator: "\n")]
        if let data = try? JSONEncoder().encode(values) {
            try? data.write(to: model.repository.rootURL.appendingPathComponent("viewport-debug.json"), options: .atomic)
        }
    }

    func prepareToClose() -> Bool {
        guard model?.prepareToClose() != false else { return false }
        if let model, let settings {
            let preferences = Preferences(topics: settings.researchTopics, selected: settings.selectedTopicIDs, mode: settings.discoveryMode)
            if let data = try? JSONEncoder().encode(preferences) {
                try? data.write(to: model.repository.rootURL.appendingPathComponent("verification-preferences.json"), options: .atomic)
            }
        }
        return true
    }

    private struct Preferences: Codable {
        var topics: [ResearchTopic]
        var selected: Set<String>
        var mode: DiscoveryMode
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.isCleaning != true else { return false }
        return prepareToClose()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil; model = nil; settings = nil
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        suiteName = nil
    }
}
