import XCTest

@MainActor final class WatchCommunityUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }
    func test10CumulativeStepsPageForwardBackAndRefresh() {
        openAccount(); ensureLogin()
        reveal(app.buttons["watch.stepRanking"]); app.buttons["watch.stepRanking"].tap()
        assertPage(1)
        reveal(app.buttons["rank.previous"], enabled: false); XCTAssertFalse(app.buttons["rank.previous"].isEnabled)
        next(); assertPage(2); capture("community-40mm-steps-page2")
        previous(); assertPage(1)
        reveal(app.buttons["rank.refresh"], down: false); app.buttons["rank.refresh"].tap(); assertPage(1)
    }
    func test20ShootingRangePages() { gamePages("shooting") }
    func test21StarStairRangePages() { gamePages("starStair") }
    func test30PictureUploadAndRelaunch() {
        openAccount(); ensureLogin(); openPicture()
        let set = app.buttons["profile.usePetImage"]; reveal(set)
        XCTAssertTrue(wait { set.isEnabled }); set.tap()
        let feedback = app.staticTexts["profile.feedback"]; reveal(feedback)
        XCTAssertTrue(wait { feedback.label == "대표 이미지를 바꿨어요." })
        reveal(app.staticTexts["profile.pictureState"], down: false)
        XCTAssertEqual(app.staticTexts["profile.pictureState"].label, "대표 이미지가 저장되어 있어요.")
        capture("community-40mm-picture-updated")
        app.terminate(); app.launch(); openAccount(); openPicture()
        let state = app.staticTexts["profile.pictureState"]
        XCTAssertTrue(wait { state.exists && state.label == "대표 이미지가 저장되어 있어요." })
        let image = app.descendants(matching: .any).matching(identifier: "profile.picture").firstMatch
        XCTAssertEqual(image.label, "저장된 대표 이미지")
        capture("community-40mm-picture-after-relaunch")
    }
    func test40LargeTextRankingAndPictureControls() {
        app.terminate(); app.launchArguments = ["--watch-ui-large-text"]; app.launch()
        test10CumulativeStepsPageForwardBackAndRefresh()
        capture("integrated-watch-large-ranking")
        app.terminate(); app.launch(); openAccount(); openPicture()
        for id in ["profile.choosePhoto", "profile.usePetImage", "profile.refresh"] {
            let button = app.buttons[id]; reveal(button)
            XCTAssertTrue(button.isEnabled); XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame))
        }
        capture("integrated-watch-large-picture-controls")
    }
    private func gamePages(_ game: String) {
        crownTo("watch.openGames"); app.buttons["watch.openGames"].tap()
        let link = app.buttons["game.openRange.\(game)"]; reveal(link); link.tap()
        assertPage(1); next(); assertPage(2); capture("community-40mm-\(game)-page2")
        previous(); assertPage(1)
    }
    private func ensureLogin() {
        if app.buttons["watch.editPicture"].waitForExistence(timeout: 2) { return }
        let login = app.buttons["watch.standaloneLogin"]; reveal(login); login.tap()
        let picture = app.buttons["watch.editPicture"]; reveal(picture, down: false); XCTAssertTrue(picture.exists)
    }
    private func openPicture() { let link = app.buttons["watch.editPicture"]; reveal(link, down: false); link.tap(); XCTAssertTrue(app.staticTexts["profile.pictureState"].waitForExistence(timeout: 5)) }
    private func openAccount() {
        crownTo("watch.openStreak"); app.buttons["watch.openStreak"].tap()
        let link = app.buttons["watch.openAccount"]; reveal(link); link.tap()
    }
    private func assertPage(_ number: Int) {
        let page = app.staticTexts["rank.page"]; reveal(page, down: false)
        XCTAssertTrue(wait { page.exists && page.label == "\(number)페이지" && self.app.buttons["rank.refresh"].isEnabled })
        XCTAssertFalse(app.staticTexts["rank.error"].exists)
    }
    private func next() { let button = app.buttons["rank.next"]; reveal(button); XCTAssertTrue(wait { button.isEnabled }); button.tap(); assertHeaderVisible() }
    private func previous() { let button = app.buttons["rank.previous"]; reveal(button); XCTAssertTrue(wait { button.isEnabled }); button.tap(); assertHeaderVisible() }
    private func assertHeaderVisible() {
        let header = app.staticTexts["rank.page"]
        XCTAssertTrue(wait { header.exists && header.isHittable && self.app.windows.firstMatch.frame.contains(header.frame) }, "A new page must reveal its header without manual scrolling")
    }
    private func crownTo(_ id: String) {
        let ids = ["watch.petTouch", "watch.managePetStatistics", "watch.openGames", "watch.openStreak", "watch.openChat"]
        for _ in 0..<12 {
            if app.buttons[id].exists && app.buttons[id].isHittable { return }
            let current = ids.firstIndex { app.buttons[$0].exists && app.buttons[$0].isHittable } ?? 0
            let target = ids.firstIndex(of: id) ?? 0
            XCUIDevice.shared.rotateDigitalCrown(delta: target > current ? 0.5 : -0.5)
        }
        XCTFail("Missing root page \(id)")
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true, enabled: Bool = true) {
        for _ in 0..<20 {
            var down = preferredDown
            if element.exists {
                let frame = element.frame, screen = app.windows.firstMatch.frame
                if (!enabled || element.isHittable) && screen.contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= screen.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.83 : 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.83)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing community control \(element)\n\(app.debugDescription)")
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in condition() }, object: nil)], timeout: 12) == .completed
    }
    private func capture(_ name: String) { let value = XCTAttachment(screenshot: app.screenshot()); value.name = name; value.lifetime = .keepAlways; add(value) }
}
