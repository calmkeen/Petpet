import Foundation

public enum StepIntensity: Int, Codable, Sendable {
    case none, light, medium, strong, goal
    public init(steps: Int) {
        switch steps {
        case 10_000...: self = .goal
        case 6_000...: self = .strong
        case 3_000...: self = .medium
        case 1...: self = .light
        default: self = .none
        }
    }
}

public struct StepMonth: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year; self.month = month
    }
    public init(containing date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        year = calendar.component(.year, from: date); month = calendar.component(.month, from: date)
    }
    public var datePrefix: String { String(format: "%04d-%02d", year, month) }
    public func dateKey(day: Int) -> String { "\(datePrefix)-\(String(format: "%02d", day))" }
    public var dayCount: Int {
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        return month == 2 ? (leap ? 29 : 28) : ([4, 6, 9, 11].contains(month) ? 30 : 31)
    }
    /// Calendar columns start on Sunday, matching the Android watch heatmap.
    public var leadingEmptyDays: Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))!
        return calendar.component(.weekday, from: date) - 1
    }
    public func adding(_ months: Int) -> StepMonth? {
        let (index, overflow) = ((year - 1) * 12 + month - 1).addingReportingOverflow(months)
        guard !overflow, (0..<(9999 * 12)).contains(index) else { return nil }
        return StepMonth(year: index / 12 + 1, month: index % 12 + 1)
    }
}

public struct StepStreak: Equatable, Sendable {
    public enum Anchor: Sendable { case today, latestRecord }
    public let counts: [String: Int]
    public let today: String
    public let currentDays: Int
    public let anchorDate: String

    public init(records: [DailyStepRecord], date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent, anchor: Anchor = .today) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let todayKey = StepDay(containing: date, calendar: calendar).date
        today = todayKey
        var counts: [String: Int] = [:]
        for record in records where StepDateKey.isValid(record.date) && record.stepCount >= 0 {
            counts[record.date] = max(counts[record.date] ?? 0, record.stepCount)
        }
        self.counts = counts
        anchorDate = anchor == .latestRecord ? (counts.keys.filter { $0 <= todayKey }.max() ?? todayKey) : todayKey
        let parts = anchorDate.split(separator: "-").compactMap { Int($0) }
        let anchorInstant = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? date
        var days = 0
        var cursor = calendar.startOfDay(for: anchorInstant)
        // Stop on the first missing/zero day, including today. Calendar day
        // arithmetic handles DST and crosses month/year boundaries.
        while (counts[StepDay(containing: cursor, calendar: calendar).date] ?? 0) > 0 {
            days += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        currentDays = days
    }
}
