import SwiftUI
import PetPetCore

struct WatchGameOverview: View {
    let services: WatchGameServices
    @ObservedObject var pet: PetProgressViewModel
    var body: some View {
        WatchOverviewLayout { compact in
          VStack(spacing: 6) {
            Label("펫과 놀기", systemImage: "gamecontroller.fill").font(.headline)
            Image("stepmate_game_shootinggame_icon").resizable().scaledToFit().frame(width: compact ? 52 : 64, height: compact ? 52 : 64).clipShape(Circle())
            NavigationLink("게임 선택") { WatchGameLibraryView(services: services, pet: pet) }
                .buttonStyle(WatchActionStyle())
                .accessibilityIdentifier("watch.openGames")
            if !compact { Text("게임 2종 · 최고 기록 · 랭킹").font(.caption2).foregroundStyle(.secondary) }
          }
        }
    }
}
struct WatchGameLibraryView: View {
    let services: WatchGameServices
    @ObservedObject var pet: PetProgressViewModel
    var body: some View {
        List {
            Section("게임 선택") {
            NavigationLink { WatchShootingGameView(pet: pet.progress?.pet, services: services) } label: {
                Label { Text("지구를 지켜라").fixedSize(horizontal: false, vertical: true) } icon: { Image("stepmate_game_shootinggame_icon").resizable().scaledToFit().frame(width: 28,height: 28) }
            }.disabled(pet.progress == nil).accessibilityIdentifier("game.openShooting")
            NavigationLink { WatchStarStairView(services: services) } label: {
                Label { Text("별계단 훈련").fixedSize(horizontal: false, vertical: true) } icon: { Image("stepmate_game_starstairgame_icon_color").resizable().scaledToFit().frame(width: 28,height: 28) }
            }.accessibilityIdentifier("game.openStairs")
            }
            Section {
            ForEach(MiniGame.allCases, id: \.self) { game in
                NavigationLink { WatchLeaderboardView(game: game, services: services) } label: { Text(game.title).fixedSize(horizontal: false, vertical: true) }
                    .accessibilityIdentifier("game.openRanking.\(game.rawValue)")
                NavigationLink("\(game.title) · 구간 랭킹") { WatchRankingPageView(kind: .game(game), client: services.client, cloud: services.cloud) }
                    .accessibilityIdentifier("game.openRange.\(game.rawValue)")
            }
            } header: { Text("랭킹") } footer: {
                if services.cloud.isDevelopment { Text("Debug · 개발 모의 랭킹") }
            }
        }.navigationTitle("게임")
    }
}
private struct WatchLeaderboardView: View {
    let game: MiniGame
    @StateObject private var model: WatchGameResultModel
    init(game: MiniGame, services: WatchGameServices) { self.game = game; _model = StateObject(wrappedValue: WatchGameResultModel(services: services)) }
    var body: some View {
        WatchGameResultView(model: model, replay: nil, refresh: { model.loadRanking(game) })
            .navigationTitle("랭킹").task { model.loadRanking(game) }
            .onDisappear { model.stop() }
    }
}
