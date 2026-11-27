import XCTest
@testable import SmolixCore

final class ScrollMathTests: XCTestCase {
    let p = ScrollParameters(step: 40, acceleration: 1, durationMs: 300)

    func testSlowNotchScrollsExactlyOneStep() {
        XCTAssertEqual(ScrollMath.distance(lines: 1, parameters: p), 40)
        XCTAssertEqual(ScrollMath.distance(lines: -1, parameters: p), -40)
    }

    func testSubLineDeltaStillScrollsAtLeastOneStep() {
        XCTAssertEqual(ScrollMath.distance(lines: 0.1, parameters: p), 40)
        XCTAssertEqual(ScrollMath.distance(lines: -0.3, parameters: p), -40)
    }

    func testZeroAndGarbageDeltaScrollNothing() {
        XCTAssertEqual(ScrollMath.distance(lines: 0, parameters: p), 0)
        XCTAssertEqual(ScrollMath.distance(lines: .nan, parameters: p), 0)
        XCTAssertEqual(ScrollMath.distance(lines: .infinity, parameters: p), 0)
    }

    func testFastSpinIsAmplifiedByAcceleration() {
        XCTAssertEqual(ScrollMath.distance(lines: 3, parameters: p), 120)       // 40 * (1 + 2*1)
        var half = p; half.acceleration = 0.5
        XCTAssertEqual(ScrollMath.distance(lines: 3, parameters: half), 80)     // 40 * (1 + 2*0.5)
        var none = p; none.acceleration = 0
        XCTAssertEqual(ScrollMath.distance(lines: 3, parameters: none), 40)
    }

    func testParametersAreClampedIntoRange() {
        let wild = ScrollParameters(step: 5000, acceleration: -2, durationMs: .nan).clamped()
        XCTAssertEqual(wild.step, ScrollParameters.stepRange.upperBound)
        XCTAssertEqual(wild.acceleration, 0)
        XCTAssertEqual(wild.durationMs, ScrollParameters.default.durationMs)
    }

    func testFrameFractionReaches95PercentAfterDuration() {
        // Simulate 120 Hz frames for exactly `duration`.
        var left = 1.0
        let dt = 1.0 / 120
        for _ in 0..<Int(0.3 / dt) {
            left *= 1 - ScrollMath.frameFraction(dt: dt, durationMs: 300)
        }
        XCTAssertEqual(left, 0.05, accuracy: 0.01)
    }

    func testFrameFractionIsRefreshRateIndependent() {
        var at60 = 1.0, at120 = 1.0
        for _ in 0..<6 { at60 *= 1 - ScrollMath.frameFraction(dt: 1.0 / 60, durationMs: 300) }
        for _ in 0..<12 { at120 *= 1 - ScrollMath.frameFraction(dt: 1.0 / 120, durationMs: 300) }
        XCTAssertEqual(at60, at120, accuracy: 1e-9)
    }

    func testFrameFractionHandlesBadDt() {
        XCTAssertEqual(ScrollMath.frameFraction(dt: 0, durationMs: 300), 0)
        XCTAssertEqual(ScrollMath.frameFraction(dt: -1, durationMs: 300), 0)
        XCTAssertLessThan(ScrollMath.frameFraction(dt: 5, durationMs: 300), 1) // stalled frame is capped
    }
}

final class SmoothAxisTests: XCTestCase {
    private func run(_ axis: inout SmoothAxis, frames: Int = 1000) -> (sum: Int, frames: Int) {
        var sum = 0
        var used = 0
        while !axis.isIdle && used < frames {
            sum += Int(axis.advance(fraction: ScrollMath.frameFraction(dt: 1.0 / 120, durationMs: 300)))
            used += 1
        }
        return (sum, used)
    }

    func testEmitsTheWholeDistanceAndStops() {
        var axis = SmoothAxis()
        axis.add(44)
        let r = run(&axis)
        XCTAssertEqual(r.sum, 44)
        XCTAssertTrue(axis.isIdle)
        XCTAssertLessThan(r.frames, 120, "should settle well within a second at 120 Hz")
    }

    func testFractionalDistanceIsNotLostToRounding() {
        var axis = SmoothAxis()
        for _ in 0..<7 { axis.add(13.3) }   // 93.1 px
        XCTAssertEqual(run(&axis).sum, 93)
    }

    func testNegativeDistance() {
        var axis = SmoothAxis()
        axis.add(-120)
        XCTAssertEqual(run(&axis).sum, -120)
    }

    func testTicksDuringAnimationAccumulate() {
        var axis = SmoothAxis()
        axis.add(40)
        var sum = 0
        for _ in 0..<5 { sum += Int(axis.advance(fraction: 0.1)) }
        axis.add(40)
        sum += run(&axis).sum
        XCTAssertEqual(sum, 80)
    }

    func testDirectionChangeDropsOldMomentum() {
        var axis = SmoothAxis()
        axis.add(400)
        _ = axis.advance(fraction: 0.1)
        axis.add(-40)
        XCTAssertEqual(axis.remaining, -40)
        XCTAssertEqual(run(&axis).sum, -40)
    }

    func testRemainingIsCapped() {
        var axis = SmoothAxis()
        for _ in 0..<10_000 { axis.add(200) }
        XCTAssertEqual(axis.remaining, SmoothAxis.maxRemaining)
    }

    func testFirstFrameMovesImmediately() {
        var axis = SmoothAxis()
        axis.add(44)
        let first = axis.advance(fraction: ScrollMath.frameFraction(dt: 1.0 / 120, durationMs: 320))
        XCTAssertGreaterThan(first, 0)
    }
}

final class GlideTests: XCTestCase {
    func testSlowNotchHasNoGlideBoost() {
        XCTAssertEqual(ScrollMath.glideBoost(lines: 0.1), 0)
        XCTAssertEqual(ScrollMath.glideBoost(lines: -1), 0)
    }

    func testFastSpinHasFullGlideBoost() {
        XCTAssertEqual(ScrollMath.glideBoost(lines: 10), 1)
        XCTAssertEqual(ScrollMath.glideBoost(lines: -13.5), 1)
        XCTAssertEqual(ScrollMath.glideBoost(lines: 5.5), 0.5, accuracy: 1e-9)
    }

    func testEffectiveDurationGrowsWithBoost() {
        let p = ScrollParameters(step: 50, acceleration: 1, durationMs: 300, glide: 1)
        XCTAssertEqual(ScrollMath.effectiveDurationMs(p, boost: 0), 300)
        XCTAssertEqual(ScrollMath.effectiveDurationMs(p, boost: 1), 600)
        var none = p; none.glide = 0
        XCTAssertEqual(ScrollMath.effectiveDurationMs(none, boost: 1), 300)
        XCTAssertEqual(ScrollMath.effectiveDurationMs(p, boost: .nan), 300)
    }
}

final class WheelDeltaTests: XCTestCase {
    func testNegatedFlipsEveryField() {
        let d = WheelDelta(line: 5, fixed: 5.169785, point: 52)
        XCTAssertEqual(d.negated, WheelDelta(line: -5, fixed: -5.169785, point: -52))
        XCTAssertEqual(d.negated.negated, d)
    }
}
