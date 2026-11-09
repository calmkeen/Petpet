import XCTest

/// Exercises shipping navigation and game clocks on the selected watch simulator.
@MainActor
final class WatchSmallScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws { app.terminate() }

    func testLargeTextShootingStartPauseFinishReplayAndSavedBest() {
        app.terminate(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        testShootingStartPauseFinishReplayAndSavedBest()
    }

    func testLargeTextStairsControlsTimeoutResultAndReplay() {
        app.terminate(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        testStairsControlsTimeoutResultAndReplay()
    }

    func testDateSelectionReturnsToCalendar() {
        openStreak()
        chooseMonth(year: 2026, month: 2)
        XCTAssertTrue(app.buttons["watch.chooseMonth"].label.contains("2026년 2월"))
        reveal(app.buttons["watch.streakDate"])
        app.buttons["watch.streakDate"].tap()
        reveal(app.buttons["watch.streakValue.28"])
        XCTAssertFalse(app.buttons["watch.streakValue.29"].exists)
        app.buttons["watch.streakValue.28"].tap()
        XCTAssertTrue(app.staticTexts["watch.selectedDaySteps"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["watch.selectedDaySteps"].label.contains("2월 28일"))
        capture("40mm-date-selected-and-returned")
        app.buttons["watch.streakDate"].tap()
        capture("40mm-date-reopened")
        app.navigationBars["날짜"].buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["watch.streakDate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["watch.streakDate"].isHittable)
        let preservedDate = app.staticTexts["watch.selectedDaySteps"].label
        XCTAssertTrue(preservedDate.contains("2월 28일"), "Date after back: \(preservedDate)")
    }

    func testYearAndMonthSelectionReturnAndRespectLeapDay() {
        openStreak()
        chooseMonth(year: 2024, month: 2)
        reveal(app.buttons["watch.streakDate"])
        app.buttons["watch.streakDate"].tap()
        reveal(app.buttons["watch.streakValue.29"])
        XCTAssertFalse(app.buttons["watch.streakValue.30"].exists)
        app.buttons["watch.streakValue.29"].tap()
        XCTAssertTrue(app.staticTexts["watch.selectedDaySteps"].label.contains("2월 29일"))
        capture("40mm-leap-day-returned")
        reveal(app.buttons["watch.chooseMonth"], direction: -1)
        chooseMonth(year: 2025, month: 2)
        reveal(app.buttons["watch.streakDate"])
        XCTAssertTrue(app.buttons["watch.streakDate"].label.contains("1일"))
        app.buttons["watch.streakDate"].tap()
        reveal(app.buttons["watch.streakValue.28"])
        XCTAssertFalse(app.buttons["watch.streakValue.29"].exists)
        capture("40mm-common-year-date-limit")
    }

    func testShootingStartPauseFinishReplayAndSavedBest() {
        openGame("game.openShooting")
        assertFits(app.buttons["game.start"])
        capture("40mm-shooting-start")
        backgroundAndReturn()
        reveal(app.buttons["game.start"])
        app.buttons["game.start"].tap()
        XCTAssertFalse(app.buttons["game.resume"].exists, "Starting a ready game after background must start playing")
        XCTAssertTrue(app.buttons["game.pause"].firstMatch.waitForExistence(timeout: 3))
        let arena = app.descendants(matching: .any).matching(identifier: "game.shootingArena").firstMatch
        let originalPosition = arena.value as? String
        XCTAssertNotNil(originalPosition)
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.2)
        let crownPosition = arena.value as? String
        XCTAssertNotEqual(originalPosition, crownPosition)
        let percentage = Int((crownPosition ?? "").filter(\.isNumber)) ?? 50
        let destination = arena.coordinate(withNormalizedOffset: CGVector(dx: percentage > 50 ? 0.2 : 0.8, dy: 0.7))
        arena.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertNotEqual(crownPosition, arena.value as? String)
        app.buttons["game.pause"].firstMatch.tap()
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 3))
        capture("40mm-shooting-paused")
        app.buttons["game.resume"].tap()
        finishGame()
        capture("40mm-shooting-result")
        reveal(app.buttons["game.replay"])
        assertFits(app.buttons["game.replay"])
        app.buttons["game.replay"].tap()
        XCTAssertTrue(app.buttons["game.finish"].waitForExistence(timeout: 3))
        finishGame()
        app.terminate()
        app.launch()
        openGame("game.openShooting")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "최고 기록 ")).firstMatch.exists)
        assertFits(app.buttons["game.start"])
        capture("40mm-shooting-best-after-relaunch")
    }

    func testStairsControlsTimeoutResultAndReplay() {
        openGame("game.openStairs")
        assertFits(app.buttons["game.start"])
        capture("40mm-stairs-start")
        backgroundAndReturn()
        reveal(app.buttons["game.start"])
        app.buttons["game.start"].tap()
        XCTAssertFalse(app.buttons["game.resume"].exists, "Starting a ready game after background must start playing")
        app.buttons["game.pause"].firstMatch.tap()
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 3))
        assertFits(app.buttons["game.stairsLeft"])
        assertFits(app.buttons["game.stairsRight"])
        XCTAssertFalse(app.buttons["game.stairsLeft"].isEnabled)
        XCTAssertFalse(app.buttons["game.stairsRight"].isEnabled)
        capture("40mm-stairs-paused-controls")
        let canvas = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "다음 계단 ")).firstMatch
        XCTAssertGreaterThanOrEqual(canvas.frame.height, 40, "Keep the next stairs and pet visible with large text")
        let next = canvas.label
        app.buttons["game.resume"].tap()
        app.buttons[next.contains("왼쪽") ? "game.stairsLeft" : "game.stairsRight"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1계단")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["게임 결과"].firstMatch.waitForExistence(timeout: 12))
        capture("40mm-stairs-timeout-result")
        reveal(app.buttons["game.replay"])
        app.buttons["game.replay"].tap()
        XCTAssertTrue(app.buttons["game.finish"].waitForExistence(timeout: 3))
        finishGame()
        capture("40mm-stairs-finish-result")
    }

    private func openStreak() {
        reveal(app.buttons["watch.openStreak"], rotation: 0.6)
        app.buttons["watch.openStreak"].tap()
        XCTAssertTrue(app.buttons["watch.chooseMonth"].waitForExistence(timeout: 3))
    }

    private func chooseMonth(year: Int, month: Int) {
        app.buttons["watch.chooseMonth"].tap()
        XCTAssertTrue(app.buttons["watch.streakYearPicker"].waitForExistence(timeout: 3))
        app.buttons["watch.streakYearPicker"].tap()
        reveal(app.buttons["watch.streakValue.\(year)"])
        app.buttons["watch.streakValue.\(year)"].tap()
        XCTAssertTrue(app.buttons["watch.streakYearPicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["watch.streakYearPicker"].isHittable)
        XCTAssertTrue(app.buttons["watch.streakYearPicker"].label.contains(String(year)))
        app.buttons["watch.streakMonthPicker"].tap()
        reveal(app.buttons["watch.streakValue.\(month)"])
        app.buttons["watch.streakValue.\(month)"].tap()
        XCTAssertTrue(app.buttons["watch.streakMonthPicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["watch.streakMonthPicker"].isHittable)
        XCTAssertTrue(app.buttons["watch.streakMonthPicker"].label.contains("\(month)월"))
        reveal(app.buttons["선택 완료"])
        app.buttons["선택 완료"].tap()
        XCTAssertTrue(app.buttons["watch.chooseMonth"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["watch.chooseMonth"].isHittable)
    }

    private func openGame(_ id: String) {
        reveal(app.buttons["watch.openGames"], rotation: 0.6)
        app.buttons["watch.openGames"].tap()
        reveal(app.buttons[id])
        app.buttons[id].tap()
        XCTAssertTrue(app.buttons["game.start"].waitForExistence(timeout: 3))
        reveal(app.buttons["game.start"])
    }

    private func finishGame() {
        app.buttons["game.finish"].firstMatch.tap()
        let confirm = app.buttons["기록 남기고 마치기"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["게임 결과"].firstMatch.waitForExistence(timeout: 4))
    }

    private func backgroundAndReturn() {
        XCUIDevice.shared.press(.home)
        app.activate()
    }

    private func reveal(_ element: XCUIElement, direction: CGFloat = 1, rotation: CGFloat? = nil, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<24 {
            var scrollDirection = direction
            if element.exists {
                let frame = element.frame
                if element.isHittable && app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(frame) { return }
                if !frame.isEmpty { scrollDirection = frame.midY < app.windows.firstMatch.frame.midY ? -1 : 1 }
            }
            if let rotation {
                // Use the real Digital Crown to change the root's vertical pages.
                XCUIDevice.shared.rotateDigitalCrown(delta: scrollDirection * rotation)
            } else {
                // Short, slow vertical drags keep adjacent list snapshots overlapping.
                let startY = scrollDirection > 0 ? 0.83 : 0.45
                let endY = scrollDirection > 0 ? 0.45 : 0.83
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)),
                           withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
        XCTFail("Element never became hittable: \(element)\n\(app.debugDescription)", file: file, line: line)
    }

    private func assertFits(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame), "Clipped element: \(element.frame), app: \(app.frame)", file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
