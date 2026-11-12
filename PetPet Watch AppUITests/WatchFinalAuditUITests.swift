import XCTest

@MainActor
final class WatchFinalAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }

    func test10FeedPersistsAndRepeatedWatchBackupCompletes() {
        openFood()
        let count = Int(app.staticTexts["watch.foodQuantity.1"].label.filter(\.isNumber)) ?? 0
        XCTAssertGreaterThan(count, 1, "Use a dedicated simulator with at least two milk portions")
        reveal(app.buttons["watch.feedFood.1"]); app.buttons["watch.feedFood.1"].tap()
        XCTAssertTrue(wait { self.app.staticTexts["watch.foodQuantity.1"].label == "우유 \(count - 1)개" })
        capture("final-watch-fed-milk")
        app.terminate(); app.launch(); openFood()
        XCTAssertEqual(app.staticTexts["watch.foodQuantity.1"].label, "우유 \(count - 1)개")
        for _ in 0..<2 {
            let backup = app.buttons["watch.claimStepRewards"]
            reveal(backup); XCTAssertTrue(backup.isEnabled); backup.tap()
            let feedback = app.staticTexts["watch.cloudFeedback"]
            reveal(feedback)
            XCTAssertTrue(wait(timeout: 45) { feedback.exists && feedback.label == "서버 백업과 걸음수 보상을 완료했어요." })
            XCTAssertTrue(backup.isEnabled)
        }
        capture("final-watch-repeated-backup")
        app.terminate(); app.launch()
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 5))
        app.buttons["watch.managePetStatistics"].tap()
        reveal(app.staticTexts["watch.stat.health"])
        XCTAssertTrue(app.staticTexts["watch.stat.health"].exists)
        capture("final-watch-growth-after-relaunch")
    }

    func test20WatchNicknameChangeSurvivesRelaunch() {
        crownTo("watch.openStreak"); app.buttons["watch.openNickname"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "nickname.input").firstMatch
        reveal(input); input.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if system.buttons["지금 안 함"].exists {
            for _ in 0..<8 { if system.buttons["지금 안 함"].isHittable { break }; system.swipeUp(velocity: .slow) }
            system.buttons["지금 안 함"].tap()
        }
        let stop = app.buttons["Stop dictation"]
        if stop.waitForExistence(timeout: 1) { stop.tap() }
        let method = app.buttons["Change input method"]
        if method.exists {
            method.tap()
            let scribble = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Scribble", "손글씨 입력"])).firstMatch
            guard scribble.waitForExistence(timeout: 3) else { XCTFail("System input methods:\n\(app.debugDescription)"); return }
            scribble.tap()
        }
        let name = "FinalWatch" + String(Int(Date().timeIntervalSince1970) % 1_000_000)
        app.typeText(name)
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["완료", "Done"])).firstMatch
        XCTAssertTrue(wait { done.exists && done.isEnabled }); done.tap()
        let submit = app.buttons["nickname.submit"]
        reveal(submit); XCTAssertTrue(wait(timeout: 15) { submit.exists && submit.isEnabled }); submit.tap()
        let feedback = app.staticTexts["nickname.feedback"]
        reveal(feedback); XCTAssertTrue(wait(timeout: 15) { feedback.exists && feedback.label == "닉네임을 바꿨어요." })
        print("FINAL_AUDIT_NICKNAME=\(name)")
        capture("final-watch-nickname-updated")
        app.terminate(); app.launch()
        let account = app.buttons["watch.openNickname"]
        crownTo("watch.openStreak"); XCTAssertEqual(account.value as? String, name)
        capture("final-watch-nickname-after-relaunch")
    }

    private func openFood() {
        XCTAssertTrue(app.buttons["watch.openPetStatistics"].waitForExistence(timeout: 10))
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.manageFoodInventory"].waitForExistence(timeout: 5))
        app.buttons["watch.manageFoodInventory"].tap()
        XCTAssertTrue(app.staticTexts["watch.foodQuantity.1"].waitForExistence(timeout: 5))
    }
    private func crownTo(_ id: String) {
        let element = app.buttons[id]
        let pages = ["watch.openPetStatistics", "watch.managePetStatistics", "watch.openGames", "watch.openStreak", "watch.openChat"]
        let destination = pages.firstIndex(of: id)
        var previous: Int?
        var stalled = 0
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            let current = pages.firstIndex { app.buttons[$0].exists && app.buttons[$0].isHittable }
            stalled = current == previous ? stalled + 1 : 0
            previous = current
            let down = destination == nil || current == nil || destination! > current!
            let magnitude = [0.25, 0.4, 0.5, 0.6][min(stalled, 3)]
            XCUIDevice.shared.rotateDigitalCrown(delta: down ? magnitude : -magnitude)
        }
        XCTFail("Missing root page: \(element)")
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<24 {
            var down = true
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                if element.isHittable && screen.insetBy(dx: -1, dy: -1).contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing final audit control: \(element)\n\(app.debugDescription)")
    }
    private func wait(timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
