import Foundation

public actor FileAccountStepCache {
    private struct Archive: Codable { let version: Int; let accountID: String; let records: [DailyStepRecord] }
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load(accountID: String) throws -> [DailyStepRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else { throw BackendError.storage }
        guard archive.accountID == accountID else { return [] }
        try ServerRestoreState.validate(pet: PetProgress.newUser(at: Date()).pet, steps: archive.records)
        return archive.records
    }
    public func save(_ records: [DailyStepRecord], accountID: String) throws {
        try ServerRestoreState.validate(pet: PetProgress.newUser(at: Date()).pet, steps: records)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Archive(version: 1, accountID: accountID, records: records)).write(to: fileURL, options: .atomic)
    }
}
