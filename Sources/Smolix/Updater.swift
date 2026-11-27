import AppKit
import Sparkle

/// In-app updates via Sparkle, fed by the `appcast.xml` attached to the latest GitHub release.
/// Checks once a day on its own; "Kiểm tra cập nhật…" in the menu checks right away.
///
/// Smolix has no Dock icon, so an update found by a background check opens behind other
/// windows and is easy to miss. While such an update waits, the menu item turns into
/// "Cài bản cập nhật x.y.z…", which brings the update window to the front.
@MainActor
final class Updater: NSObject {
    /// Version of an update a background check found and the user hasn't looked at yet.
    private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Checks now, or brings an update that was already found to the front.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // The user asked for this one and is looking at it already.
        guard !state.userInitiated else { return }
        pendingVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}
