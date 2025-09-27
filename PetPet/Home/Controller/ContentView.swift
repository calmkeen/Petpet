    //
//  ContentView.swift
//  PetPet
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import CoreMotion

struct ContentView: View {
    
    var stepCount = ""
    var motionStatus = ""
    var body: some View {
        ZStack{
            VStack {
                Text(Date(), style: .time)
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Step Count: \(Int.random(in: 0...1000000))")
            }
            .padding()
        }

    }
}

#Preview {
    ContentView()
}
