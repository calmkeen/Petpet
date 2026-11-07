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
    @StateObject private var petViewModel: PetProgressViewModel

    init() {
        let historyURL = URL.applicationSupportDirectory
            .appendingPathComponent("PetPet", isDirectory: true)
            .appendingPathComponent("step-history-v1.json")
        let history = FileStepHistoryRepository(fileURL: historyURL)
        let progress = FilePetProgressRepository(
            fileURL: historyURL.deletingLastPathComponent()
                .appendingPathComponent("pet-progress-v1.json")
        )
        _homeViewModel = StateObject(
            wrappedValue: WatchHomeViewModel(stepCounter: CoreMotionStepCounter(), repository: history)
        )
        _petViewModel = StateObject(
            wrappedValue: PetProgressViewModel(repository: progress, history: history)
        )
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(viewModel: homeViewModel, petViewModel: petViewModel)
        }
    }
}
