import XCTest
@testable import SmolixCore

final class ScrollLatchTests: XCTestCase {
    func testFirstWheelNeverDropsAnything() {
        var latch = ScrollLatch()
        XCTAssertFalse(latch.wheel(over: 7))
        XCTAssertEqual(latch.window, 7)
    }

    func testMovingAroundTheSameWindowKeepsTheGlide() {
        var latch = ScrollLatch()
        _ = latch.wheel(over: 7)
        // The pointer can travel anywhere inside the window: the window is all that counts.
        XCTAssertFalse(latch.hasLeft(over: 7))
        XCTAssertFalse(latch.wheel(over: 7))
    }

    func testMovingOntoAnotherWindowEndsTheGlide() {
        var latch = ScrollLatch()
        _ = latch.wheel(over: 7)
        XCTAssertTrue(latch.hasLeft(over: 9))
    }

    func testWheelOverAnotherWindowDropsTheOldGlideAndMovesTheLatch() {
        var latch = ScrollLatch()
        _ = latch.wheel(over: 7)
        XCTAssertTrue(latch.wheel(over: 9))
        XCTAssertEqual(latch.window, 9)
        XCTAssertFalse(latch.hasLeft(over: 9))
    }

    func testUnknownWindowNeverStopsAGlide() {
        var latch = ScrollLatch()
        _ = latch.wheel(over: 7)
        XCTAssertFalse(latch.hasLeft(over: nil))
        XCTAssertFalse(latch.wheel(over: nil))
        XCTAssertEqual(latch.window, 7, "an unknown window keeps the latch where it was")
    }

    func testReleasedLatchIgnoresMovement() {
        var latch = ScrollLatch()
        _ = latch.wheel(over: 7)
        latch.release()
        XCTAssertNil(latch.window)
        XCTAssertFalse(latch.hasLeft(over: 9))
        XCTAssertFalse(latch.wheel(over: 9))
    }
}
