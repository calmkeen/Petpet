import Combine
import Foundation
import PetPetCore
import PetPetConnectivity

@MainActor
final class PhoneAppModel: ObservableObject {
    let home: PhoneHomeViewModel
    let account: AccountViewModel
    private let transport: WatchConnectivityTransport

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PetPet", isDirectory: true)
        let transport = WatchConnectivityTransport()
        self.transport = transport
        let receiver = PhoneSnapshotReceiver(
            repository: FilePhoneSnapshotRepository(fileURL: directory.appendingPathComponent("watch-snapshot-v1.json")),
            transport: transport
        )
        home = PhoneHomeViewModel(receiver: receiver)
        let configuration = AccountConfiguration()
        let backend = configuration.baseURL.flatMap { url in
            try? BackendClient(baseURL: url, store: KeychainSessionStore(serverOrigin: url.absoluteString))
        }
        let cloud = backend.map { client in
            PhoneCloudCoordinator(backend: client, transport: transport,
                receipts: FileCloudReceiptStore(fileURL: directory.appendingPathComponent("cloud-receipts-v1.json")),
                directory: directory.appendingPathComponent("CloudOutbox", isDirectory: true))
        }
        let account = AccountViewModel(backend: backend, cloud: cloud, configuration: configuration)
        self.account = account
        let snapshotConnection = transport.onConnectionChange
        transport.onConnectionChange = { [weak account] connection in
            snapshotConnection?(connection)
            if connection.isActivated { Task { await account?.connectionChanged() } }
        }
        Task { [home] in await home.start(); await account.start() }
    }
}
