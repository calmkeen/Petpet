import XCTest
@testable import PetPetCore

final class FileStepHistoryRepositoryTests: XCTestCase {
    func testRecordsSurviveNewRepositoryInstanceAndAreSortedByDate() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/history.json")
        let store = FileStepHistoryRepository(fileURL: file)
        try await store.save(.init(date: "2026-11-06", stepCount: 500))
        try await store.save(.init(date: "2026-11-07", stepCount: 0))
        let reopened = FileStepHistoryRepository(fileURL: file)
        let records = try await reopened.allRecords()
        XCTAssertEqual(records.map(\.date), ["2026-11-07", "2026-11-06"])
        XCTAssertEqual(records.map(\.stepCount), [0, 500])
        let absent = try await reopened.record(for: "2026-11-05")
        XCTAssertNil(absent)
    }

    func testConcurrentAndOutOfOrderSavesKeepLargestTotal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let store = FileStepHistoryRepository(fileURL: file)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for total in [20, 300, 80, 300, 0, 100] {
                group.addTask { try await store.save(.init(date: "2026-11-07", stepCount: total)) }
            }
            try await group.waitForAll()
        }
        let reopened = FileStepHistoryRepository(fileURL: file)
        let record = try await reopened.record(for: "2026-11-07")
        XCTAssertEqual(record?.stepCount, 300)
    }

    func testCorruptFileIsNotSilentlyOverwritten() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("history.json")
        let original = Data("{broken".utf8)
        try original.write(to: file)
        let store = FileStepHistoryRepository(fileURL: file)
        do {
            try await store.save(.init(date: "2026-11-07", stepCount: 10))
            XCTFail("A corrupt archive must not be replaced with an empty history")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testUnknownSchemaVersionIsPreserved() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("history.json")
        let original = Data("{\"version\":2,\"records\":{\"2026-11-07\":10}}".utf8)
        try original.write(to: file)
        let store = FileStepHistoryRepository(fileURL: file)
        do {
            _ = try await store.allRecords()
            XCTFail("Newer schemas require an explicit migration")
        } catch {
            XCTAssertEqual(error as? StepHistoryStoreError, .unsupportedVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFailedWritesRetryAllDirtyDays() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocker)
        let file = blocker.appendingPathComponent("history.json")
        let store = FileStepHistoryRepository(fileURL: file)
        for record in [DailyStepRecord(date: "2026-11-06", stepCount: 10),
                       DailyStepRecord(date: "2026-11-07", stepCount: 20)] {
            do { try await store.save(record); XCTFail("Writing through a file must fail") }
            catch {}
        }
        try FileManager.default.removeItem(at: blocker)
        try await store.save(.init(date: "2026-11-07", stepCount: 20))
        let reopened = FileStepHistoryRepository(fileURL: file)
        let records = try await reopened.allRecords()
        XCTAssertEqual(records.map(\.stepCount), [20, 10])
    }

    func testInvalidDateAndNegativeCountAreRejected() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStepHistoryRepository(fileURL: root.appendingPathComponent("history.json"))
        for record in [DailyStepRecord(date: "2026-02-30", stepCount: 10),
                       DailyStepRecord(date: "2026-11-07", stepCount: -1)] {
            do { try await store.save(record); XCTFail("Invalid records must be rejected") }
            catch { XCTAssertEqual(error as? StepHistoryStoreError, .invalidRecord) }
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PetPetDailyTests-\(UUID())")
    }
}
