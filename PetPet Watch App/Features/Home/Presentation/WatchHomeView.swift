import SwiftUI
import PetPetCore

@MainActor
struct WatchHomeView: View {
    @ObservedObject var viewModel: WatchHomeViewModel
    @ObservedObject var petViewModel: PetProgressViewModel
    @ObservedObject var cloudViewModel: WatchCloudController
    @ObservedObject var streakViewModel: WatchStreakViewModel
    var games: WatchGameServices?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var character = CharacterActivityViewModel()
    @State private var showingStepError = false
    @State private var selectedSection: WatchSection = .home

    private enum WatchSection: Hashable {
        case home, statistics, food, streak, games, chat, cloud
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
                if let games {
                    WatchGameOverview(services:games,pet:petViewModel).tag(WatchSection.games)
                    WatchChatOverview(services:games).tag(WatchSection.chat)
                }
                WatchCloudOverview(viewModel: cloudViewModel)
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
                    ViewThatFits(in: .vertical) {
                        homeContents(period: period, canvas: geometry.size, hint: true)
                        homeContents(period: period, canvas: geometry.size, hint: false)
                    }
                    .foregroundStyle(period.usesLightText ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.top, 32)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.coordinateSpace(name: "pet.home")
            }
        }
        .ignoresSafeArea()
        .alert("걸음수 확인", isPresented: $showingStepError) {
            Button("다시 시도") { Task { await viewModel.refresh() } }
            Button("닫기", role: .cancel) { }
        } message: { Text(viewModel.errorMessage ?? "걸음수를 다시 불러와 주세요.") }
    }

    private func homeContents(period: PetDaylightPeriod, canvas: CGSize, hint: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                VStack(spacing: 0) {
                    Button {
                        guard character.handleTouch() else { return }
                        Task { await petViewModel.touch() }
                    } label: {
                        WatchPetSpriteView(state: character.state, backgroundImageName: period.backgroundImageName,
                                           backgroundCanvas: canvas, backgroundCoordinateSpace: "pet.home")
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain).contentShape(Rectangle())
                    .disabled(petViewModel.isBusy || petViewModel.progress == nil)
                    .accessibilityLabel("펫 쓰다듬기").accessibilityIdentifier("watch.petTouch")
                    if let progress = petViewModel.progress {
                        Text("Lv.\(WatchNumber.compact(progress.pet.level))").font(.caption2.bold()).lineLimit(1).accessibilityLabel("레벨 \(progress.pet.level)")
                        Text(progress.pet.mood.shortName).font(.caption2).lineLimit(1)
                            .accessibilityLabel(progress.pet.mood.displayName)
                    }
                }
                VStack(spacing: 0) {
                    Text("오늘").font(.caption2)
                    Text(WatchNumber.compact(Int64(viewModel.state.stepCount)))
                        .font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityLabel("오늘 \(viewModel.state.stepCount.formatted())걸음")
                        .accessibilityIdentifier("watch.stepCount")
                    if viewModel.errorMessage != nil {
                        Button { showingStepError = true } label: { Text("확인").font(.caption2) }
                            .buttonStyle(WatchActionStyle(color: .black, backgroundOpacity: 0.7))
                            .accessibilityLabel("걸음수 권한 안내 및 다시 시도")
                            .accessibilityIdentifier("watch.retrySteps")
                    } else if viewModel.state.isLoading {
                        ProgressView().accessibilityLabel("걸음수 불러오는 중")
                    } else {
                        Text("걸음").font(.caption2)
                    }
                }.frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Button { withAnimation { selectedSection = .statistics } } label: { Text("성장") }
                    .accessibilityIdentifier("watch.openPetStatistics")
                Button { withAnimation { selectedSection = .food } } label: { Text("먹이") }
                    .accessibilityIdentifier("watch.openFoodInventory")
            }
            .buttonStyle(WatchActionStyle(color: .black, backgroundOpacity: 0.7))
            if hint { Text("크라운으로 이동").font(.caption2) }
        }
        .fixedSize(horizontal: false, vertical: true)

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
