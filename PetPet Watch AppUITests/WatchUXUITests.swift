import XCTest

@MainActor
final class WatchUXUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }

    func test00OverviewPages() { checkOverviewPages(prefix: "normal") }
    func test01LargeTextOverviewPages() {
        app.terminate(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        checkOverviewPages(prefix: "large")
    }
    func test10DetailControls() { checkDetails(prefix: "normal") }
    func test11LargeTextDetailControls() {
        app.terminate(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        checkDetails(prefix: "large")
    }

    private func checkOverviewPages(prefix: String) {
        continueAfterFailure = true
        XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in self.app.buttons["watch.petTouch"].isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let pages: [(String, XCUIElement)] = [
            ("home", app.buttons["watch.openPetStatistics"]),
            ("growth", app.buttons["watch.managePetStatistics"]),
            ("food", app.buttons["watch.manageFoodInventory"]),
            ("streak", app.buttons["watch.openStreak"]),
            ("games", app.buttons["watch.openGames"]),
            ("chat", app.buttons["watch.openChat"]),
            ("account", app.buttons["백업 관리"]),
        ]
        for (name, action) in pages {
            crownTo(action)
            capture("ux-\(prefix)-\(name)")
            checkTarget(action, minimum: 44, top: 30)
            if name == "home" {
                checkTarget(app.buttons["watch.openFoodInventory"], minimum: 44, top: 30)
                let retry = app.buttons["watch.retrySteps"]
                if retry.exists {
                    checkTarget(retry, minimum: 44, top: 30)
                    retry.tap()
                    XCTAssertTrue(app.buttons["다시 시도"].waitForExistence(timeout: 3))
                    capture("ux-\(prefix)-step-guidance")
                    app.buttons["닫기"].tap()
                }
            }
        }
    }
    private func checkDetails(prefix: String) {
        XCTAssertTrue(app.buttons["watch.openPetStatistics"].waitForExistence(timeout: 10))
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 3))
        app.buttons["watch.managePetStatistics"].tap()
        for key in ["attack", "defense", "health"] {
            let button = app.buttons["watch.allocate.\(key)"]
            reveal(button, enabled: false); checkTarget(button, minimum: 44, enabled: false)
        }
        capture("ux-\(prefix)-statistics")
        app.terminate(); app.launch()
        app.buttons["watch.openFoodInventory"].tap(); app.buttons["watch.manageFoodInventory"].tap()
        reveal(app.buttons["watch.feedFood.1"]); checkTarget(app.buttons["watch.feedFood.1"], minimum: 44)
        capture("ux-\(prefix)-food-detail")
        reveal(app.buttons["watch.claimStepRewards"], enabled: false)
        checkTarget(app.buttons["watch.claimStepRewards"], minimum: 44, enabled: false)
        capture("ux-\(prefix)-rewards")
        app.terminate(); app.launch()
        crownTo(app.buttons["watch.openStreak"]); app.buttons["watch.openStreak"].tap()
        let month = app.buttons["watch.chooseMonth"]
        reveal(month); checkTarget(month, minimum: 44)
        XCTAssertGreaterThanOrEqual(month.frame.width, 100, "The year/month needs a full readable heading on 40mm")
        checkTarget(app.buttons["watch.previousMonth"], minimum: 44)
        checkTarget(app.buttons["watch.nextMonth"], minimum: 44)
        capture("ux-\(prefix)-calendar")
        app.terminate(); app.launch()
        crownTo(app.buttons["백업 관리"]); app.buttons["백업 관리"].tap()
        reveal(app.buttons["watch.editNickname"]); checkTarget(app.buttons["watch.editNickname"], minimum: 44)
        app.buttons["watch.editNickname"].tap()
        reveal(app.buttons["nickname.submit"], enabled: false)
        checkTarget(app.buttons["nickname.submit"], minimum: 44, enabled: false)
        capture("ux-\(prefix)-nickname")
    }
    private func crownTo(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.6)
        }
        XCTFail("Missing page: \(element)")
    }
    private func reveal(_ element: XCUIElement, enabled: Bool = true) {
        for _ in 0..<24 {
            var down = true
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                if (!enabled || element.isHittable) && screen.insetBy(dx: -1, dy: -1).contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing detail: \(element)\n\(app.debugDescription)")
    }
    private func checkTarget(_ element: XCUIElement, minimum: CGFloat, top: CGFloat = 0, enabled: Bool = true) {
        XCTAssertTrue(element.exists)
        if enabled { XCTAssertTrue(element.isHittable) }
        let frame = element.frame, screen = app.windows.firstMatch.frame
        print("UX_TARGET \(element.identifier) \(frame)")
        XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(frame), "Clipped target: \(element.identifier) \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, top)
        XCTAssertGreaterThanOrEqual(frame.width, minimum)
        XCTAssertGreaterThanOrEqual(frame.height, minimum)
    }
    private func capture(_ name: String) {
        let value = XCTAttachment(screenshot: app.screenshot()); value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
