//
//  PetPetApp.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI

@main
@MainActor
struct PetPetApp: App {
    @StateObject private var homeViewModel = PhoneHomeViewModel()

    var body: some Scene {
        WindowGroup {
            PhoneHomeView(viewModel: homeViewModel)
        }
    }
}
