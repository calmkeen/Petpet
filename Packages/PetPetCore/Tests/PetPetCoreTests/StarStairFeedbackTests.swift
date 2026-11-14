import XCTest
@testable import PetPetCore

/// Compile during implementation; execute in the separately requested review.
final class StarStairFeedbackTests: XCTestCase {
    func testSuccessReturnsTheAcceptedDirectionBeforeTheNextStairChanges() {
        var game = StarStairGame(seed: 7); game.start()
        for _ in 0..<20 {
            let direction = game.nextDirection, previousScore = game.score
            XCTAssertEqual(game.input(direction), .correct(direction))
            XCTAssertEqual(game.score, previousScore + 1)
            XCTAssertEqual(game.life, 3)
        }
    }
    func testRepeatedWrongInputsEachProduceFeedbackAndLoseOneLife() {
        var game = StarStairGame(seed: 3); game.start()
        let direction = game.nextDirection
        for expectedLife in [2, 1, 0] {
            XCTAssertEqual(game.input(direction.opposite), .wrong)
            XCTAssertEqual(game.life, expectedLife)
            XCTAssertEqual(game.score, 0)
        }
        XCTAssertEqual(game.status, .finished)
        XCTAssertNil(game.input(direction.opposite))
    }
    func testTimerReturnsTimeoutIncludingTheFinalLifeAndNoDuplicateAfterFinish() {
        var game = StarStairGame(seed: 2); game.start()
        XCTAssertNil(game.advance(seconds: 1.49))
        XCTAssertEqual(game.advance(seconds: 0.02), .timeout)
        XCTAssertEqual(game.life, 2)
        XCTAssertNil(game.advance(seconds: 0.01))
        XCTAssertEqual(game.advance(seconds: 2), .timeout)
        XCTAssertEqual(game.advance(seconds: 2), .timeout)
        XCTAssertEqual(game.status, .finished)
        XCTAssertEqual(game.life, 0)
        XCTAssertNil(game.advance(seconds: 10))
        XCTAssertNil(game.input(game.nextDirection))
    }
    func testManualFinishDoesNotCreateFailureFeedback() {
        var game = StarStairGame(seed: 1)
        XCTAssertNil(game.advance(seconds: 2))
        XCTAssertNil(game.input(.left))
        game.start(); game.finish()
        XCTAssertNil(game.advance(seconds: 2))
        XCTAssertNil(game.input(.right))
    }
    func testInvalidElapsedTimeDoesNotConsumeLifeOrProduceFeedback() {
        var game = StarStairGame(seed: 1); game.start()
        for seconds in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(game.advance(seconds: seconds))
            XCTAssertEqual(game.life, 3)
            XCTAssertEqual(game.remaining, 1.5)
        }
    }
}
