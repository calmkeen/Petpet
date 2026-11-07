import Foundation

/// Persist a successful server response before queueing its watch receipt.
/// Replaying a file/receipt after an app restart must not upload old state or
/// award food twice. Credentials never enter this journal.
public actor FileCloudReceiptStore {
    private struct Archive: Codable {
        var version = 1
        var receipts: [String: CloudBackupReceipt] = [:]
        var acknowledged: Set<UUID> = []
        var sequences: [String: Int64] = [:]
        var restores: [String: WatchRestoreImport] = [:]
    }
    private let fileURL: URL
    private var cached: Archive?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func pending() throws -> [CloudBackupReceipt] {
        try load()
        return cached!.receipts.values.filter { !cached!.acknowledged.contains($0.operationID) }
    }
    public func receipt(operationID: UUID) throws -> CloudBackupReceipt? {
        try load(); return cached!.receipts[operationID.uuidString]
    }
    public func latestSequence(accountID: String, storeID: UUID) throws -> Int64 {
        try load(); return cached!.sequences[accountID + "/" + storeID.uuidString] ?? 0
    }
    public func lastBackupAt(accountID: String) throws -> Date? {
        try load()
        return cached!.receipts.values.filter { $0.accountID == accountID }.map(\.completedAt).max()
    }
    public func save(_ receipt: CloudBackupReceipt) throws {
        try load()
        var next = cached!
        if let old = next.receipts[receipt.operationID.uuidString] {
            guard old == receipt else { throw BackendError.invalidResponse }
            return
        }
        next.receipts[receipt.operationID.uuidString] = receipt
        let key = receipt.accountID + "/" + receipt.storeID.uuidString
        next.sequences[key] = max(next.sequences[key] ?? 0, receipt.sequence)
        try write(next)
    }
    public func acknowledge(operationID: UUID, storeID: UUID) throws {
        try load()
        guard cached!.receipts[operationID.uuidString]?.storeID == storeID else { return }
        var next = cached!
        next.acknowledged.insert(operationID)
        try write(next)
    }
    public func pendingRestores(accountID: String) throws -> [WatchRestoreImport] {
        try load(); return cached!.restores.values.filter { $0.state.accountID == accountID }
    }
    public func saveRestore(_ command: WatchRestoreImport) throws {
        try load()
        var next = cached!
        next.restores[command.operationID.uuidString] = command
        try write(next)
    }
    public func completeRestore(operationID: UUID, storeID: UUID? = nil) throws {
        try load()
        guard let command = cached!.restores[operationID.uuidString],
              storeID == nil || command.target.storeID == storeID else { return }
        var next = cached!
        next.restores.removeValue(forKey: operationID.uuidString)
        try write(next)
    }
    private func load() throws {
        guard cached == nil else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1 else { throw BackendError.invalidResponse }
            cached = archive
        } else { cached = Archive() }
    }
    private func write(_ value: Archive) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
        cached = value
    }
}
