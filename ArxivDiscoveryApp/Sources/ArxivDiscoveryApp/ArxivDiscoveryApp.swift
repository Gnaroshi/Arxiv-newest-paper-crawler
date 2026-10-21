import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var prepareToTerminate: (() -> Bool)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareToTerminate?() == false ? .terminateCancel : .terminateNow
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            // A restored frame can exceed the current display after a monitor
            // change. Keep the toolbar and pinned actions on screen.
            for window in NSApp.windows where window.canBecomeMain && !window.styleMask.contains(.fullScreen) {
                guard let screen = window.screen ?? NSScreen.main else { continue }
                let visible = screen.visibleFrame
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                if frame != window.frame { window.setFrame(frame, display: true) }
            }
        }
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
    @StateObject private var verification = VerificationWindowController()

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
                .onAppear {
                    appDelegate.prepareToTerminate = { model.prepareToClose() && verification.prepareToClose() }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Search Selected Dates") {
                    if !verification.isFrontmost { model.searchSelectedDates() }
                }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.canChangeLibrary)
            }
            CommandGroup(after: .help) {
                Menu("Diagnostics") {
                    Button("Open verification library…") { verification.chooseLibrary(appearance: settings.appearance) }
                    Button("Verification window: minimum size") { verification.resize(width: 900, height: 620) }
                    Button("Verification window: standard size") { verification.resize(width: 1180, height: 760) }
                    Button("Verification window: toggle appearance") { verification.toggleAppearance() }
                }
            }
        }

        Settings {
            SettingsView(settings: settings, model: model, repositoryRoot: model.repository.rootURL)
        }
    }
}
