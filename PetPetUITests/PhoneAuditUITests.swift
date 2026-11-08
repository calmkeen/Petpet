import XCTest

@MainActor
final class PhoneAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    func testConnectionGuideAndExtrasReturnHome() {
        app.buttons["phone.openWatchSetup"].tap()
        XCTAssertTrue(app.staticTexts["phone.watchSetupStatus"].waitForExistence(timeout: 5))
        capture("phone-watch-setup")
        backToHome()
        signIn()
        app.buttons["phone.openExtras"].tap()
        let question = revealQuestionInput()
        question.tap()
        question.typeText("How is my pet?")
        let done = app.buttons["chat.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        reveal(app.buttons["chat.send"])
        app.buttons["chat.send"].tap()
        let answer = app.staticTexts["chat.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 5))
        capture("phone-mock-ai")
        backToHome()
        XCTAssertTrue(app.buttons["phone.openExtras"].isHittable)
    }

    func testNicknameValidationPersistsAcrossRelaunch() {
        signIn()
        app.buttons["phone.openAccount"].tap()
        app.buttons["phone.editNickname"].tap()
        let input = app.textFields["nickname.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("a")
        XCTAssertFalse(app.buttons["nickname.submit"].isEnabled)
        input.typeText(XCUIKeyboardKey.delete.rawValue)
        let nickname = "Phone" + String(Int(Date().timeIntervalSince1970) % 1_000_000)
        input.typeText(nickname)
        let submit = app.buttons["nickname.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { submit.isEnabled })
        submit.tap()
        XCTAssertTrue(wait { self.app.staticTexts["nickname.current"].label == nickname })
        print("PHONE_AUDIT_NICKNAME=\(nickname)")
        capture("phone-nickname-saved")
        app.terminate(); app.launch()
        app.buttons["phone.openAccount"].tap()
        app.buttons["phone.editNickname"].tap()
        XCTAssertTrue(wait { self.app.staticTexts["nickname.current"].label == nickname })
        capture("phone-nickname-after-relaunch")
    }

    /// Run on a paired simulator with the watch application open.
    func testPairedWatchBackupAndRestoreRoundTrip() {
        signIn()
        app.buttons["phone.openAccount"].tap()
        app.buttons["phone.serverBackup"].tap()
        let feedback = app.staticTexts["phone.cloudFeedback"]
        XCTAssertTrue(wait(timeout: 45) { feedback.exists && feedback.label == "백업과 걸음수 보상을 완료했어요." }, feedback.exists ? feedback.label : "No backup feedback")
        capture("phone-watch-backup-complete")
        let restore = app.buttons["phone.previewServerRestore"]
        reveal(restore); restore.tap()
        XCTAssertTrue(app.navigationBars["복원 전 확인"].waitForExistence(timeout: 20))
        capture("phone-restore-preview")
        app.buttons["취소"].tap()
        XCTAssertFalse(app.buttons["phone.confirmServerRestore"].exists)
        restore.tap()
        let confirm = app.buttons["phone.confirmServerRestore"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        reveal(confirm); confirm.tap()
        XCTAssertTrue(wait(timeout: 45) { feedback.exists && feedback.label == "워치에 기록을 복원했어요." }, feedback.exists ? feedback.label : "No restore feedback")
        capture("phone-watch-restore-complete")
        backToHome()
        reveal(app.staticTexts["phone.petLevel"])
        XCTAssertTrue(app.staticTexts["phone.petSource"].label.contains("워치 기록"))
        XCTAssertTrue(app.staticTexts["phone.food.1"].exists)
        capture("phone-synced-watch-pet")
    }

    /// Run on an unpaired simulator containing only a mock server backup.
    func testServerPetWithoutWatch() {
        signIn()
        reveal(app.staticTexts["phone.petSource"])
        XCTAssertTrue(wait { self.app.staticTexts["phone.petSource"].label.contains("서버 백업 기록") })
        XCTAssertTrue(app.staticTexts["phone.petLevel"].exists)
        XCTAssertFalse(app.staticTexts["phone.food.1"].exists)
        capture("phone-server-pet-without-watch")
    }

    private func signIn() {
        app.buttons["phone.openAccount"].tap()
        let login = app.buttons["phone.developmentSignIn"]
        if login.waitForExistence(timeout: 2) {
            login.tap()
            XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 10))
        }
        backToHome()
    }
    private func backToHome() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["phone.openAccount"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Missing control: \(element)")
    }
    private func revealQuestionInput() -> XCUIElement {
        // SwiftUI's vertical TextField is exposed as TextView on iOS 18 and
        // TextField on newer runtimes. Follow the actual accessible input.
        for _ in 0..<10 {
            for input in [app.textFields["chat.question"], app.textViews["chat.question"]] {
                if input.exists && input.isHittable { return input }
            }
            app.swipeUp()
        }
        XCTFail("The AI question input is unavailable")
        return app.textFields["chat.question"]
    }
    private func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
