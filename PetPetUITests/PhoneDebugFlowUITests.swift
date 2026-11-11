import XCTest

/// Ordered by Scripts/test_debug_flow.py on a fresh, paired Debug simulator.
@MainActor
final class PhoneDebugFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    func test01LoginAndEmptyRestore() {
        openAccount()
        // A retry after a connection-setup failure must still exercise the
        // visible logout -> login path without clearing simulator Keychain data.
        if app.buttons["phone.signOut"].exists {
            reveal(app.buttons["phone.signOut"]); app.buttons["phone.signOut"].tap()
        }
        XCTAssertTrue(app.buttons["phone.developmentSignIn"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["phone.serverBackup"].isEnabled)
        XCTAssertFalse(app.buttons["phone.previewServerRestore"].isEnabled)
        app.buttons["phone.developmentSignIn"].tap()
        XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 10))
        let restore = app.buttons["phone.previewServerRestore"]
        reveal(restore); restore.tap()
        let feedback = app.staticTexts["phone.cloudFeedback"]
        reveal(feedback)
        XCTAssertTrue(wait { feedback.label.contains("저장된 백업이 없어요") })
        XCTAssertFalse(app.buttons["phone.confirmServerRestore"].exists)
        capture("flow-empty-restore")
        home()
        assertHome(level: 1, experience: 0, milk: 3)
        capture("flow-login-and-first-sync")
    }

    func test03SyncedGrowthBackupTwiceAndCancelRestore() {
        assertHome(level: 2, experience: 0, milk: 1)
        openAccountFromScrolledHome()
        backup()
        home()
        assertHome(level: 2, experience: 0, milk: 5)
        XCTAssertEqual(app.staticTexts["phone.food.2"].label, "1개")
        openAccountFromScrolledHome()
        backup()
        capture("flow-repeat-backup-complete")
        home()
        assertHome(level: 2, experience: 0, milk: 5)
        openAccountFromScrolledHome()
        previewRestore()
        capture("flow-restore-before-cancel")
        app.buttons["취소"].tap()
        XCTAssertFalse(app.buttons["phone.confirmServerRestore"].exists)
        XCTAssertTrue(app.buttons["phone.serverBackup"].isEnabled)
    }

    func test05ReconnectRestoreOlderPetAndLogout() {
        assertHome(level: 2, experience: 1, milk: 4)
        reveal(app.staticTexts["phone.stat.attack"], down: false)
        XCTAssertEqual(app.staticTexts["phone.stat.attack"].label, "51")
        openAccountFromScrolledHome()
        previewRestore()
        let confirm = app.buttons["phone.confirmServerRestore"]
        reveal(confirm); confirm.tap()
        let feedback = app.staticTexts["phone.cloudFeedback"]
        reveal(feedback)
        XCTAssertTrue(wait(timeout: 45) { feedback.label == "워치에 기록을 복원했어요." }, feedback.label)
        capture("flow-restore-applied")
        home()
        assertHome(level: 2, experience: 0, milk: 4)
        reveal(app.staticTexts["phone.stat.attack"], down: false)
        XCTAssertEqual(app.staticTexts["phone.stat.attack"].label, "50")
        reveal(app.staticTexts["phone.stat.health"])
        XCTAssertEqual(app.staticTexts["phone.stat.health"].label, "9")
        reveal(app.staticTexts["스탯 포인트 0"])
        XCTAssertTrue(app.staticTexts["스탯 포인트 0"].exists)
        capture("flow-restored-pet-kept-inventory")
        openAccountFromScrolledHome()
        let logout = app.buttons["phone.signOut"]
        reveal(logout); logout.tap()
        XCTAssertTrue(app.buttons["phone.developmentSignIn"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["phone.serverBackup"].isEnabled)
        XCTAssertFalse(app.buttons["phone.previewServerRestore"].isEnabled)
        capture("flow-phone-logged-out")
    }

    func test07ReloginKeepsBackupAndLocalProgress() {
        assertHome(level: 2, experience: 1, milk: 3)
        openAccountFromScrolledHome()
        XCTAssertTrue(app.buttons["phone.developmentSignIn"].waitForExistence(timeout: 10))
        app.buttons["phone.developmentSignIn"].tap()
        XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 10))
        previewRestore()
        capture("flow-relogin-old-backup-still-available")
        app.buttons["취소"].tap()
        app.terminate(); app.launch()
        openAccount()
        XCTAssertTrue(app.buttons["phone.editNickname"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["phone.developmentSignIn"].exists)
        home()
        assertHome(level: 2, experience: 1, milk: 3)
        capture("flow-relogin-relaunch-preserved-progress")
    }

    private func assertHome(level: Int, experience: Int, milk: Int) {
        let steps = app.staticTexts["phone.stepCount"]
        reveal(steps, down: false)
        XCTAssertTrue(wait(timeout: 30) { steps.label.filter(\.isNumber) == "4321" }, steps.label)
        let pet = app.staticTexts["phone.petLevel"]
        reveal(pet)
        XCTAssertTrue(wait { pet.label == "Lv.\(level)" }, pet.label)
        reveal(app.staticTexts["phone.petExperience"])
        XCTAssertTrue(wait { self.app.staticTexts["phone.petExperience"].label == "경험치 \(experience) / \(level * 2)" })
        reveal(app.staticTexts["phone.petSource"], down: false)
        XCTAssertTrue(app.staticTexts["phone.petSource"].label.contains("워치 기록"))
        let food = app.staticTexts["phone.food.1"]
        reveal(food)
        XCTAssertTrue(wait { food.label == "\(milk)개" }, food.label)
    }
    private func openAccount() { app.buttons["phone.openAccount"].tap() }
    private func openAccountFromScrolledHome() {
        let button = app.buttons["phone.openAccount"]
        reveal(button, down: false)
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func home() {
        app.navigationBars["계정과 백업"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["phone.openAccount"].waitForExistence(timeout: 5))
    }
    private func backup() {
        let button = app.buttons["phone.serverBackup"]
        reveal(button); button.tap()
        let feedback = app.staticTexts["phone.cloudFeedback"]
        reveal(feedback)
        XCTAssertTrue(wait(timeout: 45) { feedback.label == "백업과 걸음수 보상을 완료했어요." }, feedback.label)
        XCTAssertTrue(button.isEnabled)
    }
    private func previewRestore() {
        let button = app.buttons["phone.previewServerRestore"]
        reveal(button); button.tap()
        XCTAssertTrue(app.navigationBars["복원 전 확인"].waitForExistence(timeout: 20))
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true) {
        var down = preferredDown
        for _ in 0..<30 {
            let screen = app.windows.firstMatch.frame
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : screen.minY + 20
            let visible = CGRect(x: screen.minX, y: top, width: screen.width, height: screen.maxY - top).insetBy(dx: -1, dy: -1)
            if element.exists {
                let frame = element.frame
                if element.isHittable && !frame.isEmpty && visible.contains(frame) { return }
                if !frame.isEmpty { down = frame.minY >= visible.minY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.76 : 0.52))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.52 : 0.76)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing flow control: \(element)")
    }
    private func wait(timeout: TimeInterval = 12, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
