import XCTest

@MainActor
final class WatchMotionProfileUITests: XCTestCase {
    func test00HomeTouchDoesNotShowCount() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10))
        ready(pet); pet.tap(); ready(pet)
        XCTAssertFalse((pet.value as? String ?? "").contains("/50"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "쓰다듬기 [0-9]+/50.*")).firstMatch.exists)
        capture(app, "motion-home-without-count")
        app.terminate()
    }

    func test01BothMotionClips() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--pet-animation-preview"]; app.launch()
        XCTAssertTrue(app.staticTexts["달리기"].waitForExistence(timeout: 10))
        capture(app, "motion-running")
        XCTAssertTrue(app.staticTexts["인사"].waitForExistence(timeout: 8))
        capture(app, "motion-greeting")
        XCTAssertTrue(app.staticTexts["쉬기"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func test10NicknameShortcut() { shortcut(large: false) }
    func test11LargeNicknameShortcut() { shortcut(large: true) }

    private func shortcut(large: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        if large { app.launchArguments = ["--watch-ui-large-text"] }
        app.launch()
        XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10))
        let pages = ["watch.petTouch", "watch.managePetStatistics", "watch.openGames", "watch.openStreak", "watch.openChat"]
        for _ in 0..<12 {
            if app.buttons["watch.openNickname"].exists && app.buttons["watch.openNickname"].isHittable { break }
            let current = pages.firstIndex { app.buttons[$0].exists && app.buttons[$0].isHittable } ?? 0
            XCUIDevice.shared.rotateDigitalCrown(delta: current > 3 ? -0.5 : 0.5)
        }
        let nickname = app.buttons["watch.openNickname"], calendar = app.buttons["watch.openStreak"]
        for button in [nickname,calendar] {
            XCTAssertTrue(button.exists && button.isHittable)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame))
            XCTAssertGreaterThanOrEqual(button.frame.width,44); XCTAssertGreaterThanOrEqual(button.frame.height,44)
            print("PROFILE_TARGET \(button.identifier) \(button.frame)")
        }
        capture(app, large ? "profile-shortcut-large" : "profile-shortcut")
        nickname.tap()
        XCTAssertTrue(app.navigationBars["닉네임"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "nickname.input").firstMatch.exists)
        capture(app, large ? "profile-editor-large" : "profile-editor")
        app.terminate()
    }

    private func ready(_ pet: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in pet.exists && pet.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
