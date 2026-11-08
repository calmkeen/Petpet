import XCTest
@testable import PetPetCore

final class DailyStepTrackerTests: XCTestCase {
    @MainActor func testRefreshRestartsLiveStreamAfterTransientFailure() async {
        let counter = FakeDailyStepCounter(count:20)
        let tracker = makeTracker(counter,MemoryStepHistory(),TestStepClock())
        await tracker.start()
        counter.send(.failure(.updateFailed))
        XCTAssertFalse(tracker.state.isTracking)
        counter.count = 30
        await tracker.refresh()
        XCTAssertEqual(counter.starts.count,2)
        XCTAssertTrue(tracker.state.isTracking); XCTAssertNil(tracker.state.error)
        counter.send(.success(999),subscription:0)
        XCTAssertEqual(tracker.state.stepCount,30)
        counter.send(.success(31)); XCTAssertEqual(tracker.state.stepCount,31)
        tracker.stop(); await tracker.flush()
    }
    @MainActor
    func testStartsAtLocalMidnightAndIgnoresDuplicateStarts() async {
        let clock = TestStepClock()
        let counter = FakeDailyStepCounter(count: 234)
        let store = MemoryStepHistory()
        let tracker = makeTracker(counter, store, clock)
        await tracker.start()
        await tracker.start()
        await tracker.flush()
        XCTAssertEqual(counter.starts, [instant("2026-11-07T00:00:00Z")])
        XCTAssertEqual(tracker.state.date, "2026-11-07")
        XCTAssertEqual(tracker.state.stepCount, 234)
        let saved = try? await store.record(for: "2026-11-07")
        XCTAssertEqual(saved?.stepCount, 234)
        tracker.stop()
    }

    @MainActor
    func testCachedTotalIsVisibleWhileHistoricalQueryIsPending() async {
        let clock = TestStepClock()
        let counter = FakeDailyStepCounter()
        let store = MemoryStepHistory(["2026-11-07": 120])
        let tracker = makeTracker(counter, store, clock)
        let queried = expectation(description: "Historical query started")
        counter.onQuery = { _, _ in
            queried.fulfill()
            return try await withCheckedThrowingContinuation { counter.pending = $0 }
        }
        let start = Task { await tracker.start() }
        await fulfillment(of: [queried], timeout: 2)
        XCTAssertEqual(tracker.state.stepCount, 120)
        XCTAssertTrue(tracker.state.isLoading)
        counter.pending?.resume(returning: 180)
        await start.value
        XCTAssertEqual(tracker.state.stepCount, 180)
        XCTAssertFalse(tracker.state.isLoading)
        tracker.stop()
        await tracker.flush()
    }

    @MainActor
    func testQueryAndLiveCumulativeTotalsAreNotAddedTogether() async {
        let counter = FakeDailyStepCounter()
        counter.onQuery = { _, _ in
            counter.send(.success(900))
            return 400
        }
        let store = MemoryStepHistory(["2026-11-07": 300])
        let tracker = makeTracker(counter, store, TestStepClock())
        await tracker.start()
        counter.send(.success(950))
        await tracker.flush()
        XCTAssertEqual(tracker.state.stepCount, 950)
        let saved = try? await store.record(for: "2026-11-07")
        XCTAssertEqual(saved?.stepCount, 950)
        tracker.stop()
    }

    @MainActor
    func testLowerSensorTotalDoesNotEraseStoredDay() async {
        let counter = FakeDailyStepCounter(count: 2)
        let store = MemoryStepHistory(["2026-11-07": 1_000])
        let tracker = makeTracker(counter, store, TestStepClock())
        await tracker.start()
        counter.send(.success(5))
        await tracker.flush()
        XCTAssertEqual(tracker.state.stepCount, 1_000)
        let saved = try? await store.record(for: "2026-11-07")
        XCTAssertEqual(saved?.stepCount, 1_000)
        tracker.stop()
    }

    @MainActor
    func testMidnightRollsOverWithoutWaitingForANewStep() async {
        let clock = TestStepClock(now: instant("2026-11-07T23:59:50Z"))
        let counter = FakeDailyStepCounter(count: 1_800)
        let store = MemoryStepHistory()
        let tracker = makeTracker(counter, store, clock)
        await tracker.start()
        clock.now = instant("2026-11-08T00:00:01Z")
        counter.count = 0
        await tracker.refresh()
        counter.send(.success(99_999), subscription: 0)
        await tracker.flush()
        XCTAssertEqual(tracker.state.date, "2026-11-08")
        XCTAssertEqual(tracker.state.stepCount, 0)
        XCTAssertEqual(counter.starts.last, instant("2026-11-08T00:00:00Z"))
        let yesterday = try? await store.record(for: "2026-11-07")
        let today = try? await store.record(for: "2026-11-08")
        XCTAssertEqual(yesterday?.stepCount, 1_800)
        XCTAssertEqual(today?.stepCount, 0)
        tracker.stop()
    }

    @MainActor
    func testForegroundAfterMultipleDaysRestoresTodayAndPreservesOldRecords() async {
        let clock = TestStepClock()
        let counter = FakeDailyStepCounter(count: 50)
        let store = MemoryStepHistory()
        let tracker = makeTracker(counter, store, clock)
        await tracker.start()
        tracker.stop()
        await tracker.flush()
        clock.now = instant("2026-11-10T12:00:00Z")
        counter.count = 600
        await tracker.start()
        await tracker.flush()
        XCTAssertEqual(tracker.state.date, "2026-11-10")
        XCTAssertEqual(tracker.state.stepCount, 600)
        let old = try? await store.record(for: "2026-11-07")
        XCTAssertEqual(old?.stepCount, 50)
        tracker.stop()
    }

    @MainActor
    func testRestartRejectsOldSubscriptionCallbacks() async {
        let counter = FakeDailyStepCounter(count: 20)
        let tracker = makeTracker(counter, MemoryStepHistory(), TestStepClock())
        await tracker.start()
        tracker.stop()
        counter.count = 30
        await tracker.start()
        counter.send(.success(9_999), subscription: 0)
        counter.send(.success(31), subscription: 1)
        XCTAssertEqual(tracker.state.stepCount, 31)
        tracker.stop()
        await tracker.flush()
    }

    @MainActor
    func testStopRejectsLateHistoricalQueryAndLiveCallback() async {
        let counter = FakeDailyStepCounter()
        let tracker = makeTracker(counter, MemoryStepHistory(["2026-11-07": 10]), TestStepClock())
        let queried = expectation(description: "Historical query started")
        counter.onQuery = { _, _ in
            queried.fulfill()
            return try await withCheckedThrowingContinuation { counter.pending = $0 }
        }
        let start = Task { await tracker.start() }
        await fulfillment(of: [queried], timeout: 2)
        tracker.stop()
        counter.send(.success(900))
        counter.pending?.resume(returning: 800)
        await start.value
        XCTAssertEqual(tracker.state.stepCount, 10)
        XCTAssertFalse(tracker.state.isTracking)
        XCTAssertFalse(tracker.state.isLoading)
    }

    @MainActor
    func testDeniedPermissionKeepsCachedTotal() async {
        let counter = FakeDailyStepCounter()
        counter.startError = .permissionDenied
        counter.onQuery = { _, _ in throw StepCountingError.permissionDenied }
        let tracker = makeTracker(counter, MemoryStepHistory(["2026-11-07": 600]), TestStepClock())
        await tracker.start()
        XCTAssertEqual(tracker.state.stepCount, 600)
        XCTAssertEqual(tracker.state.error, .permissionDenied)
        XCTAssertFalse(tracker.state.isTracking)
        tracker.stop()
    }

    @MainActor
    func testRepeatedTotalsDoNotWriteAgain() async {
        let counter = FakeDailyStepCounter(count: 10)
        let store = MemoryStepHistory()
        let tracker = makeTracker(counter, store, TestStepClock())
        await tracker.start()
        await tracker.flush()
        counter.send(.success(10))
        counter.send(.success(10))
        await tracker.flush()
        let writes = await store.writeCount
        XCTAssertEqual(writes, 1)
        tracker.stop()
    }

    @MainActor
    func testStorageFailureIsShownAndRetriedWithoutLosingSteps() async {
        let store = MemoryStepHistory()
        await store.setFailWrites(true)
        let counter = FakeDailyStepCounter(count: 100)
        let tracker = makeTracker(counter, store, TestStepClock())
        await tracker.start()
        await tracker.flush()
        XCTAssertEqual(tracker.state.stepCount, 100)
        XCTAssertTrue(tracker.state.hasStorageError)
        await store.setFailWrites(false)
        await tracker.flush()
        let saved = try? await store.record(for: "2026-11-07")
        XCTAssertEqual(saved?.stepCount, 100)
        XCTAssertFalse(tracker.state.hasStorageError)
        tracker.stop()
    }

    @MainActor
    func testTimeZoneChangeRestartsTheRangeEvenForSameDateKey() async {
        let clock = TestStepClock()
        let counter = FakeDailyStepCounter(count: 100)
        let tracker = makeTracker(counter, MemoryStepHistory(), clock)
        await tracker.start()
        clock.calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        counter.count = 120
        await tracker.refresh()
        XCTAssertEqual(tracker.state.date, "2026-11-07")
        XCTAssertEqual(counter.starts.count, 2)
        XCTAssertEqual(counter.starts.last, instant("2026-11-06T15:00:00Z"))
        XCTAssertEqual(tracker.state.stepCount, 120)
        tracker.stop()
        await tracker.flush()
    }

    @MainActor
    func testRecoversRecentDaysAndKeepsOlderStoredHistory() async {
        let clock = TestStepClock()
        let counter = FakeDailyStepCounter()
        counter.onQuery = { start, _ in
            switch StepDay(containing: start, calendar: clock.calendar).date {
            case "2026-11-07": return 200
            case "2026-11-06": return 1_800
            case "2026-11-05": return 1_500
            default: return 0
            }
        }
        let store = MemoryStepHistory(["2026-10-01": 9_000, "2026-11-06": 1_000])
        let tracker = makeTracker(counter, store, clock, historyDays: 6)
        await tracker.start()
        await tracker.finishHistoryRecovery()
        let records = (try? await store.allRecords()) ?? []
        XCTAssertEqual(records.first?.date, "2026-11-07")
        XCTAssertEqual(records.first { $0.date == "2026-11-06" }?.stepCount, 1_800)
        XCTAssertEqual(records.first { $0.date == "2026-11-05" }?.stepCount, 1_500)
        XCTAssertEqual(records.last?.stepCount, 9_000)
        XCTAssertEqual(tracker.state.stepCount, 200)
        XCTAssertEqual(counter.queries.count, 7)
        tracker.stop()
    }

    @MainActor
    func testAutomaticMidnightTaskRotatesWithoutCancellingItsOwnRefresh() async {
        let clock = TestStepClock(now: instant("2026-11-07T23:59:50Z"))
        let counter = FakeDailyStepCounter(count: 100)
        let store = MemoryStepHistory()
        let rolled = expectation(description: "Automatic midnight rollover completed")
        var waitCount = 0
        let tracker = DailyStepTracker(
            counter: counter, repository: store, now: { clock.now },
            calendar: { clock.calendar }, historyDays: 0,
            waitForMidnight: { delay in
                waitCount += 1
                if waitCount == 1 {
                    XCTAssertEqual(delay, 10, accuracy: 0.001)
                    clock.now = instant("2026-11-08T00:00:01Z")
                    counter.count = 0
                } else {
                    try await Task.sleep(nanoseconds: 3_600_000_000_000)
                }
            }
        )
        var didFulfill = false
        tracker.onStateChange = { state in
            if state.date == "2026-11-08", !state.isLoading, !didFulfill {
                didFulfill = true
                rolled.fulfill()
            }
        }
        await tracker.start()
        await fulfillment(of: [rolled], timeout: 2)
        XCTAssertEqual(counter.starts.last, instant("2026-11-08T00:00:00Z"))
        XCTAssertEqual(tracker.state.stepCount, 0)
        tracker.stop()
        await tracker.flush()
    }

    @MainActor
    func testFailedLiveStreamStillShowsAnErrorWhenHistoryQuerySucceeds() async {
        let counter = FakeDailyStepCounter(count: 120)
        counter.startError = .updateFailed
        let tracker = makeTracker(counter, MemoryStepHistory(), TestStepClock())
        await tracker.start()
        XCTAssertEqual(tracker.state.stepCount, 120)
        XCTAssertEqual(tracker.state.error, .updateFailed)
        XCTAssertFalse(tracker.state.isTracking)
        tracker.stop()
        await tracker.flush()
    }

    @MainActor
    func testHistoryRecoveryNeverQueriesClippedSevenDayWindow() async {
        let clock = TestStepClock(now: instant("2026-11-02T04:59:00Z"))
        clock.calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let counter = FakeDailyStepCounter(count: 0)
        let tracker = makeTracker(counter, MemoryStepHistory(), clock, historyDays: 6)
        await tracker.start()
        await tracker.finishHistoryRecovery()
        XCTAssertEqual(counter.queries.count, 6)
        XCTAssertTrue(counter.queries.allSatisfy { $0.0 >= clock.now.addingTimeInterval(-7 * 86_400) })
        tracker.stop()
    }

    @MainActor
    private func makeTracker(
        _ counter: FakeDailyStepCounter, _ repository: MemoryStepHistory,
        _ clock: TestStepClock, historyDays: Int = 0
    ) -> DailyStepTracker {
        DailyStepTracker(
            counter: counter, repository: repository, now: { clock.now },
            calendar: { clock.calendar }, automaticallyRefreshAtMidnight: false,
            historyDays: historyDays
        )
    }
}

@MainActor
private final class TestStepClock {
    var now: Date
    var calendar: Calendar
    init(now: Date = instant("2026-11-07T12:00:00Z")) {
        self.now = now
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }
}

@MainActor
private final class FakeDailyStepCounter: StepCounting {
    var count: Int
    var startError: StepCountingError?
    var starts: [Date] = []
    var queries: [(Date, Date)] = []
    var pending: CheckedContinuation<Int, Error>?
    var onQuery: (@MainActor (Date, Date) async throws -> Int)?
    private var handlers: [@MainActor (Result<Int, StepCountingError>) -> Void] = []

    init(count: Int = 0) { self.count = count }
    func steps(from start: Date, to end: Date) async throws -> Int {
        queries.append((start, end))
        if let onQuery { return try await onQuery(start, end) }
        return count
    }
    func startUpdates(
        from date: Date, onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void
    ) {
        starts.append(date)
        handlers.append(onUpdate)
        if let startError { onUpdate(.failure(startError)) }
    }
    func stopUpdates() {}
    func send(_ result: Result<Int, StepCountingError>, subscription: Int? = nil) {
        handlers[subscription ?? (handlers.count - 1)](result)
    }
}

private actor MemoryStepHistory: StepHistoryRepository {
    private var values: [String: Int]
    private var failWrites = false
    private(set) var writeCount = 0
    init(_ values: [String: Int] = [:]) { self.values = values }
    func setFailWrites(_ value: Bool) { failWrites = value }
    func record(for date: String) throws -> DailyStepRecord? {
        values[date].map { DailyStepRecord(date: date, stepCount: $0) }
    }
    func allRecords() throws -> [DailyStepRecord] {
        values.map { DailyStepRecord(date: $0.key, stepCount: $0.value) }.sorted { $0.date > $1.date }
    }
    func save(_ record: DailyStepRecord) throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        writeCount += 1
        values[record.date] = max(values[record.date] ?? 0, record.stepCount)
    }
}

func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
