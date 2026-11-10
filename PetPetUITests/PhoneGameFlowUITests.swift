import XCTest

@MainActor
final class PhoneGameFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }
    func test00EnsureDevelopmentLogin() {
        app.buttons["phone.openAccount"].tap()
        let login = app.buttons["phone.developmentSignIn"]
        if login.waitForExistence(timeout: 2) { login.tap() }
        XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 10))
    }
    func test30Logout() {
        app.buttons["phone.openAccount"].tap()
        let button = app.buttons["phone.signOut"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(app.buttons["phone.developmentSignIn"].waitForExistence(timeout: 10))
    }
    func test21BothRankingsShowWatchRecords() {
        app.buttons["phone.openExtras"].tap()
        let score = app.staticTexts["phone.rankScore.900000001"]
        XCTAssertTrue(score.waitForExistence(timeout: 20)); XCTAssertTrue(score.label.contains("점"))
        app.descendants(matching: .any).matching(identifier: "phone.rankGame").firstMatch.tap()
        app.buttons["별계단 훈련"].tap()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in score.exists && score.label.contains("계단") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "games-phone-watch-rankings"; shot.lifetime = .keepAlways; add(shot)
    }

    func test41LargeDarkPhoneChatRepeatsAndCancels() {
        app.terminate(); app.launchArguments = ["--phone-ui-large-text", "--phone-ui-dark"]; app.launch()
        test40PhoneChatRepeatsAndCancels()
    }

    func test40PhoneChatRepeatsAndCancels() {
        app.buttons["phone.openExtras"].tap()
        app.buttons["phone.showChat"].tap()
        let question = app.buttons["chat.editQuestion"]
        reveal(question); question.tap()
        let editor = app.textViews["chat.question"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); app.typeText("Hello phone")
        app.buttons["chat.dismissKeyboard"].tap()
        for index in 0..<2 {
            reveal(app.buttons["chat.send"], down: index == 0); app.buttons["chat.send"].tap()
            waitForStatus("AI 응답 완료"); reveal(app.staticTexts["chat.status"], down: false)
            reveal(app.staticTexts["chat.answer"])
            XCTAssertTrue(app.staticTexts["chat.answer"].label.contains("Hello phone"))
        }
        reveal(question, down: false); question.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        app.typeText(Array(repeating: "cancel", count: 150).joined(separator: " "))
        app.buttons["chat.dismissKeyboard"].tap()
        XCTAssertLessThan(question.frame.height, app.windows.firstMatch.frame.height / 2, "A long question must leave space for the send button and reply")
        reveal(app.buttons["chat.send"]); app.buttons["chat.send"].tap()
        let cancel = app.buttons["chat.cancel"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            cancel.exists && cancel.isHittable && self.app.windows.firstMatch.frame.contains(cancel.frame)
                && cancel.frame.minY >= self.app.buttons["phone.showChat"].frame.maxY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, "The whole cancel button must appear without scrolling")
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        let waiting = XCTAttachment(screenshot: app.screenshot()); waiting.name = "games-phone-chat-cancelling"; waiting.lifetime = .keepAlways; add(waiting)
        cancel.tap()
        waitForStatus("응답을 중단했어요"); reveal(app.staticTexts["chat.status"], down: false)
        if question.exists { XCTAssertLessThan(question.frame.height, app.windows.firstMatch.frame.height / 2) }
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "games-phone-chat-layout"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let questionRow = app.cells.containing(.button, identifier: "chat.editQuestion").firstMatch
        if questionRow.exists { XCTAssertLessThan(questionRow.frame.height, app.windows.firstMatch.frame.height / 2, "The input preview row must stay bounded when streaming stops") }
        reveal(app.buttons["chat.send"], down: false)
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "games-phone-chat-cancelled"; shot.lifetime = .keepAlways; add(shot)
    }

    private func waitForStatus(_ text: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in self.app.staticTexts["chat.status"].exists && self.app.staticTexts["chat.status"].label == text }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true) {
        var down = preferredDown
        for _ in 0..<35 {
            let screen = app.windows.firstMatch.frame
            let top = app.buttons["phone.showChat"].exists ? app.buttons["phone.showChat"].frame.maxY + 8 : 64
            let visible = CGRect(x: screen.minX, y: top, width: screen.width, height: screen.maxY - top).insetBy(dx: -1, dy: -1)
            if element.exists {
                let frame = element.frame
                let longTextVisible = frame.height > visible.height && frame.intersection(visible).height > 100
                    && frame.minX >= visible.minX && frame.maxX <= visible.maxX
                if element.isHittable && (visible.contains(frame) || longTextVisible) { return }
                if !frame.isEmpty { down = frame.minY >= visible.minY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.76 : 0.52))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.52 : 0.76)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing phone game/chat element: \(element)\n\(app.debugDescription)")
    }
}
