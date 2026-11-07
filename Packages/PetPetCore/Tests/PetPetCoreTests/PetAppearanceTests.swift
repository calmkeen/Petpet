import XCTest
@testable import PetPetCore

final class PetAppearanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func steps(_ count: Int, day: String = "2026-11-08", loading: Bool = false) -> DailyStepState {
        DailyStepState(date: day, stepCount: count, isLoading: loading)
    }
    func testBackgroundMatchesAndroidHourBoundariesAndLocalTimeZone() {
        for hour in 0..<24 {
            let expected: PetDaylightPeriod = hour == 7 ? .dawn : (8...16).contains(hour) ? .day : hour == 17 ? .sunset : .night
            XCTAssertEqual(PetDaylightPeriod(hour: hour), expected)
            XCTAssertEqual(PetDaylightPeriod(hour: hour).usesLightText, hour < 7 || hour >= 18)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let dawn = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 7))!
        XCTAssertEqual(PetDaylightPeriod(date: dawn, calendar: calendar), .dawn)
    }
    func testOriginalFrameOrderTimingAndClockRollback() {
        let running = PetSpriteAnimation(.running)
        XCTAssertEqual([0.0,1.0/15,2.0/15,15.0/15,16.0/15].map { running.imageName(elapsed: $0) },
                       [0,1,2,15,0].map { String(format: "stepmate_fox_running_v3_%02d", $0) })
        XCTAssertEqual(running.imageName(elapsed: -10), "stepmate_fox_running_v3_00")
        XCTAssertEqual(running.imageName(elapsed: .infinity), "stepmate_fox_running_v3_00")
        XCTAssertFalse(PetSpriteAnimation(.idle).isAnimated)
    }
    func testGreetingUsesSixteenOrderedFramesAndMatchingIdleEndpoints() {
        let happy = PetSpriteAnimation(.touching)
        XCTAssertEqual(happy.frameInterval, 1.0 / 15)
        XCTAssertEqual(PetSpriteAnimation.greetingDuration, 16.0 / 15)
        let expected = (0..<16).map { String(format: "stepmate_fox_greeting_v3_%02d", $0) }
        XCTAssertEqual((0..<16).map { happy.imageName(elapsed: Double($0) / 15) }, expected)
        XCTAssertEqual(happy.imageName(elapsed: -1), expected[0])
        XCTAssertEqual(happy.imageName(elapsed: 20), expected[15])
        XCTAssertEqual(PetSpriteAnimation(.idle).imageName(elapsed: 0), expected[0])
        XCTAssertEqual(happy.posterImageName, expected[8])
        var state = PetAnimationState()
        state.setActive(true, at: now)
        XCTAssertTrue(state.touch(at: now))
        state.tick(at: now.addingTimeInterval(1.0))
        XCTAssertEqual(state.activity, .touching)
        state.tick(at: now.addingTimeInterval(16.0 / 15))
        XCTAssertEqual(state.activity, .idle)
    }
    func testExtendingRunningExpiryDoesNotRestartNativePlayback() {
        var state = PetAnimationState()
        state.setActive(true, at: now)
        state.observe(steps(10), at: now)
        state.observe(steps(11), at: now)
        let first = PetPlaybackRequest(state: state, suppressed: false)
        let oldDeadline = state.expiresAt
        state.observe(steps(12), at: now.addingTimeInterval(0.5))
        XCTAssertNotEqual(oldDeadline, state.expiresAt)
        XCTAssertEqual(first, PetPlaybackRequest(state: state, suppressed: false))
        XCTAssertFalse(PetPlaybackRequest(state: state, suppressed: true).isPlaying)
    }
    func testNewGestureStartsANewClipAndPreviewHasNoGameStorageDependency() {
        var state = PetAnimationState()
        state.setActive(true, at: now)
        state.touch(at: now)
        let first = PetPlaybackRequest(state: state, suppressed: false)
        state.tick(at: now.addingTimeInterval(2))
        state.touch(at: now.addingTimeInterval(2))
        XCTAssertNotEqual(first, PetPlaybackRequest(state: state, suppressed: false))
        #if DEBUG
        let preview = PetAnimationState.preview(.running, at: now)
        XCTAssertEqual(preview.activity, .running)
        XCTAssertTrue(PetPlaybackRequest(state: preview, suppressed: false).isPlaying)
        XCTAssertNil(preview.expiresAt)
        #endif
    }
    func testRestoredTotalsLoadingAndNewDayDoNotPretendToBeLiveSteps() {
        var state = PetAnimationState()
        state.setActive(true, at: now)
        state.observe(steps(0, loading: true), at: now)
        state.observe(steps(8000, loading: true), at: now)
        state.observe(steps(8000), at: now)
        XCTAssertEqual(state.activity, .idle)
        state.observe(steps(7999), at: now)
        state.observe(steps(8000), at: now)
        XCTAssertEqual(state.activity, .idle)
        state.observe(steps(8001), at: now)
        XCTAssertEqual(state.activity, .running)
        state.observe(steps(0, day: "2026-11-09"), at: now)
        XCTAssertEqual(state.activity, .idle)
        XCTAssertNil(state.expiresAt)
    }
    func testNewStepsExtendRunningWithoutRestartingFramesAndStopAfterTwoSeconds() {
        var state = PetAnimationState()
        state.setActive(true, at: now)
        state.observe(steps(100), at: now)
        state.observe(steps(101), at: now)
        state.observe(steps(102), at: now.addingTimeInterval(1))
        XCTAssertEqual(state.startedAt, now)
        XCTAssertEqual(state.expiresAt, now.addingTimeInterval(3))
        state.tick(at: now.addingTimeInterval(2.1))
        XCTAssertEqual(state.activity, .running)
        state.tick(at: now.addingTimeInterval(3))
        XCTAssertEqual(state.activity, .idle)
    }
    func testTouchIsGatedDuringRunningOrReactionAndResumesAfterHappySequence() {
        var state = PetAnimationState()
        XCTAssertFalse(state.touch(at: now))
        state.setActive(true, at: now)
        state.observe(steps(1), at: now)
        state.observe(steps(2), at: now)
        XCTAssertFalse(state.touch(at: now))
        XCTAssertTrue(state.touch(at: now.addingTimeInterval(2)))
        XCTAssertFalse(state.touch(at: now.addingTimeInterval(2.4)))
        state.observe(steps(3), at: now.addingTimeInterval(2.5))
        XCTAssertEqual(state.activity, .touching)
        state.tick(at: now.addingTimeInterval(3.3))
        XCTAssertEqual(state.activity, .idle)
        XCTAssertTrue(state.touch(at: now.addingTimeInterval(3.3)))
    }
    func testOffscreenAndForegroundBaselineDoNotReplayOldActivity() {
        var state = PetAnimationState()
        state.setActive(true, at: now)
        state.observe(steps(1), at: now)
        state.observe(steps(2), at: now)
        state.setActive(false, at: now)
        state.observe(steps(100), at: now)
        XCTAssertEqual(state.activity, .idle)
        XCTAssertNil(state.expiresAt)
        state.setActive(true, at: now)
        state.observe(steps(200), at: now)
        XCTAssertEqual(state.activity, .idle)
        state.observe(steps(201), at: now)
        XCTAssertEqual(state.activity, .running)
    }
}
