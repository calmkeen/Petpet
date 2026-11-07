import XCTest
@testable import PetPetCore

final class SnapshotSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_052_800)
    private let source = UUID()

    func testCodecRoundTripAndInvalidVersionsDatesQuantities() throws {
        let value = snapshot()
        XCTAssertEqual(try WatchSnapshotCodec.decode(WatchSnapshotCodec.encode(value)), value)
        var invalid = value
        invalid.version = 2
        XCTAssertThrowsError(try WatchSnapshotCodec.encode(invalid))
        invalid = value
        invalid.steps = [DailyStepRecord(date: "2026-02-30", stepCount: 1)]
        XCTAssertThrowsError(try WatchSnapshotCodec.encode(invalid))
        invalid = value
        invalid.inventory[0].quantity = -1
        XCTAssertThrowsError(try WatchSnapshotCodec.encode(invalid))
        XCTAssertThrowsError(try WatchSnapshotCodec.decode(Data(repeating: 0, count: 60_001)))
    }

    func testOutboxIdentityAndRevisionSurviveRestartAndClockRollback() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try await FileWatchSnapshotOutbox(fileURL: url).prepare(
            steps: [], progress: .newUser(at: now), at: now)
        let next = try await FileWatchSnapshotOutbox(fileURL: url).prepare(
            steps: [], progress: .newUser(at: now), at: now.addingTimeInterval(-500))
        XCTAssertEqual(first.sourceID, next.sourceID)
        XCTAssertEqual(next.revision, first.revision + 1)
    }

    func testOutboxBoundsHistoryAndPreservesOriginalHistory() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let records = (1...30).map { DailyStepRecord(date: String(format: "2026-10-%02d", $0), stepCount: $0) }
        let value = try await FileWatchSnapshotOutbox(fileURL: url).prepare(
            steps: records, progress: .newUser(at: now), at: now)
        XCTAssertEqual(value.steps.count, 7)
        XCTAssertEqual(value.steps.first?.date, "2026-10-30")
        XCTAssertEqual(records.count, 30)
    }

    func testPhoneRejectsOldOrDuplicateRevisionsEvenWithNewerTimestamp() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        let latest = try await store.accept(snapshot(revision: 5), from: "A", at: now)
        var old = snapshot(revision: 4)
        old.generatedAt = now.addingTimeInterval(500)
        let ignored = try await store.accept(old, from: "A", at: now.addingTimeInterval(500))
        XCTAssertEqual(ignored, latest)
        let duplicate = try await store.accept(snapshot(revision: 5), from: "A", at: now.addingTimeInterval(600))
        XCTAssertEqual(duplicate, latest)
        let restored = try await FilePhoneSnapshotRepository(fileURL: url).load()
        XCTAssertEqual(restored, latest)
    }

    func testConcurrentReceivesKeepNewestRevision() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for revision in (1...30).reversed() {
                let value = snapshot(revision: Int64(revision))
                group.addTask { _ = try await store.accept(value, from: "A", at: value.generatedAt) }
            }
            try await group.waitForAll()
        }
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.snapshot.revision, 30)
    }

    func testWatchReinstallationAcceptsNewSourceAndRejectsRetiredSourceAfterRestart() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        _ = try await store.accept(snapshot(revision: 90), from: "A", at: now)
        var reset = snapshot()
        reset.sourceID = UUID()
        let new = try await store.accept(reset, from: "A", at: now)
        let ignored = try await FilePhoneSnapshotRepository(fileURL: url)
            .accept(snapshot(revision: 91), from: "A", at: now)
        XCTAssertEqual(ignored, new)
    }

    func testDifferentPairedWatchHasIndependentRevision() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        _ = try await store.accept(snapshot(revision: 99), from: "A", at: now)
        let new = try await store.accept(snapshot(revision: 1), from: "B", at: now)
        XCTAssertEqual(new.peerID, "B")
        XCTAssertEqual(new.snapshot.revision, 1)
    }

    func testPreviousDayNeverAppearsAsTodayAndTimeZoneIsRespected() {
        let value = CachedWatchSnapshot(snapshot: snapshot(), receivedAt: now, peerID: "A")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = StepDay(containing: now, calendar: utc)
        var seoul = utc
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        XCTAssertNotNil(value.steps(on: day.start, calendar: utc))
        XCTAssertNil(value.steps(on: day.end, calendar: utc))
        XCTAssertNil(value.steps(on: day.end.addingTimeInterval(-1), calendar: seoul))
    }

    func testFailedPhoneWriteDoesNotAdvanceRevisionAndRetryAcceptsIt() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        let original = try await store.accept(snapshot(), from: "A", at: now)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do {
            _ = try await store.accept(snapshot(revision: 2), from: "A", at: now)
            XCTFail("Write should fail")
        } catch {}
        let unchanged = try await store.load()
        XCTAssertEqual(unchanged, original)
        try FileManager.default.removeItem(at: directory)
        let retry = try await store.accept(snapshot(revision: 2), from: "A", at: now)
        XCTAssertEqual(retry.snapshot.revision, 2)
    }

    func testCorruptPhoneAndOutboxFilesAreNotOverwritten() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = Data("broken".utf8)
        try broken.write(to: url)
        do { _ = try await FilePhoneSnapshotRepository(fileURL: url).accept(snapshot(), from: "A", at: now); XCTFail() }
        catch {}
        XCTAssertEqual(try Data(contentsOf: url), broken)
        do { _ = try await FileWatchSnapshotOutbox(fileURL: url).prepare(steps: [], progress: .newUser(at: now), at: now); XCTFail() }
        catch {}
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }

    @MainActor
    func testReceiverRestoresOfflineCacheRejectsInvalidPayloadAndHidesPreviousWatch() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FilePhoneSnapshotRepository(fileURL: url)
        _ = try await store.accept(snapshot(), from: "A", at: now)
        let transport = TestSnapshotTransport()
        let receiver = PhoneSnapshotReceiver(repository: store, transport: transport)
        await receiver.start()
        XCTAssertNotNil(receiver.state.cached)
        await receiver.refresh()
        XCTAssertTrue(receiver.state.hasTransferError)
        XCTAssertNotNil(receiver.state.cached)
        transport.onSnapshot?(Data("invalid".utf8), "A")
        await receiver.finishReceiving()
        XCTAssertEqual(receiver.state.cached?.snapshot.revision, 1)
        transport.connection.peerID = "B"
        transport.onConnectionChange?(transport.connection)
        XCTAssertNil(receiver.state.cached)
        transport.onSnapshot?(try WatchSnapshotCodec.encode(snapshot(revision: 2)), "A")
        await receiver.finishReceiving()
        XCTAssertNil(receiver.state.cached)
        transport.onSnapshot?(try WatchSnapshotCodec.encode(snapshot()), "B")
        await receiver.finishReceiving()
        XCTAssertEqual(receiver.state.cached?.peerID, "B")
    }

    @MainActor
    func testPublisherDoesNotSendWhenStepFlushFails() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = TestSnapshotTransport()
        let publisher = WatchSnapshotPublisher(
            history: FileStepHistoryRepository(fileURL: directory.appendingPathComponent("steps")),
            progress: FilePetProgressRepository(fileURL: directory.appendingPathComponent("pet")),
            outbox: FileWatchSnapshotOutbox(fileURL: url), transport: transport,
            beforeReading: { throw CocoaError(.fileWriteUnknown) }
        )
        do { _ = try await publisher.publish(); XCTFail("Cannot send unsaved state") } catch {}
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testPublisherSerializesSendingAndQueuesLatestAfterDisconnectedRestart() async throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = FileStepHistoryRepository(fileURL: directory.appendingPathComponent("steps"))
        let progress = FilePetProgressRepository(fileURL: directory.appendingPathComponent("pet"))
        try await history.save(snapshot().steps[0])
        let transport = TestSnapshotTransport()
        transport.connection.isActivated = false
        let publisher = WatchSnapshotPublisher(history: history, progress: progress,
                                               outbox: FileWatchSnapshotOutbox(fileURL: url), transport: transport)
        let offline = try await publisher.publish()
        XCTAssertTrue(transport.sent.isEmpty)
        transport.connection.isActivated = true
        async let first = publisher.publish()
        async let second = publisher.publish()
        _ = try await (first, second)
        let sent = try transport.sent.map(WatchSnapshotCodec.decode)
        XCTAssertEqual(sent.map(\.revision), [offline.revision + 1, offline.revision + 2])
        let restarted = WatchSnapshotPublisher(history: history, progress: progress,
                                               outbox: FileWatchSnapshotOutbox(fileURL: url), transport: transport)
        let latest = try await restarted.publish()
        XCTAssertEqual(latest.sourceID, offline.sourceID)
        XCTAssertEqual(latest.revision, offline.revision + 3)
    }

    private func snapshot(revision: Int64 = 1) -> WatchSnapshot {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let progress = PetProgress.newUser(at: now)
        return WatchSnapshot(sourceID: source, revision: revision, generatedAt: now,
                             steps: [DailyStepRecord(date: StepDay(containing: now, calendar: utc).date, stepCount: 1234)],
                             pet: progress.pet, inventory: progress.inventory)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("sync.json")
    }
}

@MainActor
private final class TestSnapshotTransport: SnapshotTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: true, isCounterpartInstalled: true, peerID: "A")
    var onConnectionChange: ((SnapshotConnection) -> Void)?
    var onSnapshot: ((Data, String) -> Void)?
    var onSnapshotRequest: (() async throws -> Data)?
    var sent: [Data] = []
    func activate() { onConnectionChange?(connection) }
    func publish(_ data: Data) { sent.append(data) }
    func requestLatest() async throws -> Data { throw SnapshotSyncError.notReachable }
}
