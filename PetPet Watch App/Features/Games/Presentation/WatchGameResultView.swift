import SwiftUI
import PetPetCore

struct WatchGameResultView: View {
    @ObservedObject var model: WatchGameResultModel
    let replay: (() -> Void)?
    var refresh: (() -> Void)? = nil
    var body: some View {
        List {
            if let score = model.score {
                Section("게임 결과") {
                    Text("\(score.score)\(score.game == .shooting ? "점" : "계단")").font(.title2.bold()).monospacedDigit().accessibilityIdentifier("game.finalScore")
                    if score.game == .starStair { Text("최대 콤보 \(score.maxCombo)").accessibilityIdentifier("game.maxCombo") }
                    if let best = model.best { Text("최고 기록 \(best.score)").font(.caption).accessibilityIdentifier("game.bestScore") }
                }
            }
            if model.busy { ProgressView("랭킹 확인 중") }
            if let message = model.message {
                Text(message).font(.caption2).accessibilityIdentifier("game.feedback")
                if model.canRetry { Button("저장·랭킹 다시 시도") { model.retry() }.accessibilityIdentifier("game.retry") }
            }
            if let replay { Button("다시 하기", action: replay).accessibilityIdentifier("game.replay") }
            if let refresh { Button("랭킹 새로고침", action: refresh).disabled(model.busy).accessibilityIdentifier("game.refreshRanking") }
            if let ranking = model.ranking {
                Section("TOP 10") {
                    if let position = ranking.position { Text("이번 기록 \(position)위").foregroundStyle(.yellow).accessibilityIdentifier("game.position") }
                    if ranking.entries.isEmpty { Text("등록된 기록이 없어요") }
                    ForEach(Array(ranking.entries.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(row.rank)위 · \(row.name)").fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("game.rankName.\(row.userID.map(String.init) ?? "place\(row.rank)")")
                            Text("\(row.score)\(ranking.game == .shooting ? "점" : "계단")\(ranking.game == .starStair ? " · 콤보 \(row.maxCombo)" : "")")
                                .font(.caption2).foregroundStyle(.secondary)
                                .accessibilityIdentifier("game.rankScore.\(row.userID.map(String.init) ?? "place\(row.rank)")")
                        }
                    }
                }
            }

        }
        .accessibilityIdentifier("game.result")
    }
}
