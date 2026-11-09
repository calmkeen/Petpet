import XCTest

@MainActor
final class WatchGameFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }

    func test10ShootingResultSubmitsAndReplayKeepsBest() {
        openGame("game.openShooting")
        reveal(app.buttons["game.start"]); app.buttons["game.start"].tap()
        let pause = app.buttons["game.pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 4)); pause.tap()
        let combo = app.staticTexts["game.combo"]
        XCTAssertTrue(combo.waitForExistence(timeout: 3)); XCTAssertTrue(combo.label.hasSuffix("COMBO!"))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(combo.frame), "The shooting combo must fit the 40mm watch")
        XCTAssertTrue(app.buttons["game.resume"].waitForExistence(timeout: 4))
        capture("games-shooting-paused")
        app.buttons["game.resume"].tap()
        let arena = app.descendants(matching: .any).matching(identifier: "game.shootingArena").firstMatch
        if arena.exists {
            arena.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: arena.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in self.app.staticTexts["game.finalScore"].exists }, object: nil)], timeout: 8)
        finishIfPlaying()
        let best = Int(app.staticTexts["game.bestScore"].label.filter(\.isNumber)) ?? 0
        assertSubmitted()
        capture("games-shooting-submitted")
        reveal(app.buttons["game.replay"], down: false); app.buttons["game.replay"].tap()
        XCTAssertTrue(app.buttons["game.finish"].waitForExistence(timeout: 4))
        finishIfPlaying()
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["game.bestScore"].label.filter(\.isNumber)) ?? -1, best)
        assertSubmitted()
        app.terminate(); app.launch(); openGame("game.openShooting")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "최고 기록 ")).firstMatch.exists)
        capture("games-shooting-best-after-relaunch")
    }

    func test11StairsResultSubmitsAndLeaderboardReloads() {
        openGame("game.openStairs")
        reveal(app.buttons["game.start"]); app.buttons["game.start"].tap()
        app.buttons["game.pause"].firstMatch.tap()
        let direction = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "다음 계단 ")).firstMatch.label
        XCTAssertFalse(app.buttons["game.stairsLeft"].isEnabled)
        app.buttons["game.resume"].tap()
        app.buttons[direction.contains("왼쪽") ? "game.stairsLeft" : "game.stairsRight"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1계단")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["game.finalScore"].waitForExistence(timeout: 12))
        assertSubmitted(); capture("games-stairs-submitted")
        app.terminate(); app.launch(); openLibrary()
        let ranking = app.buttons["game.openRanking.starStair"]
        reveal(ranking); ranking.tap()
        reveal(app.staticTexts["game.rankName.900000001"])
        XCTAssertTrue(app.staticTexts["game.rankScore.900000001"].exists)
        reveal(app.buttons["game.refreshRanking"], down: false); app.buttons["game.refreshRanking"].tap()
        reveal(app.staticTexts["game.rankName.900000001"])
        capture("games-stairs-ranking-reloaded")
    }

    func test12StandaloneRankingRefresh() {
        openLibrary()
        reveal(app.buttons["game.openRanking.starStair"]); app.buttons["game.openRanking.starStair"].tap()
        reveal(app.staticTexts["game.rankName.900000001"])
        reveal(app.buttons["game.refreshRanking"], down: false)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in self.app.buttons["game.refreshRanking"].exists && self.app.buttons["game.refreshRanking"].isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        app.buttons["game.refreshRanking"].tap()
        reveal(app.staticTexts["game.rankName.900000001"])
        XCTAssertTrue(app.staticTexts["game.rankScore.900000001"].exists)
        capture("games-ranking-refresh-button")
    }

    func test20ChatThroughSystemInput() {
        openChat(); enterQuestion("Hello")
        for index in 1...6 {
            reveal(app.buttons["chat.send"], down: index == 1)
            XCTAssertTrue(app.buttons["chat.send"].isEnabled)
            app.buttons["chat.send"].tap()
            reveal(app.staticTexts["chat.status"])
            waitForStatus("AI 응답 완료")
            reveal(app.staticTexts["chat.answer"])
            XCTAssertTrue(app.staticTexts["chat.answer"].label.contains("Hello"))
            capture("games-chat-answer-\(index)")
        }
    }

    func test22ChatCancellationAndReturn() {
        openChat(); enterQuestion(Array(repeating: "cancel", count: 150).joined(separator: " "))
        reveal(app.buttons["chat.send"]); app.buttons["chat.send"].tap()
        XCTAssertTrue(app.buttons["chat.cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.cancel"].isHittable, "Cancellation must remain above the growing answer")
        app.buttons["chat.cancel"].tap()
        reveal(app.staticTexts["chat.status"], down: false); waitForStatus("응답을 중단했어요")
        reveal(app.buttons["chat.send"], down: false); XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        capture("games-chat-cancelled")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["watch.openChat"].waitForExistence(timeout: 4))
        app.buttons["watch.openChat"].tap()
        reveal(app.buttons["chat.send"]); XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        XCTAssertFalse(app.staticTexts["chat.answer"].exists)
        capture("games-chat-return-cleared")
    }

    func test31LoggedOutGameKeepsLocalRecordAndChatRequiresLogin() {
        openGame("game.openShooting")
        reveal(app.buttons["game.start"]); app.buttons["game.start"].tap(); finishIfPlaying()
        reveal(app.staticTexts["game.feedback"])
        XCTAssertTrue(app.staticTexts["game.feedback"].label.contains("로컬 기록"))
        XCTAssertFalse(app.staticTexts["game.position"].exists)
        capture("games-logged-out-local-result")
        app.terminate(); app.launch(); openChat(); enterQuestion("Hello")
        reveal(app.buttons["chat.send"]); app.buttons["chat.send"].tap()
        reveal(app.staticTexts["chat.status"]); waitForStatus("아이폰에서 로그인해 주세요")
        XCTAssertFalse(app.staticTexts["chat.answer"].exists)
        capture("games-logged-out-chat-guard")
    }

    private func openLibrary() {
        reveal(app.buttons["watch.openGames"], crown: true)
        app.buttons["watch.openGames"].tap()
        XCTAssertTrue(app.buttons["game.openShooting"].waitForExistence(timeout: 4))
    }
    private func openGame(_ id: String) { openLibrary(); reveal(app.buttons[id]); app.buttons[id].tap() }
    private func finishIfPlaying() {
        let finish = app.buttons["game.finish"].firstMatch
        if finish.exists { finish.tap(); let confirm = app.buttons["기록 남기고 마치기"]; XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.tap() }
        XCTAssertTrue(app.staticTexts["game.finalScore"].waitForExistence(timeout: 10))
    }
    private func assertSubmitted() {
        reveal(app.staticTexts["game.position"])
        XCTAssertTrue(app.staticTexts["game.position"].label.contains("위"))
        reveal(app.staticTexts["game.rankName.900000001"])
        XCTAssertTrue(app.staticTexts["game.rankScore.900000001"].exists)
    }
    private func openChat() { reveal(app.buttons["watch.openChat"], crown: true); app.buttons["watch.openChat"].tap() }
    private func enterQuestion(_ text: String) {
        let question = app.descendants(matching: .any).matching(identifier: "chat.question").firstMatch
        reveal(question); question.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let decline = system.buttons["지금 안 함"]
        if decline.exists {
            for _ in 0..<8 { if decline.isHittable { break }; system.swipeUp(velocity: .slow) }
            decline.tap()
        }
        // The 40mm simulator opens dictation automatically. Stop its microphone
        // session before XCTest injects text so a dictation failure cannot lock Done.
        let dictation = app.buttons["Stop dictation"]
        if dictation.waitForExistence(timeout: 1) { dictation.tap() }
        capture("games-chat-system-input")
        app.typeText(text)
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["완료", "Done"])).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in done.exists && done.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "System input must accept injected text before returning to the app")
        done.tap()
    }
    private func waitForStatus(_ text: String) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in self.app.staticTexts["chat.status"].exists && self.app.staticTexts["chat.status"].label == text }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 30), .completed)
    }
    private func reveal(_ element: XCUIElement, crown: Bool = false, down preferredDown: Bool = true) {
        for _ in 0..<24 {
            var down = preferredDown
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                if element.isHittable && screen.insetBy(dx: -1, dy: -1).contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            if crown { XCUIDevice.shared.rotateDigitalCrown(delta: down ? 0.6 : -0.6) }
            else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
        XCTFail("Missing game flow element: \(element)\n\(app.debugDescription)")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
