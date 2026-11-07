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
        var version: Int
        var environment: CloudEnvironment?
        var value: Value
        init(value: Value, environment: CloudEnvironment) {
            self.value = value; self.environment = environment
            version = environment == .development ? 2 : 1
        }
    }
    public static let maximumFileBytes = 16 * 1_024 * 1_024
    public static func encodeControl(_ value: CloudControl, environment: CloudEnvironment = .production) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(value: value, environment: environment))
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        return data
    }
    public static func decodeControl(_ data: Data, environment: CloudEnvironment = .production) throws -> CloudControl {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let value = try JSONDecoder().decode(Envelope<CloudControl>.self, from: data)
        try validate(version: value.version, environment: value.environment, expected: environment)
        return value.value
    }
    public static func encodeFile(_ value: CloudFile, environment: CloudEnvironment = .production) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(value: value, environment: environment))
        guard data.count <= maximumFileBytes else { throw BackendError.transferTooLarge }
        return data
    }
    public static func decodeFile(_ data: Data, environment: CloudEnvironment = .production) throws -> CloudFile {
        guard data.count <= maximumFileBytes else { throw BackendError.transferTooLarge }
        let value = try JSONDecoder().decode(Envelope<CloudFile>.self, from: data)
        try validate(version: value.version, environment: value.environment, expected: environment)
        return value.value
    }

    public static func encodeChallenge(_ value: WatchRestoreChallenge, environment: CloudEnvironment) throws -> Data {
        try JSONEncoder().encode(Envelope(value: value, environment: environment))
    }

    public static func decodeChallenge(_ data: Data, environment: CloudEnvironment) throws -> WatchRestoreChallenge {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        if let value = try? JSONDecoder().decode(Envelope<WatchRestoreChallenge>.self, from: data) {
            try validate(version: value.version, environment: value.environment, expected: environment)
            return value.value
        }
        // Older production builds returned a bare challenge. Development must
        // never accept it, since it could refer to the production game store.
        guard environment == .production else { throw BackendError.environmentMismatch }
        return try JSONDecoder().decode(WatchRestoreChallenge.self, from: data)
    }

    public static func encodeProfileRequest(_ value: NicknameRequest, environment: CloudEnvironment) throws -> Data {
        try encodeProfile(value, environment: environment)
    }
    public static func decodeProfileRequest(_ data: Data, environment: CloudEnvironment) throws -> NicknameRequest {
        try decodeProfile(data, environment: environment)
    }
    public static func encodeProfileReply(_ value: NicknameReply, environment: CloudEnvironment) throws -> Data {
        try encodeProfile(value, environment: environment)
    }
    public static func decodeProfileReply(_ data: Data, environment: CloudEnvironment) throws -> NicknameReply {
        try decodeProfile(data, environment: environment)
    }
    private static func encodeProfile<Value: Codable>(_ value: Value, environment: CloudEnvironment) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(value: value, environment: environment))
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        return data
    }
    private static func decodeProfile<Value: Codable>(_ data: Data, environment: CloudEnvironment) throws -> Value {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let decoded = try JSONDecoder().decode(Envelope<Value>.self, from: data)
        try validate(version: decoded.version, environment: decoded.environment, expected: environment)
        return decoded.value
    }

    private static func validate(version: Int, environment: CloudEnvironment?, expected: CloudEnvironment) throws {
        guard (environment ?? .production) == expected else { throw BackendError.environmentMismatch }
        guard version == (expected == .development ? 2 : 1) else { throw BackendError.invalidResponse }
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
    var onProfileRequest: ((Data) async throws -> Data)? { get set }
    func requestProfile(_ data: Data) async throws -> Data
}

extension CloudTransport {
    public var onProfileRequest: ((Data) async throws -> Data)? { get { nil } set {} }
    public func requestProfile(_ data: Data) async throws -> Data { throw BackendError.watchUnavailable }
}
