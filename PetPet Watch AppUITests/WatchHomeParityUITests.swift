import XCTest

@MainActor
final class WatchHomeParityUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    override func tearDownWithError() throws { app.terminate() }

    func test00DayHome() { home(mode: "day") }
    func test01NightHome() { home(mode: "night") }
    func test02LargeDayHome() { home(mode: "day", large: true) }
    func test03LargeNightHome() { home(mode: "night", large: true) }

    private func home(mode: String, large: Bool = false) {
        app.launchArguments = ["--watch-ui-\(mode)"]
        if large { app.launchArguments.append("--watch-ui-large-text") }
        app.launch()
        let pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        target(pet)
        XCTAssertFalse(app.buttons["watch.previousPage"].exists)
        XCTAssertFalse(app.buttons["watch.openPetStatistics"].exists)
        XCTAssertGreaterThan(pet.frame.height, screen.height * 0.55, "The pet must dominate the home, not sit in a small dashboard tile")
        XCTAssertEqual(pet.frame.midX, screen.midX, accuracy: 2)
        XCTAssertFalse(app.buttons["watch.openFoodInventory"].exists)
        XCTAssertFalse(app.buttons["성장"].exists)
        XCTAssertFalse(app.buttons["먹이"].exists)
        let steps = app.staticTexts["watch.stepCount"]
        XCTAssertTrue(steps.exists); XCTAssertTrue(screen.contains(steps.frame))
        XCTAssertGreaterThan(steps.frame.midY, pet.frame.midY)
        capture("parity-\(mode)-\(large ? "large" : "normal")-home")
        app.swipeUp()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(pet.waitForExistence(timeout: 5))
        capture("navigation-\(mode)-\(large ? "large" : "normal")-returned-home")
    }

    func test10FivePagesAndCareDestinations() {
        app.launchArguments = ["--watch-ui-night"]; app.launch()
        XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10))
        openWatchPetCare(app)
        let food = app.buttons["watch.manageFoodInventory"], stats = app.buttons["watch.managePetStatistics"]
        XCTAssertTrue(food.waitForExistence(timeout: 5)); target(food); target(stats)
        capture("parity-status-page")
        food.tap()
        XCTAssertTrue(app.staticTexts["watch.foodQuantity.1"].waitForExistence(timeout: 5))
        reveal(app.buttons["watch.feedFood.1"]); target(app.buttons["watch.feedFood.1"])
        capture("parity-food-detail"); back()
        stats.tap(); XCTAssertTrue(app.staticTexts["watch.petLevel"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["watch.stat.health"])
        capture("parity-stat-detail"); back()

        crownTo(app.buttons["watch.openGames"]); target(app.buttons["watch.openGames"])
        capture("parity-games-page")
        app.buttons["watch.openGames"].tap()
        XCTAssertTrue(app.buttons["game.openShooting"].waitForExistence(timeout: 5))
        reveal(app.buttons["game.openStairs"]); target(app.buttons["game.openStairs"]); back()
        crownTo(app.buttons["watch.openStreak"]); target(app.buttons["watch.openStreak"])
        capture("parity-streak-page")
        app.buttons["watch.openStreak"].tap()
        reveal(app.buttons["watch.openAccount"]); target(app.buttons["watch.openAccount"])
        app.buttons["watch.openAccount"].tap()
        XCTAssertTrue(app.navigationBars["계정"].waitForExistence(timeout: 5))
        capture("parity-account-detail"); back(); back()
        crownTo(app.buttons["watch.openChat"]); target(app.buttons["watch.openChat"])
        capture("parity-voice-page")
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.6)
        XCTAssertTrue(app.buttons["watch.openChat"].isHittable, "There must be no extra food or account root pages after voice")
    }

    private func back() { app.navigationBars.buttons.firstMatch.tap() }
    private func crownTo(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.6)
        }
        XCTFail("Missing expected root page: \(element)")
    }
    private func reveal(_ element: XCUIElement) {
        var down = true
        for _ in 0..<30 {
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                if element.isHittable && screen.contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing detail: \(element)")
    }
    private func target(_ element: XCUIElement) {
        XCTAssertTrue(element.exists && element.isHittable)
        print("PARITY_TARGET \(element.identifier) \(element.frame)")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame))
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }
    private func capture(_ name: String) {
        let value = XCTAttachment(screenshot: app.screenshot()); value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
