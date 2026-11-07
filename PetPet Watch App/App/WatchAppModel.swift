import Combine
import Foundation
import PetPetCore
import PetPetConnectivity

@MainActor
final class WatchAppModel: ObservableObject {
    let home: WatchHomeViewModel
    let pet: PetProgressViewModel
    let cloud: WatchCloudController
    private let sync: WatchSyncController
    private let transport: WatchConnectivityTransport

    init() {
        let environment = CloudEnvironment.current
        let root = URL.applicationSupportDirectory.appendingPathComponent("PetPet", isDirectory: true)
        let directory = environment.storageDirectory(in: root)
        #if DEBUG
        let game = FileGameRepository(developmentDirectory: directory, seedDirectory: root)
        #else
        let game = FileGameRepository(directory: directory)
        #endif
        let home = WatchHomeViewModel(stepCounter: CoreMotionStepCounter(), repository: game)
        let pet = PetProgressViewModel(repository: game, history: game)
        let transport = WatchConnectivityTransport(environment: environment)
        self.transport = transport
        self.home = home; self.pet = pet
        cloud = WatchCloudController(game: game, transport: transport, home: home, pet: pet, directory: directory, environment: environment)
        sync = WatchSyncController(home: home, pet: pet, history: game, progress: game,
                                   outboxURL: directory.appendingPathComponent("watch-sync-outbox-v1.json"), transport: transport)
    }

    func finishBackgroundTransfer() async {
        await transport.waitForPendingContent()
        await Task.yield()
        await cloud.finishWork()
    }
}
