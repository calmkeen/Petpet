//
//  WatchHomeView.swift
//  PetPet Watch App
//
//  Created by calmkeen on 9/20/25.
//

import SwiftUI
import PetPetCore

@MainActor
struct WatchHomeView: View {
    @ObservedObject var viewModel: WatchHomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    
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
                    Text("오늘 \(viewModel.state.stepCount.formatted())걸음")
                        .foregroundColor(.black)
                        .accessibilityIdentifier("watch.stepCount")
                    if viewModel.state.isLoading {
                        ProgressView()
                    }
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
        .background(TransparentVideoOverlay())
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.start() }
            } else if phase == .background {
                viewModel.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
    }

}

#if DEBUG
#Preview {
    WatchHomeView(viewModel: WatchHomeViewModel(
        stepCounter: PreviewStepCounter(), repository: PreviewStepHistoryRepository()
    ))
}
#endif
