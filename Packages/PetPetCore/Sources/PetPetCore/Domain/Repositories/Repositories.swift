import Foundation

/// Platform-independent persistence can live in PetPetCore/Data; SDK-specific
/// implementations belong to the application's Data layer.
public protocol PetRepository: Sendable {
    func loadSelectedPet() async throws -> PetProfile?
    func save(_ pet: PetProfile) async throws
}

public protocol StepHistoryRepository: Sendable {
    func record(for date: String) async throws -> DailyStepRecord?
    /// Newest calendar day first, matching Android's daily_steps query.
    func allRecords() async throws -> [DailyStepRecord]
    /// Merge cumulative totals without reducing an existing day's count.
    func save(_ record: DailyStepRecord) async throws
}
