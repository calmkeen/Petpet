import Foundation

@MainActor
public final class WatchSnapshotPublisher {
    private let history: any StepHistoryRepository
    private let progress: any PetProgressRepository
    private let outbox: FileWatchSnapshotOutbox
    private let transport: any SnapshotTransport
    private let beforeReading: () async throws -> Void
    private let now: () -> Date
    private var tail: Task<WatchSnapshot, Error>?

    public init(history: any StepHistoryRepository, progress: any PetProgressRepository,
                outbox: FileWatchSnapshotOutbox, transport: any SnapshotTransport,
                beforeReading: @escaping () async throws -> Void = {}, now: @escaping () -> Date = { Date() }) {
        self.history = history
        self.progress = progress
        self.outbox = outbox
        self.transport = transport
        self.beforeReading = beforeReading
        self.now = now
    }

    /// Serialize assembly and sending, not just revision allocation. Otherwise
    /// an older task could overwrite the system's newest application context.
    @discardableResult
    public func publish() async throws -> WatchSnapshot {
        let previous = tail
        let task = Task { [history, progress, outbox, transport, beforeReading, now] in
            _ = try? await previous?.value
            try await beforeReading()
            let steps = try await history.allRecords()
            let pet = try await progress.load()
            let snapshot = try await outbox.prepare(steps: steps, progress: pet, at: now())
            if transport.connection.isActivated {
                try transport.publish(WatchSnapshotCodec.encode(snapshot))
            }
            return snapshot
        }
        tail = task
        return try await task.value
    }
}
