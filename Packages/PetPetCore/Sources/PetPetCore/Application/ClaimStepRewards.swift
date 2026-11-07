import Foundation

/// Local counterpart of Android's post-backup reward trigger. A storage failure
/// or a day change during saving must never grant rewards for an unsaved day.
public struct ClaimStepRewards: Sendable {
    private let history: any StepHistoryRepository
    private let progress: any PetProgressRepository

    public init(history: any StepHistoryRepository, progress: any PetProgressRepository) {
        self.history = history
        self.progress = progress
    }

    public func callAsFunction(for record: DailyStepRecord) async throws -> PetProgressChange {
        try await history.save(record)
        guard let saved = try await history.record(for: record.date) else {
            throw PetProgressError.invalidRecord
        }
        return try await progress.perform(.claimRewards(saved))
    }
}
