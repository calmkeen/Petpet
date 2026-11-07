//
//  PetPetApp.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import AuthenticationServices

@main
@MainActor
struct PetPetApp: App {
    @StateObject private var model: PhoneAppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = PhoneAppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            PhoneHomeView(viewModel: model.home, accountViewModel: model.account)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.account.checkAppleCredential() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                    Task { await model.account.checkAppleCredential() }
                }
        }
    }
}
