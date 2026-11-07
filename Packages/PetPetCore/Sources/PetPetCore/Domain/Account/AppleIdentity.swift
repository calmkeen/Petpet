import Foundation

public enum IdentityProvider: String, Codable, Sendable {
    case apple, google
}

/// Short-lived credentials for one server exchange. Never persist or send to the watch.
public struct AppleIdentity: Sendable, CustomStringConvertible {
    public let userIdentifier: String
    public let identityToken: String
    public let authorizationCode: String
    public let rawNonce: String
    public let name: String?
    public var description: String { "AppleIdentity(credentials: redacted)" }

    public init(userIdentifier: String, identityToken: String, authorizationCode: String,
                rawNonce: String, name: String? = nil) {
        self.userIdentifier = userIdentifier; self.identityToken = identityToken
        self.authorizationCode = authorizationCode; self.rawNonce = rawNonce; self.name = name
    }
}

/// Binds a native authorization callback to the request that initiated it.
public struct AppleSignInAttempt: Sendable {
    public let rawNonce: String
    public let state: String
    private let createdAt: Date

    public init(rawNonce: String, state: String, createdAt: Date = Date()) {
        self.rawNonce = rawNonce; self.state = state; self.createdAt = createdAt
    }

    public func validate(returnedState: String?, at date: Date = Date()) throws {
        guard !state.isEmpty, !rawNonce.isEmpty, returnedState == state else { throw BackendError.invalidAppleCredential }
        let age = date.timeIntervalSince(createdAt)
        guard age >= 0, age < 300 else { throw BackendError.operationExpired }
    }
}

struct AppleLoginRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let userIdentifier: String
    let name: String?

    init(_ identity: AppleIdentity) {
        identityToken = identity.identityToken; authorizationCode = identity.authorizationCode
        rawNonce = identity.rawNonce; userIdentifier = identity.userIdentifier; name = identity.name
    }
}
