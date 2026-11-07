//
//  PetPetWatchApp.swift
//  PetPet Watch App
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import Foundation
import PetPetCore

@main
@MainActor
struct PetPetWatchApp: App {
    @StateObject private var homeViewModel: WatchHomeViewModel

    init() {
        let historyURL = URL.applicationSupportDirectory
            .appendingPathComponent("PetPet", isDirectory: true)
            .appendingPathComponent("step-history-v1.json")
        let history = FileStepHistoryRepository(fileURL: historyURL)
        _homeViewModel = StateObject(
            wrappedValue: WatchHomeViewModel(stepCounter: CoreMotionStepCounter(), repository: history)
        )
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(viewModel: homeViewModel)
        }
    }
}
