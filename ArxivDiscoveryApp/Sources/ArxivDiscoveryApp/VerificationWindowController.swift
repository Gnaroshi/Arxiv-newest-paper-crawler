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

    func chooseLibrary(appearance: AppAppearance) {
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
        let model = AppViewModel(settings: settings, repository: PaperRepository(rootURL: root), isVerification: true)
        model.scope = .all
        let content = VStack(spacing: 0) {
            Label("Verification library · offline · original library unchanged", systemImage: "testtube.2")
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
        let values = ["window": NSStringFromRect(window.frame), "content": NSStringFromRect(view.frame),
                      "bounds": NSStringFromRect(view.bounds), "layout": NSStringFromRect(window.contentLayoutRect),
                      "minimum": NSStringFromSize(window.contentMinSize),
                      "visible": NSStringFromRect(window.screen?.visibleFrame ?? .zero)]
        if let data = try? JSONEncoder().encode(values) {
            try? data.write(to: model.repository.rootURL.appendingPathComponent("viewport-debug.json"), options: .atomic)
        }
    }

    func prepareToClose() -> Bool { model?.prepareToClose() ?? true }

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
