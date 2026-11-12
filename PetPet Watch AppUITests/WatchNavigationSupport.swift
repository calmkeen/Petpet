import XCTest

/// Open the care page through the Crown; the pet home has no arrow controls.
@MainActor
func openWatchPetCare(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.buttons["watch.petTouch"].waitForExistence(timeout: 10), file: file, line: line)
    XCUIDevice.shared.rotateDigitalCrown(delta: 0.5)
    XCTAssertTrue(app.buttons["watch.managePetStatistics"].waitForExistence(timeout: 8), file: file, line: line)
}
