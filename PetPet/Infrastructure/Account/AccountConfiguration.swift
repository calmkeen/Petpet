import Foundation

struct AccountConfiguration {
    let baseURL: URL?

    init(bundle: Bundle = .main) {
        baseURL = URL(string: bundle.object(forInfoDictionaryKey: "PetPetAPIBaseURL") as? String ?? "")
    }

    var canSignIn: Bool {
        guard let baseURL else { return false }
        return baseURL.scheme == "https" && baseURL.host != nil && baseURL.user == nil
            && baseURL.password == nil && baseURL.query == nil && baseURL.fragment == nil
    }
}
