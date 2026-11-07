import XCTest
@testable import PetPetCore

final class StepDayTests: XCTestCase {
    func testDaylightSavingUsesCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = StepDay(containing: instant("2026-03-08T16:00:00Z"), calendar: calendar)
        let fall = StepDay(containing: instant("2026-11-01T16:00:00Z"), calendar: calendar)
        XCTAssertEqual(spring.date, "2026-03-08")
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3_600)
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 3_600)
    }

    func testDateKeyRemainsGregorianForAlternativeUserCalendar() {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = StepDay(containing: instant("2026-11-06T16:00:00Z"), calendar: calendar)
        XCTAssertEqual(day.date, "2026-11-07")
        XCTAssertEqual(day.start, instant("2026-11-06T15:00:00Z"))
    }
}
