import SwiftUI

@main
@MainActor
struct PetPetWatchApp: App {
    @StateObject private var model: WatchAppModel

    init() {
        let model = WatchAppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(viewModel: model.home, petViewModel: model.pet, cloudViewModel: model.cloud, streakViewModel: model.streak)
        }
        .backgroundTask(.watchConnectivity) { await model.finishBackgroundTransfer() }
    }
}
