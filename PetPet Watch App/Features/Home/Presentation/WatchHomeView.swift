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
        case home, statistics, games, streak, chat
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                home.tag(WatchSection.home)
                PetOverviewView(viewModel: petViewModel, stepViewModel: viewModel, cloudViewModel: cloudViewModel)
                    .tag(WatchSection.statistics)
                if let games {
                    WatchGameOverview(services:games,pet:petViewModel).tag(WatchSection.games)
                }
                WatchStreakOverview(model: streakViewModel, cloud: cloudViewModel).tag(WatchSection.streak)
                if let games { WatchChatOverview(services: games).tag(WatchSection.chat) }
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
            let period = WatchAppearance.period(at: context.date)
            GeometryReader { geometry in
                ZStack {
                    Image(period.backgroundImageName)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    homeContents(period: period, canvas: geometry.size)
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

    private func homeContents(period: PetDaylightPeriod, canvas: CGSize) -> some View {
        // Android/Figma: wallpaper, a central pet and steps beneath it. The
        // watchOS clock stays in its system position; the Crown owns paging.
        let petWidth = min(canvas.width * 0.60, canvas.height * 0.53)
        let petHeight = petWidth * 336 / 256
        let touchWidth = max(44, canvas.width - 88)
        let textColor: Color = period.usesLightText ? .white : .black
        return ZStack {
            Button {
                guard character.handleTouch() else { return }
                Task { await petViewModel.touch() }
            } label: {
                WatchPetSpriteView(state: character.state, backgroundImageName: period.backgroundImageName,
                                   backgroundCanvas: canvas, backgroundCoordinateSpace: "pet.home")
                    .frame(width: petWidth, height: petHeight)
                    .frame(width: touchWidth, height: petHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(petViewModel.isBusy || petViewModel.progress == nil)
            .accessibilityLabel("펫 쓰다듬기")
            .accessibilityHint("크라운이나 양옆 화살표로 화면을 바꿀 수 있어요")
            .accessibilityIdentifier("watch.petTouch")
            .position(x: canvas.width / 2, y: canvas.height * 0.51)

            HStack(spacing: 0) {
                pageArrow("chevron.left", label: "이전 화면, 음성과 AI", id: "watch.previousPage") {
                    withAnimation { selectedSection = .chat }
                }
                Spacer(minLength: 0)
                pageArrow("chevron.right", label: "다음 화면, 상태", id: "watch.openPetStatistics") {
                    withAnimation { selectedSection = .statistics }
                }
            }
            .frame(width: canvas.width)
            .position(x: canvas.width / 2, y: canvas.height * 0.51)

            HStack(spacing: 0) {
                Group {
                    if viewModel.errorMessage != nil {
                        Button { showingStepError = true } label: {
                            Image(systemName: "exclamationmark.circle")
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain).foregroundStyle(textColor)
                            .accessibilityLabel("걸음수 권한 안내 및 다시 시도")
                            .accessibilityIdentifier("watch.retrySteps")
                    } else { Color.clear.accessibilityHidden(true) }
                }.frame(width: 44, height: 44)
                Text("\(WatchNumber.compact(Int64(viewModel.state.stepCount))) 걸음")
                    .font(.caption2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(textColor)
                    .accessibilityLabel("오늘 \(viewModel.state.stepCount.formatted())걸음")
                    .accessibilityIdentifier("watch.stepCount")
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .frame(width: canvas.width, height: 44)
            .position(x: canvas.width / 2, y: canvas.height - 24)
        }
    }

    private func pageArrow(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.bold()).foregroundStyle(.white)
                .shadow(color: .black, radius: 1.5)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
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
