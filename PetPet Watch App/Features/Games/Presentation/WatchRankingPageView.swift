import SwiftUI
import PetPetCore

struct WatchRankingPageView: View {
    @StateObject private var model: WatchRankingPageModel
    let title: String
    init(kind: WatchRankingPageModel.Kind, client: WatchFeatureClient, cloud: WatchCloudController) {
        _model = StateObject(wrappedValue: WatchRankingPageModel(kind: kind, client: client, cloud: cloud))
        switch kind { case .steps: title = "누적 걸음수"; case let .game(game): title = game.title }
    }
    var body: some View {
        List {
            Section {
                Text("\(model.page)페이지").font(.headline).accessibilityIdentifier("rank.page")
                Button("새로고침") { model.load(model.page) }.disabled(model.busy).accessibilityIdentifier("rank.refresh")
                if model.busy { ProgressView("랭킹 불러오는 중") }
                if let error = model.error { Text(error).font(.caption).accessibilityIdentifier("rank.error") }
            }
            if let page = model.stepPage {
                Section("전체 \(page.totalUsers)명") {
                    if page.rankings.isEmpty { Text("이 구간에 기록이 없어요.") }
                    ForEach(page.rankings, id: \.userId) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.rank)위 · \(row.nickname)").lineLimit(2)
                            Text("\(row.totalStepCount.formatted()) 걸음").font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("rank.entry.\(row.userId)")
                    }
                }
                Text("서버에 백업된 걸음수의 누적 순위예요.").font(.caption2)
            }
            if let page = model.gamePage {
                Section("게임 랭킹") {
                    if page.entries.isEmpty { Text("이 구간에 기록이 없어요.") }
                    ForEach(page.entries, id: \.userID) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.rank)위 · \(row.name)").lineLimit(2)
                            Text("\(row.score)\(page.game == .shooting ? "점" : "계단")").font(.caption).foregroundStyle(.secondary)
                            if page.game == .starStair { Text("최대 콤보 \(row.maxCombo)").font(.caption2) }
                        }.accessibilityIdentifier("rank.entry.\(row.userID ?? 0)")
                    }
                }
            }
            Section("페이지 이동") {
                Button("이전 페이지") { model.load(model.page - 1) }.disabled(model.busy || model.page <= 1).accessibilityIdentifier("rank.previous")
                Button("다음 페이지") { model.load(model.page + 1) }.disabled(model.busy || !model.hasNext).accessibilityIdentifier("rank.next")
            }
        }.navigationTitle(title).task { model.load() }.onDisappear { model.stop() }
    }
}
