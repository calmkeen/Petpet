//
//  PhoneHomeView.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI

@MainActor
struct PhoneHomeView: View {
    @ObservedObject var viewModel: PhoneHomeViewModel
    var body: some View {
        ZStack{
            VStack {
                Text(Date(), style: .time)
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Step Count: \(viewModel.stepCountText)")
                    .accessibilityIdentifier("phone.stepCount")
            }
            .padding()
        }

    }
}
