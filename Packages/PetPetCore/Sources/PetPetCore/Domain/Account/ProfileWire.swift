import Foundation

public struct NicknameRequest: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case check, update }
    public let id: UUID
    public let accountID: String
    public let action: Action
    public let nickname: String
    public init(id: UUID = UUID(), accountID: String, action: Action, nickname: String) {
        self.id = id; self.accountID = accountID; self.action = action; self.nickname = nickname
    }
}

public enum ProfileFailure: String, Codable, Sendable {
    case authenticationRequired, sessionChanged, unavailable, tooShort, tooLong, storage, invalidResponse, network
    public init(_ error: Error) {
        switch error as? BackendError {
        case .authenticationRequired: self = .authenticationRequired
        case .sessionChanged: self = .sessionChanged
        case .nicknameUnavailable: self = .unavailable
        case .nicknameTooShort: self = .tooShort
        case .nicknameTooLong: self = .tooLong
        case .storage: self = .storage
        case .invalidResponse: self = .invalidResponse
        default: self = .network
        }
    }
    public var error: BackendError {
        switch self {
        case .authenticationRequired: .authenticationRequired
        case .sessionChanged: .sessionChanged
        case .unavailable: .nicknameUnavailable
        case .tooShort: .nicknameTooShort
        case .tooLong: .nicknameTooLong
        case .storage: .storage
        case .invalidResponse: .invalidResponse
        case .network: .network
        }
    }
}

public struct NicknameReply: Codable, Sendable {
    public enum Result: Codable, Sendable {
        case availability(Bool)
        case updated(String)
        case failure(ProfileFailure)
    }
    public let id: UUID
    public let accountID: String
    public let result: Result
    public init(request: NicknameRequest, result: Result) {
        id = request.id; accountID = request.accountID; self.result = result
    }
}
