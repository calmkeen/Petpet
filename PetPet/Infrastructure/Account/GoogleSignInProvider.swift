import UIKit
import GoogleSignIn
import PetPetCore

struct AccountConfiguration {
    let baseURL: URL?
    let clientID: String
    let serverClientID: String
    let redirectScheme: String

    init(bundle: Bundle = .main) {
        baseURL = URL(string: bundle.object(forInfoDictionaryKey: "PetPetAPIBaseURL") as? String ?? "")
        clientID = bundle.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        serverClientID = bundle.object(forInfoDictionaryKey: "GIDServerClientID") as? String ?? ""
        redirectScheme = clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var canSignIn: Bool {
        guard baseURL?.scheme == "https", clientID.hasSuffix(".apps.googleusercontent.com"),
              serverClientID.hasSuffix(".apps.googleusercontent.com") else { return false }
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(redirectScheme) == true }
    }
}

@MainActor
final class GoogleSignInProvider {
    let configuration: AccountConfiguration
    init(configuration: AccountConfiguration) { self.configuration = configuration }

    func signIn() async throws -> GoogleIdentity {
        guard configuration.canSignIn else { throw BackendError.configurationMissing }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var presenter = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw BackendError.configurationMissing
        }
        while let next = presenter.presentedViewController { presenter = next }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID, serverClientID: configuration.serverClientID
        )
        let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error {
                    // GoogleSignIn 9's public kGIDSignInErrorCodeCanceled is -5.
                    if (error as NSError).domain == kGIDSignInErrorDomain && (error as NSError).code == -5 {
                        continuation.resume(throwing: CancellationError())
                    } else { continuation.resume(throwing: error) }
                } else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: BackendError.invalidResponse) }
            }
        }
        let user: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            result.user.refreshTokensIfNeeded { user, error in
                if let error { continuation.resume(throwing: error) }
                else if let user { continuation.resume(returning: user) }
                else { continuation.resume(throwing: BackendError.invalidResponse) }
            }
        }
        guard let subject = user.userID, !subject.isEmpty,
              let token = user.idToken?.tokenString, !token.isEmpty else { throw BackendError.invalidResponse }
        return GoogleIdentity(subject: subject, idToken: token, email: user.profile?.email, name: user.profile?.name)
    }

    func signOut() { GIDSignIn.sharedInstance.signOut() }
}
