#if DEBUG
import Foundation
import PetPetCore

@MainActor
final class PreviewStepCounter: StepCounting {
    func steps(from start: Date, to end: Date) async throws -> Int { 1_234 }

    func startUpdates(
        from date: Date,
        onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void
    ) {
        onUpdate(.success(1_234))
    }

    func stopUpdates() {}
}

actor PreviewStepHistoryRepository: StepHistoryRepository {
    private var records: [String: DailyStepRecord] = [:]
    func record(for date: String) -> DailyStepRecord? { records[date] }
    func allRecords() -> [DailyStepRecord] { records.values.sorted { $0.date > $1.date } }
    func save(_ record: DailyStepRecord) { records[record.date] = record }
}
#endif
