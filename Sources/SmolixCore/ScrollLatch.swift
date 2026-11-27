import CoreGraphics

/// Keeps a smooth scroll in the place where the wheel was turned.
///
/// A glide is a stream of synthetic scroll events, and macOS delivers each one to whatever is
/// under the pointer *when it is posted*. If the pointer moves on mid-glide, the rest of the
/// scroll would land in another window or pane. (Posting the events at the original spot is
/// not an option: macOS warps the pointer to a posted scroll event's location.)
///
/// So the glide stops as soon as the pointer leaves the spot; turning the wheel somewhere else
/// starts a fresh scroll there. Points are in any one consistent screen coordinate space.
public struct ScrollLatch: Sendable, Equatable {
    /// How far (points) the pointer may drift — hand jitter while turning the wheel — before
    /// the glide counts as abandoned.
    public static let radius: Double = 6

    /// Where the wheel was last turned, while a glide is in flight.
    public private(set) var anchor: CGPoint?

    public init() {}

    /// A real wheel event with the pointer at `point`. Returns true when the glide still in
    /// flight was started somewhere else and must be dropped before adding the new scroll.
    public mutating func wheel(at point: CGPoint) -> Bool {
        defer { anchor = point }
        return hasMoved(to: point)
    }

    /// True once the pointer is farther than `radius` from where the wheel was last turned.
    public func hasMoved(to point: CGPoint) -> Bool {
        guard let anchor else { return false }
        return hypot(point.x - anchor.x, point.y - anchor.y) > Self.radius
    }

    /// The glide has finished or was cancelled.
    public mutating func release() {
        anchor = nil
    }
}
