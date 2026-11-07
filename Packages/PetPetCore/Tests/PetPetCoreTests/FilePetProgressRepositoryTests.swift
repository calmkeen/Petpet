import XCTest
@testable import PetPetCore

final class FilePetProgressRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_052_800)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testColdReloadPreservesConsumedFoodGrowthAndTouchCounter() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = repository(url)
        _ = try await store.perform(.feed(foodID: 1))
        _ = try await store.perform(.feed(foodID: 1))
        for _ in 0..<49 { _ = try await store.perform(.touch) }
        let restored = repository(url)
        var value = try await restored.load()
        XCTAssertEqual(value.quantity(of: 1), 1)
        XCTAssertEqual(value.pet.level, 2)
        XCTAssertEqual(value.pet.experience, 0)
        XCTAssertEqual(value.pet.statPoints, 2)
        _ = try await restored.perform(.touch)
        value = try await restored.load()
        XCTAssertEqual(value.pet.affection, 1)
        XCTAssertEqual(value.touchCount, 0)
        _ = try await restored.perform(.feed(foodID: 1))
        let empty = try await repository(url).load()
        XCTAssertEqual(empty.quantity(of: 1), 0) // never regrant starter milk
    }

    func testConcurrentFeedingNeverSpendsBeyondInventory() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = repository(url)
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask { (try? await store.perform(.feed(foodID: 1))) != nil }
            }
            var count = 0
            for await result in group where result { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 3)
        let value = try await repository(url).load()
        XCTAssertEqual(value.quantity(of: 1), 0)
        XCTAssertEqual(value.pet.level, 2)
        XCTAssertEqual(value.pet.experience, 1)
    }

    func testConcurrentRewardClaimsAndColdReloadGrantOnlyOnce() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = repository(url)
        let record = today(3_000)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { _ = try await store.perform(.claimRewards(record)) }
            }
            try await group.waitForAll()
        }
        let restored = repository(url)
        let change = try await restored.perform(.claimRewards(record))
        XCTAssertEqual(change.progress.quantity(of: 1), 6)
        XCTAssertEqual(change.progress.quantity(of: 2), 1)
        XCTAssertTrue(try XCTUnwrap(change.reward).isEmpty)
    }

    func testFailedFeedingWriteRollsBackAndRetrySpendsExactlyOnce() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = repository(url)
        let before = try await store.load()
        let saved = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        do {
            _ = try await store.perform(.feed(foodID: 1))
            XCTFail("A failed transaction must throw")
        } catch {}
        let unchanged = try await store.load()
        XCTAssertEqual(unchanged, before)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try saved.write(to: url)
        _ = try await store.perform(.feed(foodID: 1))
        let after = try await repository(url).load()
        XCTAssertEqual(after.quantity(of: 1), 2)
        XCTAssertEqual(after.pet.experience, 1)
    }

    func testFailedRewardWriteDoesNotAdvanceCursorOrInventory() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = repository(url)
        let before = try await store.load()
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do {
            _ = try await store.perform(.claimRewards(today(2_000)))
            XCTFail("A failed transaction must throw")
        } catch {}
        let unchanged = try await store.load()
        XCTAssertEqual(unchanged, before)
        try FileManager.default.removeItem(at: directory)
        let change = try await store.perform(.claimRewards(today(2_000)))
        XCTAssertEqual(change.reward, StepRewardGrant(milk: 2, apple: 1))
        let restored = try await repository(url).load()
        XCTAssertEqual(restored, change.progress)
    }

    func testCorruptUnsupportedAndInvalidArchivesArePreserved() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try await repository(url).load()
        let valid = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["version"] = 99
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress["touchCount"] = -1
        object["version"] = 1
        object["progress"] = progress
        let invalid = try JSONSerialization.data(withJSONObject: object)
        for data in [Data("broken".utf8), unsupported, invalid] {
            try data.write(to: url)
            do {
                _ = try await repository(url).perform(.feed(foodID: 1))
                XCTFail("Must preserve an unreadable archive")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testClaimUsesSavedHighWaterCountAndDoesNotRewardHistoricalBackfill() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let history = FileStepHistoryRepository(fileURL: url.deletingLastPathComponent().appendingPathComponent("steps.json"))
        try await history.save(today(3_000))
        let old = StepDay(containing: now.addingTimeInterval(-86_400), calendar: calendar).date
        try await history.save(DailyStepRecord(date: old, stepCount: 99_000))
        let claim = ClaimStepRewards(history: history, progress: repository(url))
        let change = try await claim(for: today(999))
        XCTAssertEqual(change.reward, StepRewardGrant(milk: 3, apple: 1))
        XCTAssertEqual(change.progress.rewardClaims.count, 1)
    }

    func testHistorySaveFailurePreventsRewards() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = repository(url)
        let before = try await store.load()
        let claim = ClaimStepRewards(history: FailingStepHistory(), progress: store)
        do {
            _ = try await claim(for: today(5_000))
            XCTFail("Cannot reward unsaved steps")
        } catch {}
        let after = try await store.load()
        XCTAssertEqual(after, before)
    }

    private func repository(_ url: URL) -> FilePetProgressRepository {
        let instant = now
        return FilePetProgressRepository(fileURL: url, now: { instant }, calendar: calendar)
    }

    private func today(_ count: Int) -> DailyStepRecord {
        DailyStepRecord(date: StepDay(containing: now, calendar: calendar).date, stepCount: count)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("progress.json")
    }
}

private actor FailingStepHistory: StepHistoryRepository {
    func save(_ record: DailyStepRecord) throws { throw CocoaError(.fileWriteUnknown) }
    func record(for date: String) -> DailyStepRecord? { nil }
    func allRecords() -> [DailyStepRecord] { [] }
}
