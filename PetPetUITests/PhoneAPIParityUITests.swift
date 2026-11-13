import XCTest

@MainActor final class PhoneAPIParityUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launch() }
    override func tearDownWithError() throws { app.terminate() }
    func test10StepRankingPagesAndServerOutput() {
        openAccount(); loginIfNeeded()
        open("phone.openStepRanking"); assertPage(1)
        next(); assertPage(2)
        let steps = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9,]+ 걸음")).firstMatch
        reveal(steps); XCTAssertTrue(steps.exists); capture("api-parity-phone-step-ranking")
        previous(); assertPage(1)
    }
    func test20ShootingRangePages() { gamePages(stairs: false) }
    func test21StairsRangePagesAndComboOutput() { gamePages(stairs: true) }
    func test30PictureUpdatePersistsAcrossRelaunch() {
        openAccount(); loginIfNeeded(); open("phone.editPicture")
        let set = app.buttons["phone.usePetPicture"]; reveal(set); XCTAssertTrue(wait { set.isEnabled }); set.tap()
        let feedback = app.staticTexts["phone.pictureFeedback"]; reveal(feedback)
        XCTAssertTrue(wait { feedback.label == "대표 이미지를 바꿨어요." })
        capture("api-parity-phone-picture-updated")
        app.terminate(); app.launch(); openAccount(); open("phone.editPicture")
        let state = app.staticTexts["phone.profilePictureState"]
        XCTAssertTrue(wait { state.exists && state.label == "대표 이미지가 저장되어 있어요." })
        let image = app.descendants(matching: .any).matching(identifier: "phone.profilePicture").firstMatch
        XCTAssertEqual(image.label, "저장된 대표 이미지"); capture("api-parity-phone-picture-relaunch")
    }
    func test31WatchPictureAndNicknameAreVisibleWithoutPhoneUpload() {
        openAccount(); loginIfNeeded()
        let name = app.staticTexts["phone.accountName"]
        XCTAssertTrue(wait { name.exists && name.label.hasPrefix("FinalWatch") })
        capture("integrated-phone-watch-nickname")
        open("phone.editPicture")
        let state = app.staticTexts["phone.profilePictureState"]
        XCTAssertTrue(wait { state.exists && state.label == "대표 이미지가 저장되어 있어요." })
        let image = app.descendants(matching: .any).matching(identifier: "phone.profilePicture").firstMatch
        XCTAssertEqual(image.label, "저장된 대표 이미지")
        capture("integrated-phone-watch-picture")
    }
    func test40LargeDarkStepRankingAndPictureControls() {
        app.terminate(); app.launchArguments = ["--phone-ui-large-text", "--phone-ui-dark"]; app.launch()
        openAccount(); loginIfNeeded(); open("phone.openStepRanking")
        assertPage(1); next(); assertPage(2); capture("api-parity-phone-large-ranking")
        app.terminate(); app.launch(); openAccount(); open("phone.editPicture")
        for id in ["phone.choosePicture", "phone.usePetPicture", "phone.refreshPicture"] {
            let target = app.buttons[id]; reveal(target)
            XCTAssertGreaterThanOrEqual(target.frame.height, 44)
            XCTAssertTrue(visibleFrame.contains(target.frame))
        }
        capture("api-parity-phone-large-picture-controls")
    }
    private func openAccount() { open("phone.openAccount") }
    private func loginIfNeeded() {
        let login = app.buttons["phone.developmentSignIn"]
        if login.waitForExistence(timeout: 1) { reveal(login); login.tap() }
        XCTAssertTrue(app.buttons["phone.editPicture"].waitForExistence(timeout: 12))
    }
    private func gamePages(stairs: Bool) {
        openAccount(); loginIfNeeded(); app.navigationBars.buttons.firstMatch.tap()
        open("phone.openExtras")
        if stairs {
            let picker = app.descendants(matching: .any).matching(identifier: "phone.rankGame").firstMatch
            reveal(picker); picker.tap(); app.buttons["별계단 훈련"].tap()
        }
        open("phone.openGameRange"); assertPage(1); next(); assertPage(2)
        if stairs {
            let combo = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "최대 콤보 ")).firstMatch
            reveal(combo); XCTAssertTrue(combo.exists)
        }
        capture(stairs ? "api-parity-phone-stairs-range" : "api-parity-phone-shooting-range")
        previous(); assertPage(1)
    }
    private func open(_ id: String) { let button = app.buttons[id]; reveal(button); button.tap() }
    private func next() { let button = app.buttons["phone.rankNext"]; reveal(button); XCTAssertTrue(wait { button.isEnabled }); button.tap() }
    private func previous() { let button = app.buttons["phone.rankPrevious"]; reveal(button); XCTAssertTrue(wait { button.isEnabled }); button.tap() }
    private func assertPage(_ number: Int) {
        let page = app.staticTexts["phone.rankPage"]; reveal(page, down: false)
        XCTAssertTrue(wait { page.label == "\(number)페이지" && self.app.buttons["phone.rankPageRefresh"].isEnabled })
        XCTAssertFalse(app.staticTexts["phone.rankPageError"].exists)
    }
    private var visibleFrame: CGRect {
        let screen = app.windows.firstMatch.frame
        let nav = app.navigationBars.firstMatch
        let top = nav.exists ? max(24, nav.frame.maxY) : 24
        return CGRect(x: screen.minX, y: top, width: screen.width, height: screen.maxY - top).insetBy(dx: -1, dy: -1)
    }
    private func reveal(_ element: XCUIElement, down preferredDown: Bool = true) {
        for _ in 0..<30 {
            var down = preferredDown
            if element.exists {
                let frame = element.frame
                if element.isHittable && visibleFrame.contains(frame) { return }
                if !frame.isEmpty { down = frame.midY >= visibleFrame.midY }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.82 : 0.37))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.37 : 0.82)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Missing API UI \(element)\n\(app.debugDescription)")
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool { XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in condition() }, object: nil)], timeout: 12) == .completed }
    private func capture(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
}
