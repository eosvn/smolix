import Foundation

public enum ScrollMath {
    /// Signed pixel distance to add for one discrete wheel event.
    ///
    /// - Parameter lines: the event's line delta as reported by macOS (already includes the
    ///   system's wheel acceleration, so it grows when the wheel is spun fast).
    public static func distance(lines: Double, parameters: ScrollParameters) -> Double {
        guard lines != 0, lines.isFinite else { return 0 }
        let p = parameters.clamped()
        let magnitude = max(abs(lines), 1)
        let factor = 1 + (magnitude - 1) * p.acceleration
        return (lines < 0 ? -1 : 1) * p.step * factor
    }

    /// How "fast" a wheel event is, 0…1, from macOS's accelerated line delta.
    /// A slow notch reports ~0.1 lines, a fast spin climbs to ~10–13 lines within a few notches.
    public static func glideBoost(lines: Double) -> Double {
        guard lines.isFinite else { return 0 }
        return min(max((abs(lines) - 1) / 9, 0), 1)
    }

    /// Animation duration for the current scroll: longer when the wheel was spun fast,
    /// so a flick keeps gliding instead of stopping abruptly.
    public static func effectiveDurationMs(_ parameters: ScrollParameters, boost: Double) -> Double {
        let p = parameters.clamped()
        let b = boost.isFinite ? min(max(boost, 0), 1) : 0
        return p.durationMs * (1 + p.glide * b)
    }

    /// Fraction of the remaining distance to cover during a frame lasting `dt` seconds.
    ///
    /// Exponential ease-out that is independent of the display's refresh rate
    /// (60 Hz, 120 Hz ProMotion, external monitors all feel the same).
    /// After `durationMs` about 95% of the distance has been scrolled.
    public static func frameFraction(dt: Double, durationMs: Double) -> Double {
        guard dt.isFinite, dt > 0 else { return 0 }
        let duration = min(max(durationMs, 1), 10_000) / 1000
        let tau = duration / 3          // e^-3 ≈ 5% left after `duration`
        let clampedDt = min(dt, 0.1)    // a stalled frame must not teleport the page
        return 1 - exp(-clampedDt / tau)
    }
}

/// The three delta fields macOS puts on a wheel event for one axis.
/// Mutating one field can make CoreGraphics recompute the others, so read all three first.
public struct WheelDelta: Equatable, Sendable {
    public var line: Int64      // scrollWheelEventDeltaAxis
    public var fixed: Double    // scrollWheelEventFixedPtDeltaAxis
    public var point: Int64     // scrollWheelEventPointDeltaAxis

    public init(line: Int64, fixed: Double, point: Int64) {
        self.line = line
        self.fixed = fixed
        self.point = point
    }

    public var negated: WheelDelta { WheelDelta(line: -line, fixed: -fixed, point: -point) }
}

/// Remaining scroll distance on one axis, emitted as whole pixels frame by frame.
public struct SmoothAxis: Sendable, Equatable {
    /// Pixels still to be scrolled (signed).
    public private(set) var remaining: Double = 0
    /// Sub-pixel residue carried to the next frame so no distance is lost to rounding.
    private var carry: Double = 0

    /// Below this many pixels left, the rest is emitted at once instead of a long 1px tail.
    public static let finishThreshold: Double = 1.0
    /// Hard cap so a frantic wheel spin can't queue an absurd distance.
    public static let maxRemaining: Double = 30_000

    public init() {}

    public var isIdle: Bool { remaining == 0 }

    public mutating func add(_ distance: Double) {
        guard distance != 0, distance.isFinite else { return }
        if remaining * distance < 0 {
            // Direction changed: drop the old momentum so the page reverses immediately.
            remaining = 0
            carry = 0
        }
        remaining = min(max(remaining + distance, -Self.maxRemaining), Self.maxRemaining)
    }

    /// Advances one frame and returns the whole pixels to post for it (may be 0).
    public mutating func advance(fraction: Double) -> Int32 {
        guard remaining != 0 else { return 0 }
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 1
        var move = remaining * f
        let finishing = abs(remaining - move) < Self.finishThreshold
        if finishing { move = remaining }
        remaining -= move

        let total = move + carry
        let whole: Double
        if finishing {
            whole = total.rounded()
            carry = 0
            remaining = 0
        } else {
            whole = total.rounded(.towardZero)
            carry = total - whole
        }
        return Int32(clamping: Int(whole))
    }

    public mutating func reset() {
        remaining = 0
        carry = 0
    }
}
