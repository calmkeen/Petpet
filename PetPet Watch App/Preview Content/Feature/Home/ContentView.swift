//
//  ContentView.swift
//  PetPet Watch App
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = UserMotionCheckManager()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack{
                Image("background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                VStack {
                    Text(Date(), style: .time)
                        .foregroundColor(.black)
                    Image("snowfox_baby_sitting")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Text("Step Count: \(motionManager.steps)")
                        .foregroundColor(.black)
                        
                }
                .padding()
            }
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
        .background(OverlayPlayerForTimeRemove())
        .onAppear {
            motionManager.startPedometerUpdates()
        }
        .onDisappear {
            motionManager.stopPedometerUpdates()
        }
    }

}

#Preview {
    ContentView()
}
