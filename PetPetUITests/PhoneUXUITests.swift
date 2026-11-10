import XCTest

@MainActor
final class PhoneUXUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--phone-ui-light"]; app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    func test00HomeLight() { home(prefix: "light") }
    func test01HomeLargeLight() { launch(large: true); home(prefix: "large-light") }
    func test02HomeDark() { launch(dark: true); home(prefix: "dark") }
    func test03HomeLargeDark() { launch(large: true, dark: true); home(prefix: "large-dark") }
    func test10DetailsLight() { details(prefix: "light") }
    func test11DetailsLargeLight() { launch(large: true); details(prefix: "large-light") }
    func test12DetailsDark() { launch(dark: true); details(prefix: "dark") }
    func test20RankingsLight() { rankings(prefix: "light") }
    func test21RankingsLargeDark() { launch(large: true, dark: true); rankings(prefix: "large-dark") }

    func test30QuestionDraftLimitAndCancel() {
        launch(large: true)
        open("phone.openExtras"); app.buttons["phone.showChat"].tap()
        reveal(app.buttons["chat.editQuestion"]); app.buttons["chat.editQuestion"].tap()
        let editor = app.textViews["chat.question"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); checkTarget(editor)
        editor.tap()
        print("PHONE_UX_KEYBOARD \(app.keyboards.count)")
        editor.typeText(String(repeating: "a", count: 2001))
        let count = app.staticTexts["chat.characterCount"]
        XCTAssertTrue(count.label.contains("2,001")); checkText(count)
        XCTAssertGreaterThanOrEqual(count.frame.height, 25, "The question sheet must use the actual system accessibility text size")
        let done = app.buttons["chat.dismissKeyboard"]
        XCTAssertFalse(done.isEnabled); checkTarget(done, enabled: false)
        checkTarget(app.buttons["chat.cancelEditing"]); capture("phone-ux-question-limit")
        app.buttons["chat.cancelEditing"].tap()
        reveal(app.buttons["chat.send"]); XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        XCTAssertTrue(app.buttons["chat.editQuestion"].label.contains("질문을 입력해 주세요"))
    }

    func test50LargeLoginAndReconnect() {
        launch(large: true)
        open("phone.openAccount")
        let logout = app.buttons["phone.signOut"]
        reveal(logout); checkTarget(logout); logout.tap()
        let login = app.buttons["phone.developmentSignIn"]
        XCTAssertTrue(login.waitForExistence(timeout: 10)); reveal(login); checkTarget(login)
        capture("phone-ux-large-login")
        back(); open("phone.openExtras"); app.buttons["phone.showChat"].tap()
        let notice = app.staticTexts["phone.chatLoginNotice"]
        reveal(notice); checkText(notice)
        reveal(app.buttons["chat.editQuestion"], enabled: false); XCTAssertFalse(app.buttons["chat.editQuestion"].isEnabled)
        reveal(app.buttons["chat.send"], enabled: false); XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        capture("phone-ux-large-login-guidance")
        back(); open("phone.openAccount"); reveal(login)
        login.tap(); XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 15))
        back()
        let source = app.staticTexts["phone.petSource"]
        reveal(source); XCTAssertTrue(source.label.contains("워치 기록"))
        reveal(app.staticTexts["phone.petLevel"]); checkText(app.staticTexts["phone.petLevel"])
        capture("phone-ux-reconnected")
    }

    func test70LargeSoftwareKeyboardLayout() {
        launch(large: true, dark: true)
        open("phone.openAccount")
        let login = app.buttons["phone.developmentSignIn"]
        if login.exists {
            reveal(login); login.tap()
            XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 15))
        }
        back()
        open("phone.openExtras"); app.buttons["phone.showChat"].tap()
        reveal(app.buttons["chat.editQuestion"]); app.buttons["chat.editQuestion"].tap()
        let editor = app.textViews["chat.question"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let keyboard = app.keyboards.firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            keyboard.exists && keyboard.frame.height > 100
                && keyboard.frame.intersection(self.app.windows.firstMatch.frame).height > 100
        }, object: nil)
        let result = XCTWaiter.wait(for: [shown], timeout: 5)
        print("PHONE_UX_SOFTWARE_KEYBOARD \(keyboard.exists ? keyboard.frame : .zero)")
        capture("phone-ux-large-keyboard-focused")
        XCTAssertEqual(result, .completed, "Show the real software keyboard for the overlap check")
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            self.visibleRect(for: editor).contains(editor.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 3), .completed)
        checkTarget(editor); XCTAssertGreaterThanOrEqual(editor.frame.height, 100)
        checkText(app.staticTexts["chat.characterCount"])
        checkTarget(app.buttons["chat.cancelEditing"]); checkTarget(app.buttons["chat.dismissKeyboard"])
        editor.typeText("Hello keyboard")
        XCTAssertTrue((editor.value as? String)?.contains("Hello keyboard") == true)
        checkTarget(editor)
        capture("phone-ux-large-keyboard-input")
        app.buttons["chat.cancelEditing"].tap()
        XCTAssertFalse(editor.exists)
        back(); open("phone.openAccount")
        let logout = app.buttons["phone.signOut"]
        reveal(logout); logout.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 10), "Leave the dedicated unpaired simulator signed out")
    }

    /// Run on a separate, unpaired simulator with a fresh app container.
    func test60UnpairedLargeDark() {
        launch(large: true, dark: true)
        let status = app.staticTexts["phone.connectionStatus"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            status.exists && status.label.contains("Apple Watch를 연결")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        reveal(status); checkText(status)
        reveal(app.buttons["phone.openWatchSetup"]); checkTarget(app.buttons["phone.openWatchSetup"])
        capture("phone-ux-unpaired-large-home")
        open("phone.openWatchSetup")
        reveal(app.buttons["phone.checkWatchConnection"], enabled: false)
        checkTarget(app.buttons["phone.checkWatchConnection"], enabled: false)
        capture("phone-ux-unpaired-large-setup"); back()
        open("phone.openAccount")
        reveal(app.buttons["phone.developmentSignIn"]); checkTarget(app.buttons["phone.developmentSignIn"])
        reveal(app.buttons["phone.serverBackup"], enabled: false)
        checkTarget(app.buttons["phone.serverBackup"], enabled: false)
        XCTAssertFalse(app.buttons["phone.serverBackup"].isEnabled)
        reveal(app.buttons["phone.previewServerRestore"], enabled: false)
        checkTarget(app.buttons["phone.previewServerRestore"], enabled: false)
        XCTAssertFalse(app.buttons["phone.previewServerRestore"].isEnabled)
        capture("phone-ux-unpaired-large-account")
    }

    private func launch(large: Bool = false, dark: Bool = false) {
        app.terminate(); app.launchArguments = [dark ? "--phone-ui-dark" : "--phone-ui-light"]
        if large { app.launchArguments.append("--phone-ui-large-text") }
        app.launch()
    }
    private func home(prefix: String) {
        checkTarget(app.buttons["phone.openWatchSetup"])
        reveal(app.buttons["phone.refreshWatchData"], enabled: false); checkTarget(app.buttons["phone.refreshWatchData"], enabled: false)
        checkText(app.staticTexts["phone.connectionStatus"])
        reveal(app.staticTexts["phone.stepCount"]); checkText(app.staticTexts["phone.stepCount"])
        capture("phone-ux-\(prefix)-steps")
        for id in ["phone.openAccount", "phone.openExtras"] { reveal(app.buttons[id]); checkTarget(app.buttons[id]) }
        capture("phone-ux-\(prefix)-shortcuts")
        reveal(app.buttons["phone.greetPet"]); checkTarget(app.buttons["phone.greetPet"])
        for id in ["phone.petLevel", "phone.petExperience", "phone.stat.attack", "phone.stat.defense", "phone.stat.health"] {
            let text = app.staticTexts[id]; reveal(text); checkText(text)
        }
        capture("phone-ux-\(prefix)-pet")
        for id in ["phone.food.1", "phone.food.2", "phone.food.3"] {
            let text = app.staticTexts[id]; reveal(text); checkText(text)
        }
        capture("phone-ux-\(prefix)-food")
        reveal(app.staticTexts["phone.currentStreak"]); checkText(app.staticTexts["phone.currentStreak"])
        reveal(app.buttons["phone.refreshStreak"], enabled: false); checkTarget(app.buttons["phone.refreshStreak"], enabled: false)
        capture("phone-ux-\(prefix)-streak")
    }
    private func details(prefix: String) {
        open("phone.openWatchSetup")
        let connection = app.buttons["phone.checkWatchConnection"]
        reveal(connection, enabled: false); checkTarget(connection, enabled: false)
        capture("phone-ux-\(prefix)-setup"); back()
        open("phone.openAccount")
        reveal(app.staticTexts["phone.accountName"]); checkText(app.staticTexts["phone.accountName"])
        let nickname = app.buttons["phone.editNickname"]
        reveal(nickname); checkTarget(nickname); nickname.tap()
        let input = app.textFields["nickname.input"]
        reveal(input); checkTarget(input); input.tap(); input.typeText("UXDraft1717")
        let done = app.buttons["nickname.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3)); checkTarget(done); done.tap()
        let submit = app.buttons["nickname.submit"]
        reveal(submit, enabled: false); checkTarget(submit, enabled: false)
        capture("phone-ux-\(prefix)-nickname"); back()
        reveal(app.buttons["phone.serverBackup"], enabled: false); checkTarget(app.buttons["phone.serverBackup"], enabled: false)
        let restore = app.buttons["phone.previewServerRestore"]
        reveal(restore); checkTarget(restore); capture("phone-ux-\(prefix)-account"); restore.tap()
        XCTAssertTrue(app.navigationBars["복원 전 확인"].waitForExistence(timeout: 20))
        let confirm = app.buttons["phone.confirmServerRestore"]
        reveal(confirm); checkTarget(confirm)
        if prefix.contains("large") { XCTAssertGreaterThanOrEqual(confirm.frame.height, 90, "Restore sheets must receive the system accessibility text size") }
        capture("phone-ux-\(prefix)-restore")
        checkTarget(app.buttons["phone.cancelServerRestore"]); app.buttons["phone.cancelServerRestore"].tap()
        XCTAssertFalse(app.buttons["phone.confirmServerRestore"].exists)
    }
    private func rankings(prefix: String) {
        open("phone.openExtras")
        checkTarget(app.buttons["phone.showRankings"]); checkTarget(app.buttons["phone.showChat"])
        let picker = app.descendants(matching: .any).matching(identifier: "phone.rankGame").firstMatch
        reveal(picker); checkTarget(picker)
        let score = app.staticTexts["phone.rankScore.900000001"]
        reveal(score); XCTAssertTrue(score.label.contains("점")); checkText(score)
        capture("phone-ux-\(prefix)-shooting-ranking")
        reveal(picker, down: false); picker.tap(); app.buttons["별계단 훈련"].tap()
        reveal(score); XCTAssertTrue(score.label.contains("계단")); checkText(score)
        let name = app.staticTexts["phone.rankName.900000001"]
        reveal(name, down: false); checkText(name); capture("phone-ux-\(prefix)-stairs-ranking")
        reveal(app.buttons["phone.refreshRanking"]); checkTarget(app.buttons["phone.refreshRanking"])
        app.buttons["phone.refreshRanking"].tap()
        app.buttons["phone.showChat"].tap()
        reveal(app.buttons["chat.editQuestion"]); checkTarget(app.buttons["chat.editQuestion"])
        reveal(app.buttons["chat.send"], enabled: false); checkTarget(app.buttons["chat.send"], enabled: false)
        capture("phone-ux-\(prefix)-chat")
    }
    private func open(_ id: String) {
        let element = app.buttons[id]; reveal(element); element.tap()
    }
    private func back() { app.navigationBars.buttons.firstMatch.tap() }
    private func visibleRect(for element: XCUIElement) -> CGRect {
        let screen = app.windows.firstMatch.frame
        var top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : screen.minY + 20
        let pane = app.buttons["phone.showChat"]
        if pane.exists && pane.isHittable && !["phone.showChat", "phone.showRankings"].contains(element.identifier) {
            top = max(top, pane.frame.maxY + 8)
        }
        if app.navigationBars.buttons.allElementsBoundByIndex.contains(where: { $0.identifier == element.identifier && !$0.identifier.isEmpty }) { top = screen.minY + 20 }
        let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : screen.maxY
        return CGRect(x: screen.minX, y: top, width: screen.width, height: max(0, bottom - top)).insetBy(dx: -1, dy: -1)
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true, enabled: Bool = true) {
        for _ in 0..<30 {
            var down = preferredDown
            if element.exists {
                let frame = element.frame, visible = visibleRect(for: element)
                if (!enabled || element.isHittable) && !frame.isEmpty && visible.contains(frame) { return }
                if !frame.isEmpty { down = frame.minY >= visible.minY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.82 : 0.35))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.82)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing visible UI: \(element)\n\(app.debugDescription)")
    }
    private func checkTarget(_ element: XCUIElement, enabled: Bool = true) {
        XCTAssertTrue(element.exists)
        if enabled { XCTAssertTrue(element.isHittable) }
        print("PHONE_UX_TARGET \(element.identifier) \(element.frame)")
        XCTAssertTrue(visibleRect(for: element).contains(element.frame), "Clipped target \(element.identifier): \(element.frame)")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44); XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }
    private func checkText(_ element: XCUIElement) {
        XCTAssertTrue(element.exists)
        print("PHONE_UX_TEXT \(element.identifier) \(element.frame)")
        XCTAssertTrue(visibleRect(for: element).contains(element.frame), "Clipped text \(element.identifier): \(element.frame)")
    }
    private func capture(_ name: String) {
        let value = XCTAttachment(screenshot: app.screenshot()); value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
