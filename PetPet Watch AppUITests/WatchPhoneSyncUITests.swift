import XCTest

@MainActor
final class WatchPhoneSyncUITests: XCTestCase {
    func testFeedMilkAndReadSyncedNickname() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["watch.openFoodInventory"].waitForExistence(timeout: 8))
        app.buttons["watch.openFoodInventory"].tap()
        XCTAssertTrue(app.buttons["watch.manageFoodInventory"].waitForExistence(timeout: 5))
        app.buttons["watch.manageFoodInventory"].tap()
        let quantity = app.staticTexts["watch.foodQuantity.1"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        let before = count(quantity.label)
        let feed = app.buttons["watch.feedFood.1"]
        for _ in 0..<4 { if feed.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(feed.isEnabled && feed.isHittable)
        feed.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in quantity.exists && self.count(quantity.label) == before - 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        print("WATCH_AUDIT_MILK=\(before - 1)")
        capture(app, "watch-fed-milk")
        app.terminate(); app.launch()
        for _ in 0..<10 {
            if app.staticTexts["watch.accountName"].isHittable { break }
            app.swipeUp()
        }
        let name = app.staticTexts["watch.accountName"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertTrue(name.label.hasPrefix("Phone"), name.label)
        print("WATCH_AUDIT_NICKNAME=\(name.label)")
        capture(app, "watch-synced-phone-nickname")
    }
    private func count(_ label: String) -> Int { Int(label.filter(\.isNumber)) ?? -1 }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
