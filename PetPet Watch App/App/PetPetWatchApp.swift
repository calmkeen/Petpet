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
    @StateObject private var syncController: WatchSyncController

    init() {
        let historyURL = URL.applicationSupportDirectory
            .appendingPathComponent("PetPet", isDirectory: true)
            .appendingPathComponent("step-history-v1.json")
        let history = FileStepHistoryRepository(fileURL: historyURL)
        let progress = FilePetProgressRepository(
            fileURL: historyURL.deletingLastPathComponent()
                .appendingPathComponent("pet-progress-v1.json")
        )
        let home = WatchHomeViewModel(stepCounter: CoreMotionStepCounter(), repository: history)
        let pet = PetProgressViewModel(repository: progress, history: history)
        _homeViewModel = StateObject(wrappedValue: home)
        _petViewModel = StateObject(wrappedValue: pet)
        let sync = WatchSyncController(
            home: home, pet: pet, history: history, progress: progress,
            outboxURL: historyURL.deletingLastPathComponent().appendingPathComponent("watch-sync-outbox-v1.json")
        )
        _syncController = StateObject(wrappedValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(viewModel: homeViewModel, petViewModel: petViewModel)
                .environmentObject(syncController)
        }
    }
}
