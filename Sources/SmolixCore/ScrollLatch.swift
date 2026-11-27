/// Keeps a smooth scroll in the window where the wheel was turned.
///
/// A glide is a stream of synthetic scroll events, and macOS delivers each one to whatever is
/// under the pointer *when it is posted*. If the pointer moves onto another window mid-glide,
/// the rest of the scroll would land there. (Posting the events at the original spot is not an
/// option: macOS warps the pointer to a posted scroll event's location.)
///
/// Moving the pointer around inside the same window is normal while scrolling and keeps the
/// glide going. Only reaching a different window stops it; turning the wheel there starts a
/// fresh scroll. Windows are identified by their window-server number; `nil` means unknown,
/// and an unknown window never stops a glide.
public struct ScrollLatch: Sendable, Equatable {
    /// The window the wheel was turned over, while a glide is in flight.
    public private(set) var window: Int?

    public init() {}

    /// A real wheel event over `current`. Returns true when the glide still in flight belongs
    /// to another window and must be dropped before adding the new scroll.
    public mutating func wheel(over current: Int?) -> Bool {
        let left = hasLeft(over: current)
        if let current { window = current }
        return left
    }

    /// True once the pointer is over a different window from the one being scrolled.
    public func hasLeft(over current: Int?) -> Bool {
        guard let window, let current else { return false }
        return current != window
    }

    /// The glide has finished or was cancelled.
    public mutating func release() {
        window = nil
    }
}
