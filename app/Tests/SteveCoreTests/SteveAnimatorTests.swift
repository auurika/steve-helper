import XCTest
@testable import SteveCore

final class SteveAnimatorTests: XCTestCase {
    func testSleepingFrameHasClosedEyesAndLetters() {
        let frame = SteveAnimator.frame(animation: nil, asleep: true, elapsed: 0, clock: 5)
        XCTAssertEqual(frame.eyeScaleY, 0.14, accuracy: 0.001)
        XCTAssertEqual(frame.letters.count, 3)
        XCTAssertGreaterThan(frame.rootOffsetY, 0) // осел вниз
    }

    func testBlinkClosesEyesOnlyInTheMiddle() {
        let open = SteveAnimator.frame(animation: .blink, asleep: false, elapsed: 0.02, clock: 0)
        let closed = SteveAnimator.frame(animation: .blink, asleep: false, elapsed: 0.15, clock: 0)
        XCTAssertEqual(open.eyeScaleY, 1)
        XCTAssertEqual(closed.eyeScaleY, 0.1, accuracy: 0.001)
    }

    func testLookLeftAndRightMirror() {
        let left = SteveAnimator.frame(animation: .lookLeft, asleep: false, elapsed: 0.9, clock: 0)
        let right = SteveAnimator.frame(animation: .lookRight, asleep: false, elapsed: 0.9, clock: 0)
        XCTAssertEqual(left.eyeOffsetX, -right.eyeOffsetX)
    }

    func testFollowUsesGivenOffsetAndLooksDown() {
        let frame = SteveAnimator.frame(animation: .follow, asleep: false, elapsed: 3, clock: 3, followX: 5)
        XCTAssertEqual(frame.eyeOffsetX, 5)
        XCTAssertGreaterThan(frame.eyeOffsetY, 0)
    }

    func testHeldStatesNeverEnd() {
        for animation in [SteveAnimation.listen, .work, .talk, .follow] {
            XCTAssertNil(animation.duration)
        }
        XCTAssertNotNil(SteveAnimation.happy.duration)
    }

    func testThinkShowsGrowingDots() {
        let early = SteveAnimator.frame(animation: .think, asleep: false, elapsed: 0.2, clock: 0)
        let late = SteveAnimator.frame(animation: .think, asleep: false, elapsed: 2.0, clock: 0)
        XCTAssertEqual(early.thoughtDots, 0)
        XCTAssertEqual(late.thoughtDots, 3)
    }

    func testSurpriseShowsBang() {
        XCTAssertTrue(SteveAnimator.frame(animation: .surprise, asleep: false, elapsed: 0.5, clock: 0).showBang)
        XCTAssertFalse(SteveAnimator.frame(animation: .surprise, asleep: false, elapsed: 1.7, clock: 0).showBang)
    }
}
