import AuthenticationServices
import CryptoKit
import Foundation
import Security
import PetPetCore

@MainActor
final class WatchAppleSignInProvider {
    private let provider = ASAuthorizationAppleIDProvider()
    private let defaults: UserDefaults
    private let profileKey = "PetPet.watch.apple.pendingNames.v1"
    private var attempt: AppleSignInAttempt?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func configure(_ request: ASAuthorizationAppleIDRequest) throws {
        attempt = nil
        let attempt = AppleSignInAttempt(rawNonce: try randomValue(), state: try randomValue())
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(attempt.rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
        request.state = attempt.state
        self.attempt = attempt
    }

    func identity(from result: Result<ASAuthorization, Error>) throws -> AppleIdentity {
        defer { attempt = nil }
        let authorization: ASAuthorization
        do { authorization = try result.get() }
        catch let error as ASAuthorizationError where error.code == .canceled { throw CancellationError() }
        catch { throw WatchAppleAuthorizationError.failed }
        guard let attempt, let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw BackendError.invalidAppleCredential
        }
        try attempt.validate(returnedState: credential.state)
        guard !credential.user.isEmpty,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8), !token.isEmpty,
              let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
            throw BackendError.invalidAppleCredential
        }

        // Apple supplies the name only on first authorization. Preserve just
        // that profile field locally until the backend confirms the exchange.
        var names = defaults.dictionary(forKey: profileKey) as? [String: String] ?? [:]
        if let components = credential.fullName {
            let name = PersonNameComponentsFormatter().string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[credential.user] = name; defaults.set(names, forKey: profileKey) }
        }
        return AppleIdentity(userIdentifier: credential.user, identityToken: token,
                             authorizationCode: code, rawNonce: attempt.rawNonce, name: names[credential.user])
    }

    func confirmProfile(for userIdentifier: String) {
        var names = defaults.dictionary(forKey: profileKey) as? [String: String] ?? [:]
        names.removeValue(forKey: userIdentifier)
        defaults.set(names, forKey: profileKey)
    }

    func credentialIsAuthorized(for userIdentifier: String) async throws -> Bool {
        let state: ASAuthorizationAppleIDProvider.CredentialState = try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userIdentifier) { state, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: state) }
            }
        }
        switch state {
        case .authorized: return true
        case .revoked, .notFound, .transferred: return false
        @unknown default: throw WatchAppleAuthorizationError.failed
        }
    }

    private func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WatchAppleAuthorizationError.failed
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum WatchAppleAuthorizationError: LocalizedError {
    case failed
    var errorDescription: String? { "Apple 로그인을 완료하지 못했어요. Apple 계정과 앱의 로그인 설정을 확인해 주세요." }
}
