import SwiftUI
import PetPetCore

@MainActor
struct WatchHomeView: View {
    @ObservedObject var viewModel: WatchHomeViewModel
    @ObservedObject var petViewModel: PetProgressViewModel
    @ObservedObject var cloudViewModel: WatchCloudController
    @ObservedObject var streakViewModel: WatchStreakViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var character = CharacterActivityViewModel()
    @State private var selectedSection: WatchSection = .home

    private enum WatchSection: Hashable {
        case home, statistics, food, streak, cloud
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                home.tag(WatchSection.home)
                PetOverviewView(viewModel: petViewModel)
                    .tag(WatchSection.statistics)
                FoodOverviewView(viewModel: petViewModel, stepViewModel: viewModel, cloudViewModel: cloudViewModel)
                    .tag(WatchSection.food)
                WatchStreakOverview(model: streakViewModel, cloud: cloudViewModel).tag(WatchSection.streak)
                VStack(spacing: 12) {
                    Label("계정과 백업", systemImage: "icloud").font(.headline)
                    Text(cloudViewModel.account?.displayName ?? "아이폰에서 로그인해 주세요")
                        .font(.caption).multilineTextAlignment(.center)
                    NavigationLink("백업 관리") { WatchCloudView(viewModel: cloudViewModel) }
                }
                .padding(.horizontal, 18)
                .tag(WatchSection.cloud)
            }
            // Keep pages short so the Crown always changes sections. Long
            // lists open on the navigation stack and receive Crown scrolling.
            .tabViewStyle(.verticalPage)
        }
        .onReceive(viewModel.$state) { character.observe($0) }
        .onChange(of: characterIsVisible, initial: true) { _, active in
            character.setActive(active, steps: viewModel.state)
        }
        .onChange(of: [reduceMotion, luminanceReduced, scenePhase == .active, selectedSection == .home], initial: true) { _, flags in
            AnimationDiagnostics.record(reduceMotion: flags[0], luminanceReduced: flags[1], sceneActive: flags[2], homeVisible: flags[3])
        }
        // Keep tracking alive while browsing the pet and food pages.
        .task {
            await cloudViewModel.start()
            guard scenePhase == .active else { return }
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
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60), by: 60)) { context in
            let period = PetDaylightPeriod(date: context.date)
            GeometryReader { geometry in
                ZStack {
                    Image(period.backgroundImageName)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    VStack(spacing: 4) {
                        Button {
                            guard character.handleTouch() else { return }
                            Task { await petViewModel.touch() }
                        } label: {
                            WatchPetSpriteView(state: character.state)
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
                            Button {
                                withAnimation { selectedSection = .statistics }
                            } label: {
                                Label("성장", systemImage: "chart.bar.fill")
                            }
                            .accessibilityIdentifier("watch.openPetStatistics")
                            Button {
                                withAnimation { selectedSection = .food }
                            } label: {
                                Label("먹이", systemImage: "carrot.fill")
                            }
                            .accessibilityIdentifier("watch.openFoodInventory")
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.8))
                        Text("크라운을 돌려 섹션 이동")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(period.usesLightText ? .white : .black)
                    .padding(.horizontal, 12)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var characterIsVisible: Bool { selectedSection == .home && scenePhase == .active && !luminanceReduced }

    private func stop() {
        viewModel.stop()
        petViewModel.stop()
        character.stop()
    }
}

#if DEBUG
#Preview {
    let history = PreviewStepHistoryRepository()
    let progress = FilePetProgressRepository(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("PetPetPreview-\(UUID().uuidString).json")
    )
    let home = WatchHomeViewModel(stepCounter: PreviewStepCounter(), repository: history)
    let pet = PetProgressViewModel(repository: progress, history: history)
    WatchHomeView(viewModel: home, petViewModel: pet, cloudViewModel: WatchCloudController(
        game: FileGameRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        transport: PreviewCloudTransport(), home: home, pet: pet, directory: FileManager.default.temporaryDirectory
    ), streakViewModel: WatchStreakViewModel(history: history, home: home))
}
#endif
