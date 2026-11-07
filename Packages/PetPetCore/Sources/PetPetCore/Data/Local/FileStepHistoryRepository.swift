import Foundation

public enum StepHistoryStoreError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidRecord
}

/// One instance per application container. No third-party database or account
/// capability is needed. Writes serialize through the actor and replace the
/// file atomically; a failed write remains dirty for the next save to retry.
public actor FileStepHistoryRepository: StepHistoryRepository {
    private struct Archive: Codable {
        var version: Int
        var records: [String: Int]
    }

    private let fileURL: URL
    private var records: [String: Int]?
    private var isDirty = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func record(for date: String) throws -> DailyStepRecord? {
        try loadIfNeeded()
        return records?[date].map { DailyStepRecord(date: date, stepCount: $0) }
    }

    public func allRecords() throws -> [DailyStepRecord] {
        try loadIfNeeded()
        return (records ?? [:]).map { DailyStepRecord(date: $0.key, stepCount: $0.value) }
            .sorted { $0.date > $1.date }
    }

    public func save(_ record: DailyStepRecord) throws {
        guard Self.isValidDate(record.date), record.stepCount >= 0 else {
            throw StepHistoryStoreError.invalidRecord
        }
        try loadIfNeeded()
        let existing = records?[record.date]
        let total = max(existing ?? 0, record.stepCount)
        guard existing != total || isDirty else { return }

        records?[record.date] = total
        isDirty = true
        let data = try JSONEncoder().encode(Archive(version: 1, records: records ?? [:]))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        isDirty = false
    }

    private func loadIfNeeded() throws {
        guard records == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = [:]
            return
        }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else {
            throw StepHistoryStoreError.unsupportedVersion(archive.version)
        }
        guard archive.records.allSatisfy({ Self.isValidDate($0.key) && $0.value >= 0 }) else {
            throw StepHistoryStoreError.invalidRecord
        }
        records = archive.records
    }

    private static func isValidDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2,
              parts[2].count == 2, let year = Int(parts[0]),
              let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day
    }
}
