import Foundation

/// A read-only projection. Reward ledgers, credentials and local tap counters
/// stay on the watch; the phone never writes into the watch's game aggregate.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var environment: CloudEnvironment?
    public var resolvedEnvironment: CloudEnvironment { environment ?? .production }
    public var sourceID: UUID
    public var revision: Int64
    public var generatedAt: Date
    public var steps: [DailyStepRecord]
    public var pet: PetProfile
    public var inventory: [FoodInventoryItem]
    public var customization: PetCustomization?
    public var resolvedCustomization: PetCustomization { customization ?? .default }

    public init(sourceID: UUID, revision: Int64, generatedAt: Date,
                steps: [DailyStepRecord], pet: PetProfile, inventory: [FoodInventoryItem], environment: CloudEnvironment = .production,
                customization: PetCustomization? = nil) {
        version = environment == .development ? 2 : 1
        self.environment = environment == .development ? environment : nil
        self.sourceID = sourceID
        self.revision = revision
        self.generatedAt = generatedAt
        self.steps = steps
        self.pet = pet
        self.inventory = inventory
        self.customization = customization
    }
}

public enum SnapshotSyncError: Error, Equatable {
    case invalidSnapshot, unsupportedVersion(Int), payloadTooLarge, revisionOverflow
    case notActivated, notReachable, counterpartUnavailable, transferFailed
}

public enum WatchSnapshotCodec {
    public static let maximumStepDays = 7
    public static let maximumBytes = 60_000

    public static func encode(_ value: WatchSnapshot) throws -> Data {
        try validate(value)
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw SnapshotSyncError.payloadTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> WatchSnapshot {
        guard data.count <= maximumBytes else { throw SnapshotSyncError.payloadTooLarge }
        let value = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        try validate(value)
        return value
    }

    public static func validate(_ value: WatchSnapshot) throws {
        do { try value.customization?.validate() } catch { throw SnapshotSyncError.invalidSnapshot }
        guard (value.version == 1 && value.resolvedEnvironment == .production)
                || (value.version == 2 && value.environment == .development) else {
            throw SnapshotSyncError.unsupportedVersion(value.version)
        }
        let pet = value.pet
        guard value.revision > 0, value.generatedAt.timeIntervalSince1970.isFinite,
              value.steps.count <= maximumStepDays,
              value.steps.allSatisfy({ StepDateKey.isValid($0.date) && $0.stepCount >= 0 }),
              Set(value.steps.map(\.date)).count == value.steps.count,
              pet.id == 1, pet.level > 0, pet.level <= Int64.max / 2,
              pet.experience >= 0, pet.experience < pet.level * 2,
              [pet.affection, pet.attack, pet.defense, pet.health, pet.statPoints].allSatisfy({ $0 >= 0 }),
              value.inventory.allSatisfy({
                  $0.id == $0.foodID && FoodCatalog.food(id: $0.foodID) != nil && $0.quantity > 0
              }), Set(value.inventory.map(\.foodID)).count == value.inventory.count else {
            throw SnapshotSyncError.invalidSnapshot
        }
    }
}

public struct CachedWatchSnapshot: Codable, Equatable, Sendable {
    public let snapshot: WatchSnapshot
    public let receivedAt: Date
    public let peerID: String

    public init(snapshot: WatchSnapshot, receivedAt: Date, peerID: String) {
        self.snapshot = snapshot
        self.receivedAt = receivedAt
        self.peerID = peerID
    }

    public func steps(on date: Date, calendar: Calendar = .current) -> DailyStepRecord? {
        let key = StepDay(containing: date, calendar: calendar).date
        return snapshot.steps.first { $0.date == key }
    }
}

public protocol PhoneSnapshotRepository: Sendable {
    func load() async throws -> CachedWatchSnapshot?
    func accept(_ snapshot: WatchSnapshot, from peerID: String, at date: Date) async throws -> CachedWatchSnapshot
}
