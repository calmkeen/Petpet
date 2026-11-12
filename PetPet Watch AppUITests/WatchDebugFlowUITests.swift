import XCTest

/// Uses actual buttons and persistence; step fixtures belong to the simulator driver.
@MainActor
final class WatchDebugFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launch()
        allowSimulatorMotionIfRequested()
    }
    override func tearDownWithError() throws { app.terminate() }

    private func allowSimulatorMotionIfRequested() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let prompt = system.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND (label CONTAINS %@ OR label CONTAINS[c] %@)", "PetPet Debug", "피트니스", "fitness")).firstMatch
        guard prompt.waitForExistence(timeout: 2) else { return }
        let allow = system.buttons.matching(NSPredicate(format: "label IN %@", ["허용", "Allow"])).firstMatch
        for _ in 0..<6 { if allow.isHittable { break }; system.swipeUp() }
        XCTAssertTrue(allow.isHittable)
        allow.tap()
        app.activate()
    }

    func test00NewWatchCanPlayWithoutLogin() {
        openFood()
        XCTAssertEqual(app.staticTexts["watch.foodQuantity.1"].label, "우유 3개")
        reveal(app.buttons["watch.claimStepRewards"])
        XCTAssertFalse(app.buttons["watch.claimStepRewards"].isEnabled)
        capture("flow-watch-first-food-logged-out")
    }
    func test02FeedGrowAndAllocate() {
        openFood()
        feedMilk(from: 3); feedMilk(from: 2)
        capture("flow-watch-two-feeds")
        openStatistics()
        XCTAssertEqual(app.staticTexts["watch.petLevel"].label, "Lv.2")
        reveal(app.staticTexts["watch.statPoints"])
        XCTAssertEqual(app.staticTexts["watch.statPoints"].label, "스탯 포인트 2")
        let health = app.buttons["watch.allocate.health"]
        reveal(health); health.tap()
        XCTAssertTrue(wait { self.app.staticTexts["watch.stat.health"].label == "9" })
        capture("flow-watch-level-up-and-health")
        reveal(app.staticTexts["watch.statPoints"], down: false)
        XCTAssertEqual(app.staticTexts["watch.statPoints"].label, "스탯 포인트 1")
        app.terminate(); app.launch()
        openStatistics()
        XCTAssertEqual(app.staticTexts["watch.petLevel"].label, "Lv.2")
        reveal(app.staticTexts["watch.stat.health"])
        XCTAssertEqual(app.staticTexts["watch.stat.health"].label, "9")
    }
    func test04SpendAfterBackup() {
        openFood()
        feedMilk(from: 5)
        openStatistics()
        let attack = app.buttons["watch.allocate.attack"]
        reveal(attack); attack.tap()
        XCTAssertTrue(wait { self.app.staticTexts["watch.stat.attack"].label == "51" })
        reveal(app.staticTexts["watch.statPoints"], down: false)
        XCTAssertEqual(app.staticTexts["watch.statPoints"].label, "스탯 포인트 0")
        capture("flow-watch-changed-after-backup")
    }
    func test06LoggedOutWatchKeepsLocalPlay() {
        for _ in 0..<8 {
            if app.buttons["watch.openNickname"].isHittable { break }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.45)
        }
        XCTAssertTrue(app.buttons["watch.openNickname"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["watch.openNickname"].value as? String, "아이폰에서 로그인해 주세요")
        openFood()
        feedMilk(from: 4)
        reveal(app.buttons["watch.claimStepRewards"])
        XCTAssertFalse(app.buttons["watch.claimStepRewards"].isEnabled)
        capture("flow-watch-local-play-after-logout")
    }

    func test08WatchRequestsBackupAfterRelogin() {
        openFood()
        XCTAssertEqual(app.staticTexts["watch.foodQuantity.1"].label, "우유 3개")
        let backup = app.buttons["watch.claimStepRewards"]
        reveal(backup)
        XCTAssertTrue(backup.isEnabled)
        backup.tap()
        let feedback = app.staticTexts["watch.cloudFeedback"]
        reveal(feedback)
        XCTAssertTrue(wait(timeout: 45) { feedback.label == "서버 백업과 걸음수 보상을 완료했어요." }, feedback.label)
        XCTAssertTrue(backup.isEnabled)
        capture("flow-watch-initiated-backup")
        app.terminate(); app.launch()
        openFood()
        XCTAssertEqual(app.staticTexts["watch.foodQuantity.1"].label, "우유 3개")
    }

    private func openFood() {
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["watch.openPetStatistics"].waitForExistence(timeout: 10))
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.manageFoodInventory"].waitForExistence(timeout: 5))
        app.buttons["watch.manageFoodInventory"].tap()
        XCTAssertTrue(app.staticTexts["watch.foodQuantity.1"].waitForExistence(timeout: 5))
    }
    private func openStatistics() {
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["watch.openPetStatistics"].waitForExistence(timeout: 10))
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 5))
        app.buttons["watch.managePetStatistics"].tap()
        XCTAssertTrue(app.staticTexts["watch.petLevel"].waitForExistence(timeout: 5))
    }
    private func feedMilk(from quantity: Int) {
        XCTAssertEqual(app.staticTexts["watch.foodQuantity.1"].label, "우유 \(quantity)개")
        let feed = app.buttons["watch.feedFood.1"]
        reveal(feed); feed.tap()
        XCTAssertTrue(wait { self.app.staticTexts["watch.foodQuantity.1"].label == "우유 \(quantity - 1)개" })
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true) {
        var down = preferredDown
        for _ in 0..<24 {
            if element.exists {
                let frame = element.frame
                let screen = app.windows.firstMatch.frame
                if element.isHittable && screen.insetBy(dx: -1, dy: -1).contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing watch flow control: \(element)")
    }
    private func wait(timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
