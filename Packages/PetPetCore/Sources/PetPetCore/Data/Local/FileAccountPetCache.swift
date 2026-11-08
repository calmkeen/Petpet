import Foundation

public struct CachedServerPet: Codable, Equatable, Sendable {
    public let accountID: String
    public let pet: PetProfile
    public let fetchedAt: Date

    public init(accountID: String, pet: PetProfile, fetchedAt: Date) {
        self.accountID = accountID; self.pet = pet; self.fetchedAt = fetchedAt
    }
}

/// A regeneratable, account-scoped display cache. It never writes to the watch aggregate.
public actor FileAccountPetCache {
    private struct Archive: Codable { let version: Int; let value: CachedServerPet }
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load(accountID: String) throws -> CachedServerPet? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else { throw BackendError.storage }
        guard archive.value.accountID == accountID else { return nil }
        try validate(archive.value)
        return archive.value
    }

    @discardableResult
    public func save(_ pet: PetProfile, accountID: String, at date: Date) throws -> CachedServerPet {
        let value = CachedServerPet(accountID: accountID, pet: pet, fetchedAt: date)
        try validate(value)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Archive(version: 1, value: value)).write(to: fileURL, options: .atomic)
        return value
    }

    private func validate(_ value: CachedServerPet) throws {
        guard !value.accountID.isEmpty, value.fetchedAt.timeIntervalSince1970.isFinite else { throw BackendError.invalidResponse }
        try ServerRestoreState.validate(pet: value.pet, steps: [])
    }
}
