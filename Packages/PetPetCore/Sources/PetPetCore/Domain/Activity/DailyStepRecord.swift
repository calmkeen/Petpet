import Foundation

/// A calendar-day total. `date` uses the Android daily_steps key, yyyy-MM-dd.
/// Counts are cumulative for the entire local calendar day.
public struct DailyStepRecord: Codable, Equatable, Sendable {
    public var date: String
    public var stepCount: Int

    public init(date: String, stepCount: Int) {
        self.date = date
        self.stepCount = stepCount
    }
}
