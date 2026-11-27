import AppKit
import Combine

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let engine: ScrollEngine
    private let updater: Updater
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    private let headerItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let smoothItem = NSMenuItem()
    private let reverseItem = NSMenuItem()
    private let updateItem = NSMenuItem()

    init(settings: AppSettings, engine: ScrollEngine, updater: Updater, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.engine = engine
        self.updater = updater
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Smolix")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Smolix"
        }
        statusItem.menu = buildMenu()

        Publishers.CombineLatest3(settings.$smoothEnabled, engine.$state, settings.$hideMenuBarIcon)
            .sink { [weak self] smooth, state, hidden in
                MainActor.assumeIsolated {
                    self?.applyAppearance(smooth: smooth, state: state, hidden: hidden)
                }
            }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        headerItem.isEnabled = false
        menu.addItem(headerItem)

        permissionItem.title = "Cấp quyền Trợ năng…"
        permissionItem.target = self
        permissionItem.action = #selector(openAccessibility)
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        smoothItem.title = "Cuộn mượt"
        smoothItem.target = self
        smoothItem.action = #selector(toggleSmooth)
        menu.addItem(smoothItem)

        reverseItem.title = "Đảo chiều cuộn chuột"
        reverseItem.target = self
        reverseItem.action = #selector(toggleReverse)
        menu.addItem(reverseItem)

        menu.addItem(.separator())

        updateItem.target = self
        updateItem.action = #selector(checkForUpdates)
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: "Cài đặt…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Thoát Smolix", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        engine.healthCheck()
        switch engine.state {
        case .running: headerItem.title = settings.smoothEnabled ? "Smolix đang chạy" : "Smolix đang tạm tắt"
        case .needsPermission: headerItem.title = "Smolix cần quyền Trợ năng"
        case .failed: headerItem.title = "Smolix không chặn được cuộn chuột"
        case .starting: headerItem.title = "Smolix đang khởi động…"
        }
        permissionItem.isHidden = engine.state != .needsPermission
        smoothItem.state = settings.smoothEnabled ? .on : .off
        reverseItem.state = settings.reverseEnabled ? .on : .off
        if let version = updater.pendingVersion {
            updateItem.title = "Cài bản cập nhật \(version)…"
            updateItem.isEnabled = true
        } else {
            updateItem.title = "Kiểm tra cập nhật…"
            updateItem.isEnabled = updater.canCheckForUpdates
        }
    }

    private func applyAppearance(smooth: Bool, state: EngineState, hidden: Bool) {
        statusItem.isVisible = !hidden
        statusItem.button?.appearsDisabled = !(smooth && state == .running)
    }

    @objc private func toggleSmooth() { settings.smoothEnabled.toggle() }
    @objc private func toggleReverse() { settings.reverseEnabled.toggle() }
    @objc private func showSettings() { openSettings() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func openAccessibility() { Accessibility.openSystemSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
