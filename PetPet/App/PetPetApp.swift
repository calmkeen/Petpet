//
//  PetPetApp.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import PetPetCore
import PetPetConnectivity

@main
@MainActor
struct PetPetApp: App {
    @StateObject private var homeViewModel: PhoneHomeViewModel

    init() {
        let repository = FilePhoneSnapshotRepository(
            fileURL: URL.applicationSupportDirectory.appendingPathComponent("PetPet", isDirectory: true)
                .appendingPathComponent("watch-snapshot-v1.json")
        )
        let receiver = PhoneSnapshotReceiver(repository: repository, transport: WatchConnectivityTransport())
        let home = PhoneHomeViewModel(receiver: receiver)
        _homeViewModel = StateObject(wrappedValue: home)
        // WCSession must also activate when the system launches us for a
        // background delivery, before a phone screen has appeared.
        Task { await home.start() }
    }

    var body: some Scene {
        WindowGroup {
            PhoneHomeView(viewModel: homeViewModel)
        }
    }
}
