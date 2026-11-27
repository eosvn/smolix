import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var engine = ScrollEngine(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, engine: engine)
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        statusItem = StatusItemController(settings: settings, engine: engine) { [weak self] in
            self?.settingsWindow.show()
        }

        if !Accessibility.isTrusted {
            Accessibility.requestIfNeeded()
            settingsWindow.show()
        }
        engine.startSupervising()
    }

    /// Opening Smolix again (Finder, Spotlight) while it runs shows the settings window —
    /// the only way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        if let other = others.first {
            other.activate()
            return true
        }
        return false
    }
}
