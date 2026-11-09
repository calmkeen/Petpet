import Foundation
import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor
final class WatchPetLifecycleTests: XCTestCase {
    func testRapidBackgroundAndReturnStartsOnlyOneMoodLoop() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let repository = HeldPetVisit(file: file)
        let waits = MoodWaits()
        let history = FileStepHistoryRepository(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = PetProgressViewModel(repository: repository, history: history, waitForMoodRefresh: waits.wait)
        defer { model.stop(); waits.finish() }
        let first = Task { await model.start() }
        await until { await repository.waiting }
        model.stop(); await model.start()
        await until { waits.requests == 1 }
        await repository.release(); await first.value
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(waits.requests, 1, "A late initial load must not create a second foreground timer")
    }

    func testForegroundMoodRefreshAlsoRecordsRecentActivity() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let clock = PetClock()
        let repository = FilePetProgressRepository(fileURL: file, now: { clock.now })
        let waits = MoodWaits()
        let history = FileStepHistoryRepository(fileURL: file.appendingPathExtension("steps"))
        let model = PetProgressViewModel(repository: repository, history: history, waitForMoodRefresh: waits.wait)
        defer { model.stop(); waits.finish() }
        await model.start(); await until { waits.requests == 1 }
        clock.advance(600); waits.releaseAll()
        await until { waits.requests == 2 }
        let progress = try await repository.load()
        XCTAssertEqual(progress.lastActiveAt, clock.now, "Android records activity at every 10-minute foreground refresh")
    }

    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<100 { if await condition() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out waiting for foreground work")
    }
}

@MainActor private final class MoodWaits {
    private(set) var requests = 0
    private var pending: [CheckedContinuation<Void, Error>] = []
    private var finished = false
    func wait() async throws {
        try Task.checkCancellation()
        guard !finished else { throw CancellationError() }
        requests += 1
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func releaseAll() { let values = pending; pending.removeAll(); values.forEach { $0.resume() } }
    func finish() { finished = true; let values = pending; pending.removeAll(); values.forEach { $0.resume(throwing: CancellationError()) } }
}

private actor HeldPetVisit: PetProgressRepository {
    private(set) var waiting = false
    private var first: CheckedContinuation<Void, Never>?
    private let repository: FilePetProgressRepository
    init(file: URL) { repository = FilePetProgressRepository(fileURL: file) }
    func load() async throws -> PetProgress { try await repository.load() }
    func perform(_ action: PetProgressAction) async throws -> PetProgressChange {
        if !waiting { waiting = true; await withCheckedContinuation { first = $0 } }
        return try await repository.perform(action)
    }
    func release() { first?.resume(); first = nil }
}

private final class PetClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_794_211_200)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}
