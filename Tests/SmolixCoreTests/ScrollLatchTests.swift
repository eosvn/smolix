import CoreGraphics
import XCTest
@testable import SmolixCore

final class ScrollLatchTests: XCTestCase {
    func testFirstWheelNeverDropsAnything() {
        var latch = ScrollLatch()
        XCTAssertFalse(latch.wheel(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(latch.anchor, CGPoint(x: 100, y: 100))
    }

    func testHandJitterKeepsTheGlide() {
        var latch = ScrollLatch()
        _ = latch.wheel(at: CGPoint(x: 100, y: 100))
        XCTAssertFalse(latch.hasMoved(to: CGPoint(x: 103, y: 98)))
        XCTAssertFalse(latch.wheel(at: CGPoint(x: 104, y: 103)))
    }

    func testLeavingTheSpotEndsTheGlide() {
        var latch = ScrollLatch()
        _ = latch.wheel(at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(latch.hasMoved(to: CGPoint(x: 100, y: 100 + ScrollLatch.radius + 1)))
        XCTAssertTrue(latch.hasMoved(to: CGPoint(x: 400, y: 100)))
    }

    func testWheelSomewhereElseDropsTheOldGlideAndMovesTheAnchor() {
        var latch = ScrollLatch()
        _ = latch.wheel(at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(latch.wheel(at: CGPoint(x: 300, y: 100)))
        XCTAssertEqual(latch.anchor, CGPoint(x: 300, y: 100))
        XCTAssertFalse(latch.hasMoved(to: CGPoint(x: 302, y: 101)))
    }

    func testAnchorFollowsSlowDriftWhileTheWheelKeepsTurning() {
        var latch = ScrollLatch()
        // Each notch drifts 4 pt: never far from the previous notch, so nothing is dropped,
        // even though the pointer ends up well away from where it started.
        for i in 0...10 {
            XCTAssertFalse(latch.wheel(at: CGPoint(x: 100 + Double(i) * 4, y: 100)))
        }
        XCTAssertFalse(latch.hasMoved(to: CGPoint(x: 140, y: 100)))
    }

    func testReleasedLatchIgnoresMovement() {
        var latch = ScrollLatch()
        _ = latch.wheel(at: CGPoint(x: 100, y: 100))
        latch.release()
        XCTAssertNil(latch.anchor)
        XCTAssertFalse(latch.hasMoved(to: CGPoint(x: 900, y: 900)))
        XCTAssertFalse(latch.wheel(at: CGPoint(x: 900, y: 900)))
    }
}
