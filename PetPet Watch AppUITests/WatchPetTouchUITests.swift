import XCTest

@MainActor
final class WatchPetTouchUITests: XCTestCase {
    func test00SingleTouch() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        let pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10)); ready(pet)
        pet.tap(); ready(pet)
        let savedAffection = affection(pet)
        XCTAssertFalse((pet.value as? String ?? "").contains("/50"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "쓰다듬기 [0-9]+/50.*")).firstMatch.exists)
        capture(app, "pet-touch-without-count")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10)); ready(app.buttons["watch.petTouch"])
        XCTAssertEqual(affection(app.buttons["watch.petTouch"]), savedAffection)
        app.terminate()
    }

    func test10FiftyTouchesPersistAndUpdateStatus() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        var pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10)); ready(pet)
        let original = affection(pet)
        for index in 1...50 {
            ready(pet); pet.tap(); ready(pet)
            print("TOUCH_SAVED index=\(index) affection=\(affection(pet))")
            if index == 25 {
                app.terminate(); app.launch(); pet = app.buttons["watch.petTouch"]
                XCTAssertTrue(pet.waitForExistence(timeout: 10)); ready(pet)
            }
        }
        XCTAssertEqual(affection(pet), original + 1)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10)); ready(app.buttons["watch.petTouch"])
        XCTAssertEqual(affection(app.buttons["watch.petTouch"]), original + 1)
        app.buttons["watch.openPetStatistics"].tap()
        let label = app.staticTexts["watch.affection"]
        XCTAssertTrue(label.waitForExistence(timeout: 5)); XCTAssertEqual(label.label, "애정도 \(original + 1)")
        capture(app, "pet-touch-status-after-relaunch")
        app.terminate()
    }

    func test20SavedCountDetail() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["watch.openPetStatistics"].waitForExistence(timeout: 10))
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 5))
        app.buttons["watch.managePetStatistics"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "watch.touchCount").firstMatch.exists)
        capture(app, "pet-statistics-without-count")
        app.terminate()
    }
    private func ready(_ pet: XCUIElement) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in pet.exists && pet.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 8), .completed)
    }
    private func affection(_ pet: XCUIElement) -> Int {
        let number = (pet.value as? String ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first
        XCTAssertNotNil(number); return number ?? -1
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
