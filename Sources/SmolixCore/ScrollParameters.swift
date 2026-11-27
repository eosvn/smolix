import Foundation

/// User-tunable feel of the smooth scroll.
public struct ScrollParameters: Equatable, Sendable {
    /// Pixels scrolled for one slow wheel notch.
    public var step: Double
    /// How much fast wheel spinning (OS-accelerated line deltas) amplifies the step.
    /// 0 = every notch scrolls exactly `step`.
    public var acceleration: Double
    /// Time (ms) for a scroll to be ~95% finished. Higher = floatier.
    public var durationMs: Double
    /// Extra glide when the wheel is spun fast: duration grows by up to `glide × 100%`.
    /// 0 = fast and slow scrolls glide equally long.
    public var glide: Double

    public init(step: Double, acceleration: Double, durationMs: Double, glide: Double = 1.0) {
        self.step = step
        self.acceleration = acceleration
        self.durationMs = durationMs
        self.glide = glide
    }

    public static let stepRange: ClosedRange<Double> = 10...200
    public static let accelerationRange: ClosedRange<Double> = 0...3
    public static let durationRange: ClosedRange<Double> = 80...800
    public static let glideRange: ClosedRange<Double> = 0...3

    public static let `default` = ScrollParameters(step: 52, acceleration: 1.0, durationMs: 320, glide: 1.0)

    public func clamped() -> ScrollParameters {
        ScrollParameters(
            step: Self.clamp(step, to: Self.stepRange, fallback: Self.default.step),
            acceleration: Self.clamp(acceleration, to: Self.accelerationRange, fallback: Self.default.acceleration),
            durationMs: Self.clamp(durationMs, to: Self.durationRange, fallback: Self.default.durationMs),
            glide: Self.clamp(glide, to: Self.glideRange, fallback: Self.default.glide)
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
