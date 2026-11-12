import XCTest

@MainActor
final class WatchPetTouchUITests: XCTestCase {
    func test00SingleTouch() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        let pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10))
        ready(pet)
        let original = read(pet)
        pet.tap()
        let feedback = app.staticTexts["watch.touchFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(feedback.frame))
        capture(app, "pet-touch-large-feedback")
        expect(pet, count: (original.count + 1) % 50, affection: original.affection + (original.count == 49 ? 1 : 0))
        app.terminate()
        app.launch()
        expect(app.buttons["watch.petTouch"], count: (original.count + 1) % 50, affection: original.affection + (original.count == 49 ? 1 : 0))
        app.terminate()
    }

    func test10FiftyTouchesPersistAndUpdateStatus() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        var pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10)); ready(pet)
        let original = read(pet)
        print("TOUCH_BASELINE count=\(original.count) affection=\(original.affection)")
        for index in 1...50 {
            ready(pet); pet.tap()
            let count = (original.count + index) % 50
            let affection = original.affection + (original.count + index) / 50
            if count == 0 {
                let reward = app.staticTexts["watch.touchFeedback"]
                XCTAssertTrue(reward.waitForExistence(timeout: 3))
                XCTAssertEqual(reward.label, "애정도 +1!")
                capture(app, "pet-touch-affection-reward")
            }
            expect(pet, count: count, affection: affection)
            print("TOUCH_SAVED index=\(index) count=\(count) affection=\(affection)")
            if index == 25 {
                app.terminate(); app.launch(); pet = app.buttons["watch.petTouch"]
                expect(pet, count: count, affection: affection)
            }
        }
        app.terminate(); app.launch()
        expect(app.buttons["watch.petTouch"], count: original.count, affection: original.affection + 1)
        app.buttons["watch.openPetStatistics"].tap()
        let affection = app.staticTexts["watch.affection"]
        XCTAssertTrue(affection.waitForExistence(timeout: 5))
        XCTAssertEqual(affection.label, "애정도 \(original.affection + 1)")
        capture(app, "pet-touch-status-after-relaunch")
        app.terminate()
    }

    func test20SavedCountDetail() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let pet = app.buttons["watch.petTouch"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10)); ready(pet)
        let original = read(pet)
        app.buttons["watch.openPetStatistics"].tap()
        XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 5))
        app.buttons["watch.managePetStatistics"].tap()
        let count = app.descendants(matching: .any).matching(identifier: "watch.touchCount").firstMatch
        for _ in 0..<20 {
            let screen = app.windows.firstMatch.frame
            var down = true
            if count.exists {
                let frame = count.frame
                if !frame.isEmpty && screen.contains(frame) { break }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            // Short overlapping drags cannot skip the count row as a full
            // application swipe can in a lazily loaded watchOS list.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(count.exists, app.debugDescription)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(count.frame))
        XCTAssertEqual(count.label, "쓰다듬기 \(original.count)/50 · 50회마다 애정도 +1")
        capture(app, "pet-touch-saved-count-detail")
        app.terminate()
    }

    private func ready(_ pet: XCUIElement) {
        let predicate = NSPredicate { _, _ in pet.exists && pet.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 6), .completed)
    }
    private func read(_ pet: XCUIElement) -> (count: Int, affection: Int) {
        let parts = (pet.value as? String ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        XCTAssertEqual(parts.count, 3, "Touch count / threshold / affection must be accessible")
        return (parts.first ?? -1, parts.last ?? -1)
    }
    private func expect(_ pet: XCUIElement, count: Int, affection: Int) {
        let expected = "쓰다듬기 \(count)/50, 애정도 \(affection)"
        let predicate = NSPredicate { _, _ in pet.exists && pet.value as? String == expected }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
