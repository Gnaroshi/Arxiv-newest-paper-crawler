import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct ArxivDiscoveryApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppViewModel

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("Arxiv Discovery") {
            ContentView(model: model, settings: settings)
                .frame(minWidth: 900, minHeight: 620)
                .tint(AppTheme.sky)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Search Selected Dates") { model.searchSelectedDates() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.isDiscovering || ShowcaseMode.isEnabled)
            }
        }

        Settings {
            SettingsView(settings: settings, model: model, repositoryRoot: model.repository.rootURL)
        }
    }
}
