import XCTest
@testable import PetPetCore

final class PetFrameBlendTests: XCTestCase {
    func testHalfFrameUsesEqualWeightsInsteadOfAnAbruptSwap() {
        let animation = PetSpriteAnimation(.touching)
        let sample = animation.blend(elapsed: animation.frameInterval / 2)
        XCTAssertEqual(sample.fromIndex, 0); XCTAssertEqual(sample.toIndex, 1)
        XCTAssertEqual(sample.amount, 0.5, accuracy: 0.0001)
    }
    func testRunningInterpolatesAcrossTheLoopBoundary() {
        let animation = PetSpriteAnimation(.running)
        let sample = animation.blend(elapsed: animation.cycleDuration - animation.frameInterval / 2)
        XCTAssertEqual(sample.fromIndex, 15); XCTAssertEqual(sample.toIndex, 0)
        XCTAssertEqual(sample.amount, 0.5, accuracy: 0.0001)
        XCTAssertEqual(animation.blend(elapsed: animation.cycleDuration).fromIndex, 0)
    }
    func testGreetingHoldsTheLastFrameAndInvalidTimesStayInBounds() {
        let animation = PetSpriteAnimation(.touching)
        let last = animation.blend(elapsed: 100)
        XCTAssertEqual(last.fromIndex, 15); XCTAssertEqual(last.toIndex, 15); XCTAssertEqual(last.amount, 0)
        for time in [-1.0, .nan, .infinity] {
            let sample = animation.blend(elapsed: time)
            XCTAssertEqual(sample.fromIndex, 0); XCTAssertEqual(sample.amount, 0)
        }
        let idle = PetSpriteAnimation(.idle).blend(elapsed: 1)
        XCTAssertEqual(idle.fromIndex, idle.toIndex); XCTAssertEqual(idle.amount, 0)
    }
}
