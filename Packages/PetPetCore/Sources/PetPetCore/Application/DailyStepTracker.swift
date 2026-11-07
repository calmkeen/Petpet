import Foundation

@MainActor
public final class DailyStepTracker {
    public private(set) var state: DailyStepState
    public var onStateChange: (@MainActor (DailyStepState) -> Void)?

    private let counter: any StepCounting
    private let repository: any StepHistoryRepository
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let automaticallyRefreshAtMidnight: Bool
    private let historyDays: Int
    private let waitForMidnight: @MainActor (TimeInterval) async throws -> Void
    private var isRunning = false
    private var hasSubscription = false
    private var generation = 0
    private var activeDay: StepDay?
    private var queryingGeneration: Int?
    private var midnightTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var lastRecoveredDay: StepDay?
    private var saveTask: Task<Void, Never>?
    private var enqueuedCounts: [String: Int] = [:]

    public init(
        counter: any StepCounting, repository: any StepHistoryRepository,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current },
        automaticallyRefreshAtMidnight: Bool = true, historyDays: Int = 6,
        waitForMidnight: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(min(seconds, 172_800) * 1_000_000_000))
        }
    ) {
        self.counter = counter
        self.repository = repository
        self.now = now
        self.calendar = calendar
        self.automaticallyRefreshAtMidnight = automaticallyRefreshAtMidnight
        self.historyDays = min(6, max(0, historyDays))
        self.waitForMidnight = waitForMidnight
        state = DailyStepState(date: StepDay(containing: now(), calendar: calendar()).date)
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        await activate(StepDay(containing: now(), calendar: calendar()))
    }

    /// Called for calendar/time-zone changes. A new date starts a new range,
    /// even if the sensor has not emitted another event yet.
    public func refresh() async {
        guard isRunning else { return }
        let day = StepDay(containing: now(), calendar: calendar())
        if day != activeDay {
            await activate(day)
        } else if !state.isLoading {
            await queryToday(day, generation: generation)
            scheduleMidnight(for: day)
        }
    }

    public func stop() {
        isRunning = false
        generation += 1
        stopCounter()
        midnightTask?.cancel()
        historyTask?.cancel()
        update { $0.isTracking = false; $0.isLoading = false }
    }

    /// Finishes queued writes when the app backgrounds. On an I/O failure,
    /// saving the current total also retries the repository's dirty archive.
    public func flush() async {
        await saveTask?.value
        if state.hasStorageError {
            enqueueSave(DailyStepRecord(date: state.date, stepCount: state.stepCount))
            await saveTask?.value
        }
    }

    /// Useful to await historical recovery before reading a complete snapshot.
    public func finishHistoryRecovery() async {
        await historyTask?.value
        await flush()
    }

    private func activate(_ day: StepDay) async {
        generation += 1
        let token = generation
        stopCounter()
        midnightTask?.cancel()
        historyTask?.cancel()
        activeDay = day
        let retainedCount = state.date == day.date ? state.stepCount : 0
        update {
            $0.date = day.date
            $0.stepCount = retainedCount
            $0.isTracking = false
            $0.isLoading = true
            $0.error = nil
        }

        do {
            let stored = try await repository.record(for: day.date)
            guard isCurrent(day, token) else { return }
            if let stored {
                enqueuedCounts[day.date] = max(enqueuedCounts[day.date] ?? 0, stored.stepCount)
                update { $0.stepCount = max($0.stepCount, stored.stepCount) }
            }
        } catch {
            guard isCurrent(day, token) else { return }
            update { $0.hasStorageError = true }
        }
        guard isCurrent(day, token), !Task.isCancelled else { return }

        hasSubscription = true
        update { $0.isTracking = true }
        counter.startUpdates(from: day.start) { [weak self] result in
            guard let self, self.hasSubscription else { return }
            self.receive(result, day: day, generation: token)
        }
        scheduleMidnight(for: day)
        await queryToday(day, generation: token)
        if isCurrent(day, token) { recoverHistory(before: day) }
    }

    private func queryToday(_ day: StepDay, generation token: Int) async {
        guard isCurrent(day, token), queryingGeneration != token else { return }
        queryingGeneration = token
        update { $0.isLoading = true }
        defer {
            if queryingGeneration == token { queryingGeneration = nil }
            if isCurrent(day, token) { update { $0.isLoading = false } }
        }
        do {
            let count = try await counter.steps(from: day.start, to: min(now(), day.end))
            guard isCurrent(day, token), !Task.isCancelled else { return }
            receive(.success(count), day: day, generation: token)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(day, token), !Task.isCancelled else { return }
            // A historical-query failure must not stop a working live stream.
            update { $0.error = (error as? StepCountingError) ?? .updateFailed }
        }
    }

    private func receive(_ result: Result<Int, StepCountingError>, day: StepDay, generation token: Int) {
        guard isCurrent(day, token) else { return }
        guard StepDay(containing: now(), calendar: calendar()) == day else {
            Task { [weak self] in await self?.refresh() }
            return
        }
        switch result {
        case .success(let count):
            // Both CoreMotion query and live values are totals since midnight.
            // Merging by maximum handles replay and late queries without adding twice.
            let total = max(state.stepCount, max(0, count))
            update {
                $0.stepCount = total
                if hasSubscription { $0.error = nil }
            }
            enqueueSave(DailyStepRecord(date: day.date, stepCount: total))
        case .failure(let error):
            stopCounter()
            update { $0.isTracking = false; $0.error = error }
        }
    }

    private func recoverHistory(before day: StepDay) {
        guard historyDays > 0, lastRecoveredDay != day,
              !state.hasStorageError, state.error == nil else { return }
        let currentTime = now()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = self.calendar().timeZone
        let days = (1...historyDays).compactMap { offset -> StepDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day.start) else { return nil }
            let previous = StepDay(containing: date, calendar: calendar)
            // Do not label a clipped, partial CoreMotion window as a full day.
            return previous.start >= currentTime.addingTimeInterval(-7 * 86_400) ? previous : nil
        }
        historyTask = Task { [weak self, counter, repository] in
            var completed = true
            for previous in days {
                guard !Task.isCancelled else { return }
                let count: Int
                do {
                    count = max(0, try await counter.steps(from: previous.start, to: previous.end))
                } catch {
                    completed = false
                    continue
                }
                guard !Task.isCancelled else { return }
                do {
                    let stored = try await repository.record(for: previous.date)
                    guard !Task.isCancelled else { return }
                    self?.enqueueSave(DailyStepRecord(
                        date: previous.date, stepCount: max(stored?.stepCount ?? 0, count)
                    ))
                } catch {
                    completed = false
                    self?.update { $0.hasStorageError = true }
                }
            }
            if completed, !Task.isCancelled { self?.lastRecoveredDay = day }
        }
    }

    private func enqueueSave(_ record: DailyStepRecord) {
        let record = DailyStepRecord(
            date: record.date, stepCount: max(enqueuedCounts[record.date] ?? 0, record.stepCount)
        )
        guard enqueuedCounts[record.date] != record.stepCount || state.hasStorageError else { return }
        enqueuedCounts[record.date] = record.stepCount
        let previous = saveTask
        saveTask = Task { [weak self, repository] in
            await previous?.value
            do {
                try await repository.save(record)
                self?.update { $0.hasStorageError = false }
            } catch {
                self?.update { $0.hasStorageError = true }
            }
        }
    }

    private func scheduleMidnight(for day: StepDay) {
        midnightTask?.cancel()
        guard automaticallyRefreshAtMidnight, isRunning else { return }
        let delay = max(0.01, day.end.timeIntervalSince(now()))
        let token = generation
        midnightTask = Task { [weak self, waitForMidnight] in
            do { try await waitForMidnight(delay) }
            catch { return }
            guard let self, self.isCurrent(day, token), !Task.isCancelled else { return }
            self.midnightTask = nil
            await self.refresh()
        }
    }

    private func stopCounter() {
        guard hasSubscription else { return }
        hasSubscription = false
        counter.stopUpdates()
    }

    private func isCurrent(_ day: StepDay, _ token: Int) -> Bool {
        isRunning && generation == token && activeDay == day
    }

    private func update(_ change: (inout DailyStepState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        onStateChange?(next)
    }
}
