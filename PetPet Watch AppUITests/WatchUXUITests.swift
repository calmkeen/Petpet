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
        let pages: [(String, String)] = [
            ("home", "watch.petTouch"),
            ("status", "watch.managePetStatistics"),
            ("games", "watch.openGames"),
            ("streak", "watch.openStreak"),
            ("chat", "watch.openChat"),
        ]
        for (name, id) in pages {
            let action = app.buttons[id]
            crownTo(id)
            capture("ux-\(prefix)-\(name)")
            checkTarget(action, minimum: 44, top: 30)
            if name == "home" {
                checkTarget(app.buttons["watch.petTouch"], minimum: 44, top: 30)
                XCTAssertFalse(app.buttons["watch.previousPage"].exists)
                XCTAssertFalse(app.buttons["watch.openPetStatistics"].exists)
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
        openWatchPetCare(app)
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 3))
        app.buttons["watch.managePetStatistics"].tap()
        for key in ["attack", "defense", "health"] {
            let button = app.buttons["watch.allocate.\(key)"]
            reveal(button, enabled: false); checkTarget(button, minimum: 44, enabled: false)
        }
        capture("ux-\(prefix)-statistics")
        app.terminate(); app.launch()
        openWatchPetCare(app); app.buttons["watch.manageFoodInventory"].tap()
        reveal(app.buttons["watch.feedFood.1"]); checkTarget(app.buttons["watch.feedFood.1"], minimum: 44)
        capture("ux-\(prefix)-food-detail")
        reveal(app.buttons["watch.claimStepRewards"], enabled: false)
        checkTarget(app.buttons["watch.claimStepRewards"], minimum: 44, enabled: false)
        capture("ux-\(prefix)-rewards")
        app.terminate(); app.launch()
        crownTo("watch.openStreak"); app.buttons["watch.openStreak"].tap()
        let month = app.buttons["watch.chooseMonth"]
        reveal(month); checkTarget(month, minimum: 44)
        XCTAssertGreaterThanOrEqual(month.frame.width, 100, "The year/month needs a full readable heading on 40mm")
        checkTarget(app.buttons["watch.previousMonth"], minimum: 44)
        checkTarget(app.buttons["watch.nextMonth"], minimum: 44)
        capture("ux-\(prefix)-calendar")
        app.terminate(); app.launch()
        crownTo("watch.openStreak"); app.buttons["watch.openStreak"].tap()
        reveal(app.buttons["watch.openAccount"]); app.buttons["watch.openAccount"].tap()
        reveal(app.buttons["watch.editNickname"]); checkTarget(app.buttons["watch.editNickname"], minimum: 44)
        app.buttons["watch.editNickname"].tap()
        reveal(app.buttons["nickname.submit"], enabled: false)
        checkTarget(app.buttons["nickname.submit"], minimum: 44, enabled: false)
        capture("ux-\(prefix)-nickname")
    }
    private func crownTo(_ id: String) {
        let element = app.buttons[id]
        let pages = ["watch.petTouch", "watch.managePetStatistics", "watch.openGames", "watch.openStreak", "watch.openChat"]
        let destination = pages.firstIndex(of: id)
        var previous: Int?
        var stalled = 0
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            let current = pages.firstIndex { id in
                let button = app.buttons[id]
                return button.exists && button.isHittable
            }
            stalled = current == previous ? stalled + 1 : 0
            previous = current
            let down = destination == nil || current == nil || destination! > current!
            let magnitude = [0.25, 0.4, 0.5, 0.6][min(stalled, 3)]
            print("UX_CROWN target=\(id) current=\(current.map(String.init) ?? "unknown") rotation=\(down ? magnitude : -magnitude)")
            XCUIDevice.shared.rotateDigitalCrown(delta: down ? magnitude : -magnitude)
        }
        XCTFail("Missing page: \(element)")
    }
    private func reveal(_ element: XCUIElement, enabled: Bool = true) {
        for _ in 0..<24 {
            var down = true
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                // watchOS scales list rows near the curved edge. Move the
                // action into the list's interior before measuring its size.
                if (!enabled || element.isHittable) && frame.width >= 44 && frame.height >= 44 && screen.insetBy(dx: -1, dy: -1).contains(frame) { return }
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
