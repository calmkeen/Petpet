import SwiftUI
import PetPetCore

@MainActor
struct WatchHomeView: View {
    @ObservedObject var viewModel: WatchHomeViewModel
    @ObservedObject var petViewModel: PetProgressViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            home
        }
        // Keep tracking alive while browsing the pet and food pages.
        .task {
            await petViewModel.start()
            await viewModel.start()
        }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await petViewModel.start()
                    await viewModel.start()
                }
            } else if phase == .background {
                stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
    }

    private var home: some View {
        GeometryReader { geometry in
            ZStack {
                Image("background")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                VStack(spacing: 4) {
                    Button {
                        Task { await petViewModel.touch() }
                    } label: {
                        Image("snowfox_baby_sitting")
                            .resizable().scaledToFit()
                            .frame(height: min(90, geometry.size.height * 0.38))
                    }
                    .buttonStyle(.plain)
                    .disabled(petViewModel.isBusy || petViewModel.progress == nil)
                    .accessibilityLabel("펫 쓰다듬기")
                    .accessibilityIdentifier("watch.petTouch")
                    if let progress = petViewModel.progress {
                        Text("Lv.\(progress.pet.level) · \(progress.pet.mood.displayName)")
                            .font(.caption2)
                    }
                    Text("오늘 \(viewModel.state.stepCount.formatted())걸음")
                        .font(.headline).monospacedDigit()
                        .accessibilityIdentifier("watch.stepCount")
                    if viewModel.state.isLoading { ProgressView() }
                    if let message = viewModel.errorMessage {
                        Text(message).font(.caption2).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 8) {
                        NavigationLink {
                            PetStatisticsView(viewModel: petViewModel)
                        } label: {
                            Label("성장", systemImage: "chart.bar.fill")
                        }
                        .accessibilityIdentifier("watch.openPetStatistics")
                        NavigationLink {
                            FoodInventoryView(viewModel: petViewModel, stepViewModel: viewModel)
                        } label: {
                            Label("먹이", systemImage: "carrot.fill")
                        }
                        .accessibilityIdentifier("watch.openFoodInventory")
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.8))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func stop() {
        viewModel.stop()
        petViewModel.stop()
    }
}

#if DEBUG
#Preview {
    let history = PreviewStepHistoryRepository()
    let progress = FilePetProgressRepository(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("PetPetPreview-\(UUID().uuidString).json")
    )
    WatchHomeView(
        viewModel: WatchHomeViewModel(stepCounter: PreviewStepCounter(), repository: history),
        petViewModel: PetProgressViewModel(repository: progress, history: history)
    )
}
#endif
