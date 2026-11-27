import AppKit
import QuartzCore

/// Finds which app owns the window under the mouse (scroll events go there, not necessarily
/// to the frontmost app). Uses the on-screen window list: owner PID and bounds are available
/// without Screen Recording permission. ~2 ms per lookup, so results are cached while the
/// cursor stays put (a whole wheel flick costs one lookup).
@MainActor
final class AppUnderCursor {
    /// Terminals scroll by whole lines (and tmux/TUIs turn every wheel report into N lines),
    /// so smoothing there only makes scrolling faster without making it look smoother.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "org.tabby",
    ]

    private var cachedBundleID: String?
    private var cachedPoint = CGPoint(x: CGFloat.nan, y: .nan)
    private var cachedAt: CFTimeInterval = 0

    private static let cacheLifetime: CFTimeInterval = 0.5
    private static let cacheRadius: CGFloat = 8

    /// - Parameter point: global display coordinates, top-left origin (`CGEvent.location`).
    func bundleID(at point: CGPoint) -> String? {
        let now = CACurrentMediaTime()
        if now - cachedAt < Self.cacheLifetime,
           abs(point.x - cachedPoint.x) < Self.cacheRadius,
           abs(point.y - cachedPoint.y) < Self.cacheRadius {
            return cachedBundleID
        }
        cachedBundleID = Self.lookup(at: point)
        cachedPoint = point
        cachedAt = now
        return cachedBundleID
    }

    func isTerminal(at point: CGPoint) -> Bool {
        guard let id = bundleID(at: point) else { return false }
        return Self.terminalBundleIDs.contains(id)
    }

    private static func lookup(at point: CGPoint) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // Front-to-back order; layer 0 = normal app windows (skips menu bar, Dock, overlays).
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? Int
            else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            return NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        }
        return nil
    }
}
