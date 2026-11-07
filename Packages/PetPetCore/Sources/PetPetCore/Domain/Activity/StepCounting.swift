import Foundation

public enum StepCountingError: Error, Equatable, Sendable {
    case unavailable
    case permissionDenied
    case updateFailed
}

/// Platform adapters deliver updates on the main actor. Counts are cumulative
/// from `date`, not increments and not necessarily a daily total.
@MainActor
public protocol StepCounting: AnyObject {
    func steps(from start: Date, to end: Date) async throws -> Int
    func startUpdates(
        from date: Date,
        onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void
    )
    func stopUpdates()
}

public struct DailyStepState: Equatable, Sendable {
    public var date: String
    public var stepCount: Int
    public var isTracking: Bool
    public var isLoading: Bool
    public var error: StepCountingError?
    public var hasStorageError: Bool

    public init(
        date: String = "", stepCount: Int = 0, isTracking: Bool = false,
        isLoading: Bool = false, error: StepCountingError? = nil,
        hasStorageError: Bool = false
    ) {
        self.date = date
        self.stepCount = stepCount
        self.isTracking = isTracking
        self.isLoading = isLoading
        self.error = error
        self.hasStorageError = hasStorageError
    }
}
