import Foundation
import PetPetCore

struct AccountConfiguration {
    let baseURL: URL?
    let environment = CloudEnvironment.current
    var isDevelopment: Bool { environment == .development }

    init(bundle: Bundle = .main) {
        #if DEBUG
        baseURL = LocalDevelopmentBackend.baseURL
        #else
        baseURL = URL(string: bundle.object(forInfoDictionaryKey: "PetPetAPIBaseURL") as? String ?? "")
        #endif
    }

    var canSignIn: Bool {
        guard let baseURL else { return false }
        return baseURL.scheme == "https" && baseURL.host != nil && baseURL.user == nil
            && baseURL.password == nil && baseURL.query == nil && baseURL.fragment == nil
    }
}
