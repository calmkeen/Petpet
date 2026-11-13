import SwiftUI

@main
@MainActor
struct PetPetWatchApp: App {
    @StateObject private var model: WatchAppModel
    #if DEBUG
    @State private var previewing = ProcessInfo.processInfo.arguments.contains("--pet-animation-preview")
    #endif

    init() {
        let model = WatchAppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
          Group {
            #if DEBUG
            if previewing {
                NavigationStack {
                    WatchAnimationPreview().toolbar { Button("홈") { previewing = false } }
                }
            } else {
                WatchHomeView(viewModel: model.home, petViewModel: model.pet, cloudViewModel: model.cloud, streakViewModel: model.streak,
                              customization: model.customization, games:model.games)
            }
            #else
            WatchHomeView(viewModel: model.home, petViewModel: model.pet, cloudViewModel: model.cloud, streakViewModel: model.streak,
                          customization: model.customization, games:model.games)
            #endif
          }
          #if DEBUG
          .transformEnvironment(\.dynamicTypeSize) { size in
              if ProcessInfo.processInfo.arguments.contains("--watch-ui-large-text") { size = .xxxLarge }
          }
          #endif
        }
        .backgroundTask(.watchConnectivity) { await model.finishBackgroundTransfer() }
    }
}
