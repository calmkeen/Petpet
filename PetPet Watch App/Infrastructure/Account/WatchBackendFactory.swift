import Foundation
import PetPetCore

@MainActor enum WatchBackendFactory {
    static func make(directory: URL, game: FileGameRepository, environment: CloudEnvironment) -> WatchStandaloneService? {
        let client: BackendClient?
        #if DEBUG
        let url = LocalDevelopmentBackend.baseURL
        client = try? BackendClient(baseURL: url,
            transport: LocalDevelopmentBackend(fileURL: directory.appendingPathComponent("standalone-mock-backend-v1.json")),
            store: WatchKeychainSessionStore(serverOrigin: url.absoluteString))
        #else
        let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "PetPetAPIBaseURL") as? String ?? "")
        client = url.flatMap { try? BackendClient(baseURL: $0, store: WatchKeychainSessionStore(serverOrigin: $0.absoluteString)) }
        #endif
        return client.map { WatchStandaloneService(backend: $0, game: game,
            receipts: FileCloudReceiptStore(fileURL: directory.appendingPathComponent("standalone-receipts-v1.json")),
            modeURL: directory.appendingPathComponent("standalone-mode-v1.json"), environment: environment) }
    }
}
