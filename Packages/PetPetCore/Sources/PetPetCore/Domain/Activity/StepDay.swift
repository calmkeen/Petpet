import Foundation

/// Gregorian keys match Android LocalDate. Boundaries follow the device's time
/// zone and calendar days, including 23/25-hour daylight-saving days.
public struct StepDay: Equatable, Sendable {
    public let date: String
    public let start: Date
    public let end: Date

    public init(containing instant: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let interval = gregorian.dateInterval(of: .day, for: instant)!
        start = interval.start
        end = interval.end
        let parts = gregorian.dateComponents([.year, .month, .day], from: start)
        date = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
