import SwiftUI
import PetPetCore

struct WatchGameOverview: View {
    let services: WatchGameServices
    @ObservedObject var pet: PetProgressViewModel
    var body: some View {
        VStack(spacing: 10) {
            Label("펫과 놀기", systemImage: "gamecontroller.fill").font(.headline)
            Image("stepmate_game_shootinggame_icon").resizable().scaledToFit().frame(width: 70, height: 70).clipShape(Circle())
            NavigationLink("게임 선택") { WatchGameLibraryView(services: services, pet: pet) }
                .accessibilityIdentifier("watch.openGames")
            Text("게임 2종 · 최고 기록 · 랭킹").font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 16)
    }
}
struct WatchGameLibraryView: View {
    let services: WatchGameServices
    @ObservedObject var pet: PetProgressViewModel
    var body: some View {
        List {
            if services.cloud.isDevelopment { Text("개발 모의 랭킹").font(.caption2).foregroundStyle(.orange) }
            NavigationLink { WatchShootingGameView(pet: pet.progress?.pet, services: services) } label: {
                Label { Text("지구를 지켜라") } icon: { Image("stepmate_game_shootinggame_icon").resizable().scaledToFit().frame(width: 28,height: 28) }
            }.disabled(pet.progress == nil).accessibilityIdentifier("game.openShooting")
            NavigationLink { WatchStarStairView(services: services) } label: {
                Label { Text("별계단 훈련") } icon: { Image("stepmate_game_starstairgame_icon_color").resizable().scaledToFit().frame(width: 28,height: 28) }
            }.accessibilityIdentifier("game.openStairs")
            ForEach(MiniGame.allCases, id: \.self) { game in
                NavigationLink("\(game.title) 랭킹") { WatchLeaderboardView(game: game, services: services) }
                    .accessibilityIdentifier("game.openRanking.\(game.rawValue)")
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
