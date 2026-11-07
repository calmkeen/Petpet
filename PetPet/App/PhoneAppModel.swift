import Combine
import Foundation
import PetPetCore
import PetPetConnectivity

@MainActor
final class PhoneAppModel: ObservableObject {
    let home: PhoneHomeViewModel
    let account: AccountViewModel
    let streak: PhoneStreakViewModel
    private let transport: WatchConnectivityTransport

    init() {
        let configuration = AccountConfiguration()
        let root = URL.applicationSupportDirectory.appendingPathComponent("PetPet", isDirectory: true)
        let directory = configuration.environment.storageDirectory(in: root)
        let transport = WatchConnectivityTransport(environment: configuration.environment)
        self.transport = transport
        let receiver = PhoneSnapshotReceiver(
            repository: FilePhoneSnapshotRepository(fileURL: directory.appendingPathComponent("watch-snapshot-v1.json")),
            transport: transport
        )
        home = PhoneHomeViewModel(receiver: receiver)
        let backend = configuration.baseURL.flatMap { url in
            #if DEBUG
            return try? BackendClient(baseURL: url,
                transport: LocalDevelopmentBackend(fileURL: directory.appendingPathComponent("mock-backend-v1.json")),
                store: KeychainSessionStore(serverOrigin: url.absoluteString))
            #else
            try? BackendClient(baseURL: url, store: KeychainSessionStore(serverOrigin: url.absoluteString))
            #endif
        }
        let cloud = backend.map { client in
            PhoneCloudCoordinator(backend: client, transport: transport,
                receipts: FileCloudReceiptStore(fileURL: directory.appendingPathComponent("cloud-receipts-v1.json")),
                directory: directory.appendingPathComponent("CloudOutbox", isDirectory: true), environment: configuration.environment)
        }
        let profile = backend.map { PhoneProfileCoordinator(backend: $0, transport: transport, environment: configuration.environment) }
        streak = PhoneStreakViewModel(backend: backend, cache: FileAccountStepCache(fileURL: directory.appendingPathComponent("server-streak-v1.json")))
        let account = AccountViewModel(backend: backend, cloud: cloud, profile: profile, configuration: configuration)
        self.account = account
        let snapshotConnection = transport.onConnectionChange
        transport.onConnectionChange = { [weak account] connection in
            snapshotConnection?(connection)
            if connection.isActivated { Task { await account?.connectionChanged() } }
        }
        Task { [home] in await home.start(); await account.start(); await account.refreshProfile() }
    }
}
