import SwiftUI
import PetPetCore

struct PhoneRankingPageView: View {
    @StateObject private var model: PhoneRankingPageModel
    let title: String
    init(kind: PhoneRankingPageModel.Kind, account: AccountViewModel) {
        _model = StateObject(wrappedValue: account.makeRankingModel(kind))
        switch kind { case .steps: title = "누적 걸음수 랭킹"; case let .game(game): title = game.title + " 랭킹" }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    HStack {
                        Text("\(model.page)페이지").font(.headline).accessibilityIdentifier("phone.rankPage")
                        Spacer()
                        Button { model.load(model.page) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(PhoneIconStyle()).disabled(model.busy || model.accountID == nil)
                            .accessibilityLabel("랭킹 새로고침").accessibilityIdentifier("phone.rankPageRefresh")
                    }.id("rank.top")
                    if model.busy { ProgressView("랭킹 불러오는 중") }
                    if let error = model.error { Text(error).font(.callout).accessibilityIdentifier("phone.rankPageError") }
                }
                if let value = model.stepPage {
                    Section("전체 \(value.totalUsers)명") {
                        if value.rankings.isEmpty { Text("이 구간에 기록이 없어요.") }
                        ForEach(value.rankings, id: \.userId) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(row.rank)위 · \(row.nickname)").font(.headline).fixedSize(horizontal: false, vertical: true)
                                Text("\(row.totalStepCount.formatted()) 걸음").font(.title3).monospacedDigit().foregroundStyle(PhoneDesign.accent)
                            }.padding(.vertical, 6).accessibilityIdentifier("phone.rankEntry.\(row.userId)")
                        }
                    }
                    Text("서버에 백업된 걸음수의 누적 순위예요.").font(.footnote).foregroundStyle(.secondary)
                }
                if let value = model.gamePage {
                    Section("게임 랭킹") {
                        if value.entries.isEmpty { Text("이 구간에 기록이 없어요.") }
                        ForEach(value.entries, id: \.userID) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(row.rank)위 · \(row.name)").font(.headline).fixedSize(horizontal: false, vertical: true)
                                Text("\(row.score)\(value.game == .shooting ? "점" : "계단")").font(.title3).monospacedDigit()
                                if value.game == .starStair { Text("최대 콤보 \(row.maxCombo)").font(.subheadline).foregroundStyle(.secondary) }
                            }.padding(.vertical, 6).accessibilityIdentifier("phone.rankEntry.\(row.userID ?? 0)")
                        }
                    }
                }
                Section("페이지 이동") {
                    Text("\(model.page)페이지 · 5명씩").font(.footnote).foregroundStyle(.secondary)
                    Button("이전 페이지") { model.load(model.page - 1) }.buttonStyle(PhoneActionStyle())
                        .disabled(model.busy || model.page <= 1).accessibilityIdentifier("phone.rankPrevious")
                    Button("다음 페이지") { model.load(model.page + 1) }.buttonStyle(PhoneActionStyle())
                        .disabled(model.busy || !model.hasNext).accessibilityIdentifier("phone.rankNext")
                }
            }
            .task(id: model.page) {
                try? await Task.sleep(for: .milliseconds(120)); guard !Task.isCancelled else { return }
                proxy.scrollTo("rank.top", anchor: .top)
            }
            .onChange(of: model.error) { _, value in if value != nil { proxy.scrollTo("rank.top", anchor: .top) } }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .tint(PhoneDesign.accent).task(id: model.accountID) { model.load() }.onDisappear { model.stop() }
    }
}
