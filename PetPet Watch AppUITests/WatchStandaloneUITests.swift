import XCTest

/// Run on a fresh, unpaired 40mm watch simulator. No companion app is installed.
@MainActor final class WatchStandaloneUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication(); app.launch()
        // Fresh unpaired simulators request Motion & Fitness permission.
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let allow = system.buttons.matching(NSPredicate(format: "label IN %@", ["허용", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) {
            for _ in 0..<4 { if allow.isHittable { break }; system.swipeUp(velocity: .slow) }
            allow.tap()
        }
    }
    override func tearDownWithError() throws { app.terminate() }

    func test10WatchLoginBackupRestoreWithoutCompanion() {
        openAccount()
        if app.buttons["watch.editPicture"].waitForExistence(timeout: 2) {
            let logout = app.buttons["watch.standaloneLogout"]; reveal(logout); logout.tap()
        }
        reveal(app.buttons["watch.standaloneLogin"]); app.buttons["watch.standaloneLogin"].tap()
        let mode = app.staticTexts["watch.connectionMode"]
        reveal(mode)
        XCTAssertTrue(mode.waitForExistence(timeout: 8)); XCTAssertEqual(mode.label, "아이폰 없이 사용 중")
        capture("standalone-40mm-login")
        for _ in 0..<2 {
            reveal(app.buttons["watch.serverBackup"]); XCTAssertTrue(app.buttons["watch.serverBackup"].isEnabled)
            app.buttons["watch.serverBackup"].tap()
            let feedback = app.staticTexts["watch.cloudFeedback"]
            reveal(feedback)
            XCTAssertTrue(wait { feedback.label == "워치 단독 백업과 걸음수 보상을 완료했어요." })
        }
        capture("standalone-40mm-backup")
        reveal(app.buttons["watch.standaloneRestore"], down: false); app.buttons["watch.standaloneRestore"].tap()
        let confirm = app.buttons["watch.confirmStandaloneRestore"]
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); capture("standalone-40mm-restore-preview"); confirm.tap()
        let feedback = app.staticTexts["watch.cloudFeedback"]
        reveal(feedback); XCTAssertTrue(wait { feedback.label == "워치에서 백업 기록을 복원했어요." })
        capture("standalone-40mm-restored")
        app.terminate(); app.launch(); openAccount()
        reveal(mode); XCTAssertEqual(mode.label, "아이폰 없이 사용 중")
        XCTAssertFalse(app.buttons["watch.standaloneLogin"].exists)
    }

    func test20WatchNicknameWithoutCompanion() {
        openAccount(); reveal(app.buttons["watch.editNickname"]); app.buttons["watch.editNickname"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "nickname.input").firstMatch
        reveal(input); input.tap()
        dismissOptionalDictationSharingIfRequested(timeout: 3)
        let stop = app.buttons["Stop dictation"]; if stop.waitForExistence(timeout: 1) { stop.tap() }
        let method = app.buttons["Change input method"]
        if method.waitForExistence(timeout: 3) {
            method.tap()
            let scribble = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Scribble", "손글씨 입력"])).firstMatch
            XCTAssertTrue(scribble.waitForExistence(timeout: 3)); scribble.tap()
        }
        let name = "SoloWatch" + String(Int(Date().timeIntervalSince1970) % 100000)
        app.typeText(name)
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["완료", "Done"])).firstMatch
        XCTAssertTrue(wait { done.exists && done.isEnabled }); done.tap()
        let submit = app.buttons["nickname.submit"]; reveal(submit)
        XCTAssertTrue(wait { submit.exists && submit.isEnabled }); submit.tap()
        let feedback = app.staticTexts["nickname.feedback"]; reveal(feedback)
        XCTAssertTrue(wait { feedback.label == "닉네임을 바꿨어요." }); capture("standalone-40mm-nickname")
        app.terminate(); app.launch(); reveal(app.buttons["watch.openStreak"], crown: true)
        XCTAssertEqual(app.buttons["watch.openNickname"].value as? String, name)
    }

    func test30RankingAndAIWithoutCompanion() {
        openLibrary()
        let ranking = app.buttons["game.openRanking.shooting"]; reveal(ranking); ranking.tap()
        let rank = app.staticTexts["game.rankName.900000101"]
        reveal(rank); XCTAssertTrue(rank.exists); capture("standalone-40mm-ranking")
        app.terminate(); app.launch()
        openChat(); enterQuestion("SoloWalk")
        reveal(app.buttons["chat.send"]); XCTAssertTrue(app.buttons["chat.send"].isEnabled); app.buttons["chat.send"].tap()
        reveal(app.staticTexts["chat.status"]); waitForStatus("AI 응답 완료")
        reveal(app.staticTexts["chat.answer"]); XCTAssertTrue(app.staticTexts["chat.answer"].label.contains("SoloWalk"))
        capture("standalone-40mm-ai-response")
        let full = app.buttons["chat.openFullAnswer"]; reveal(full); full.tap()
        app.swipeUp(velocity: .slow)
        let lastLine = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "chat.fullAnswer.", "않았어요.")).firstMatch
        XCTAssertTrue(lastLine.waitForExistence(timeout: 4))
        XCTAssertTrue(lastLine.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(lastLine.frame))
        capture("standalone-40mm-ai-full-answer")
    }

    private func openAccount() {
        reveal(app.buttons["watch.openStreak"], crown: true); app.buttons["watch.openStreak"].tap()
        let account = app.buttons["watch.openAccount"]; reveal(account); account.tap()
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in condition() }, object: nil)], timeout: 12) == .completed
    }
    private func openLibrary() {
        reveal(app.buttons["watch.openGames"], crown: true)
        app.buttons["watch.openGames"].tap()
        XCTAssertTrue(app.buttons["game.openShooting"].waitForExistence(timeout: 4))
    }
    private func openGame(_ id: String) { openLibrary(); reveal(app.buttons[id]); app.buttons[id].tap() }
    private func openChat() { reveal(app.buttons["watch.openChat"], crown: true); app.buttons["watch.openChat"].tap() }
    private func enterQuestion(_ text: String) {
        let question = app.descendants(matching: .any).matching(identifier: "chat.question").firstMatch
        reveal(question); question.tap()
        dismissOptionalDictationSharingIfRequested(timeout: 4)
        // The 40mm simulator opens dictation automatically. Stop its microphone
        // session before XCTest injects text so a dictation failure cannot lock Done.
        let dictation = app.buttons["Stop dictation"]
        if dictation.waitForExistence(timeout: 1) { dictation.tap() }
        let method = app.buttons["Change input method"]
        if method.waitForExistence(timeout: 3) {
            method.tap()
            let scribble = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Scribble", "손글씨 입력"])).firstMatch
            guard scribble.waitForExistence(timeout: 3) else { XCTFail("System input methods:\n\(app.debugDescription)"); return }
            scribble.tap()
        }
        capture("games-chat-system-input")
        print("STANDALONE_TEXT_INPUT_BEFORE=\(app.debugDescription)")
        app.typeText(text)
        print("STANDALONE_TEXT_INPUT_AFTER=\(app.debugDescription)")
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["완료", "Done"])).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in done.exists && done.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed, "System input must accept injected text before returning to the app")
        done.tap()
        let host = app.descendants(matching: .any).matching(identifier: "TextInputHost").firstMatch
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !host.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, "System text editor must close before querying app controls")
    }
    private func dismissOptionalDictationSharingIfRequested(timeout: TimeInterval) {
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let title = system.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND (label CONTAINS %@ OR label CONTAINS[c] %@)",
            "Siri", "받아쓰기", "dictation")).firstMatch
        guard title.waitForExistence(timeout: timeout) else { return }
        let decline = system.buttons.matching(NSPredicate(format: "label IN %@", ["지금 안 함", "Not Now"])).firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        for _ in 0..<8 { if decline.isHittable { break }; system.swipeUp(velocity: .slow) }
        XCTAssertTrue(decline.isHittable)
        decline.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !title.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        print("WATCH_OPTIONAL_DICTATION_SHARING_DECLINED")
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
