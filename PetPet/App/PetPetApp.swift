//
//  PetPetApp.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import GoogleSignIn

@main
@MainActor
struct PetPetApp: App {
    @StateObject private var model: PhoneAppModel

    init() {
        let model = PhoneAppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            PhoneHomeView(viewModel: model.home, accountViewModel: model.account)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
