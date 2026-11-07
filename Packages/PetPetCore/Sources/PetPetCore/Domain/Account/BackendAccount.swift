import Foundation

public struct GoogleIdentity: Sendable {
    public let subject: String
    public let idToken: String
    public let email: String?
    public let name: String?

    public init(subject: String, idToken: String, email: String?, name: String?) {
        self.subject = subject; self.idToken = idToken; self.email = email; self.name = name
    }
}

public struct BackendSession: Codable, Equatable, Sendable, CustomStringConvertible {
    public let accountID: String
    public let serverOrigin: String
    public let accessToken: String
    public let refreshToken: String?
    public let email: String?
    public let name: String?
    public let nickname: String?
    public let selectedMateID: Int64
    public let isNewUser: Bool
    public let identityProvider: IdentityProvider?
    public let providerSubject: String?
    public var description: String { "BackendSession(credentials: redacted)" }

    public init(accountID: String, serverOrigin: String, accessToken: String, refreshToken: String?,
                email: String?, name: String?, nickname: String?, selectedMateID: Int64 = 1, isNewUser: Bool = false,
                identityProvider: IdentityProvider? = nil, providerSubject: String? = nil) {
        self.accountID = accountID; self.serverOrigin = serverOrigin
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.email = email; self.name = name; self.nickname = nickname
        self.selectedMateID = selectedMateID; self.isNewUser = isNewUser
        self.identityProvider = identityProvider; self.providerSubject = providerSubject
    }
}

public protocol BackendSessionStore: Sendable {
    func load() async throws -> BackendSession?
    func save(_ session: BackendSession) async throws
    func clear() async throws
}

public enum BackendError: Error, Equatable, Sendable {
    case configurationMissing, invalidServerURL, invalidResponse, authenticationRequired
    case sessionChanged, unsupportedMate, accountMismatch, localStateChanged
    case http(Int), network, storage, watchUnavailable, transferTooLarge, operationExpired
    case invalidAppleCredential, appleLoginUnavailable
}
