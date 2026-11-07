import Foundation

public actor FilePhoneSnapshotRepository: PhoneSnapshotRepository {
    private struct Archive: Codable {
        var version: Int
        var cached: CachedWatchSnapshot
        var retiredSources: Set<UUID>
    }

    private let fileURL: URL
    private var archive: Archive?
    private var didLoad = false

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> CachedWatchSnapshot? {
        try loadIfNeeded()
        return archive?.cached
    }

    public func accept(_ snapshot: WatchSnapshot, from peerID: String, at date: Date) throws -> CachedWatchSnapshot {
        try WatchSnapshotCodec.validate(snapshot)
        guard !peerID.isEmpty else { throw SnapshotSyncError.invalidSnapshot }
        try loadIfNeeded()
        var retired = archive?.cached.peerID == peerID ? archive?.retiredSources ?? [] : []
        if let old = archive?.cached, old.peerID == peerID {
            if snapshot.sourceID == old.snapshot.sourceID {
                guard snapshot.revision > old.snapshot.revision else { return old }
            } else {
                guard !retired.contains(snapshot.sourceID) else { return old }
                retired.insert(old.snapshot.sourceID)
            }
        }
        let cached = CachedWatchSnapshot(snapshot: snapshot, receivedAt: date, peerID: peerID)
        let next = Archive(version: 1, cached: cached, retiredSources: retired)
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        archive = next
        return cached
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let loaded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard loaded.version == 1 else { throw SnapshotSyncError.unsupportedVersion(loaded.version) }
            try WatchSnapshotCodec.validate(loaded.cached.snapshot)
            guard !loaded.cached.peerID.isEmpty else { throw SnapshotSyncError.invalidSnapshot }
            archive = loaded
        }
        didLoad = true
    }
}
