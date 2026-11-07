import Foundation

public struct CloudAccount: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
}

public struct WatchBackupExport: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let storeID: UUID
    public let sequence: Int64
    public let accountID: String
    public let capturedAt: Date
    public let timeZoneIdentifier: String
    public let backupDay: String
    public let pet: PetProfile
    public let steps: [DailyStepRecord]

    public func request() throws -> ServerBackupRequest {
        guard let zone = TimeZone(identifier: timeZoneIdentifier), !steps.isEmpty else { throw BackendError.invalidResponse }
        return try ServerBackupRequest(pet: pet, steps: steps, timeZone: zone)
    }
}

public struct CloudBackupReceipt: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let storeID: UUID
    public let accountID: String
    public let completedAt: Date
    public let sequence: Int64
    public init(export: WatchBackupExport, completedAt: Date) {
        operationID = export.operationID; storeID = export.storeID
        accountID = export.accountID; self.completedAt = completedAt
        sequence = export.sequence
    }
}

public struct WatchRestoreChallenge: Codable, Equatable, Sendable {
    public let storeID: UUID
    public let ownerID: String?
    public let pet: PetProfile
}

public struct WatchRestoreImport: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let target: WatchRestoreChallenge
    public let state: ServerRestoreState
    public init(operationID: UUID = UUID(), target: WatchRestoreChallenge, state: ServerRestoreState) {
        self.operationID = operationID; self.target = target; self.state = state
    }
}

public enum CloudControl: Codable, Sendable {
    case account(CloudAccount?)
    case exportRequested(operationID: UUID, account: CloudAccount)
    case backupSucceeded(CloudBackupReceipt)
    case backupApplied(operationID: UUID, storeID: UUID)
    case restoreApplied(operationID: UUID, storeID: UUID)
    case failed(operationID: UUID, reason: String)
}

public enum CloudFile: Codable, Sendable {
    case backup(WatchBackupExport)
    case restore(WatchRestoreImport)
}

public enum CloudWire {
    private struct Envelope<Value: Codable>: Codable {
        var version = 1
        var value: Value
    }
    public static let maximumFileBytes = 16 * 1_024 * 1_024
    public static func encodeControl(_ value: CloudControl) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(value: value))
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        return data
    }
    public static func decodeControl(_ data: Data) throws -> CloudControl {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let value = try JSONDecoder().decode(Envelope<CloudControl>.self, from: data)
        guard value.version == 1 else { throw BackendError.invalidResponse }
        return value.value
    }
    public static func encodeFile(_ value: CloudFile) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(value: value))
        guard data.count <= maximumFileBytes else { throw BackendError.transferTooLarge }
        return data
    }
    public static func decodeFile(_ data: Data) throws -> CloudFile {
        guard data.count <= maximumFileBytes else { throw BackendError.transferTooLarge }
        let value = try JSONDecoder().decode(Envelope<CloudFile>.self, from: data)
        guard value.version == 1 else { throw BackendError.invalidResponse }
        return value.value
    }
}

@MainActor
public protocol CloudTransport: AnyObject {
    var connection: SnapshotConnection { get }
    var onCloudControl: ((Data) -> Void)? { get set }
    var onCloudFile: ((URL) -> Void)? { get set }
    var onCloudChallenge: (() async throws -> Data)? { get set }
    var onCloudTransferError: ((String?) -> Void)? { get set }
    func enqueueCloudControl(_ data: Data) throws
    func enqueueCloudFile(_ url: URL) throws
    func requestCloudChallenge() async throws -> Data
}
