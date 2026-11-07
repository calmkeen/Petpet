import Foundation

/// Persist revision before handing a snapshot to the system. The same identity
/// survives relaunches, so delayed packets cannot roll the phone back.
public actor FileWatchSnapshotOutbox {
    private let fileURL: URL
    private var cached: WatchSnapshot?
    private var didLoad = false

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func prepare(steps: [DailyStepRecord], progress: PetProgress, at date: Date) throws -> WatchSnapshot {
        try loadIfNeeded()
        let previousRevision = cached?.revision ?? 0
        guard previousRevision < Int64.max else { throw SnapshotSyncError.revisionOverflow }
        let snapshot = WatchSnapshot(
            sourceID: cached?.sourceID ?? UUID(), revision: previousRevision + 1,
            generatedAt: date,
            steps: Array(steps.sorted { $0.date > $1.date }.prefix(WatchSnapshotCodec.maximumStepDays)),
            pet: progress.pet, inventory: progress.inventory
        )
        let data = try WatchSnapshotCodec.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        cached = snapshot
        return snapshot
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            cached = try WatchSnapshotCodec.decode(Data(contentsOf: fileURL))
        }
        didLoad = true
    }
}
