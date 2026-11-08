import Combine
import SwiftUI
import PetPetCore

@MainActor final class PhoneExtrasModel: ObservableObject {
    var onSessionInvalidated: (() async -> Void)?
    @Published var question = ""
    @Published private(set) var progress = ChatProgress()
    @Published private(set) var ranking: GameRanking?
    @Published private(set) var rankMessage: String?
    @Published private(set) var rankingBusy = false
    @Published private(set) var chatting = false
    private let backend: BackendClient?
    private var accountID: String?
    private var rankTask: Task<Void,Never>?
    private var chatTask: Task<Void,Never>?
    private var rankRevision = UUID()
    private var chatRevision = UUID()
    init(backend: BackendClient?) { self.backend = backend }
    func setAccount(_ value: String?) {
        guard value != accountID else { return }
        stop(); ranking = nil; rankMessage = nil; progress = ChatProgress(); question = ""; accountID = value
    }
    func load(_ game: MiniGame) {
        rankTask?.cancel(); rankRevision = UUID()
        rankingBusy = false
        guard let backend, let accountID else { rankMessage = "로그인 후 랭킹을 확인할 수 있어요"; return }
        let revision = rankRevision
        ranking = nil; rankMessage = nil; rankingBusy = true
        rankTask = Task {
            defer { if revision == self.rankRevision { rankingBusy = false; rankTask = nil } }
            do {
                let value = try await backend.ranking(game,accountID:accountID)
                guard self.accountID == accountID, self.rankRevision == revision, !Task.isCancelled else { return }
                ranking = value
            } catch is CancellationError { }
            catch {
                if self.rankRevision == revision { rankMessage = (error as? BackendError ?? .network).localizedDescription }
                await notifySessionChange(expected: accountID)
            }
        }
    }
    func send() {
        guard !chatting, let backend, let accountID else { progress.fail("로그인 후 질문을 보낼 수 있어요"); return }
        let question = question.trimmingCharacters(in:.whitespacesAndNewlines)
        do { try ChatProgress.validate(question:question) } catch { progress.fail("질문을 1~2,000자로 입력해 주세요"); return }
        let revision = UUID(); chatRevision = revision
        chatting = true; progress = ChatProgress()
        chatTask = Task {
            defer { if self.chatRevision == revision { chatting = false; chatTask = nil } }
            do {
                try await backend.streamChat(question:question,accountID:accountID) { [weak self] event in
                    try await self?.receive(event,revision:revision,accountID:accountID)
                }
                if self.chatRevision == revision { progress.end() }
            } catch is CancellationError { }
            catch {
                if self.chatRevision == revision { progress.fail((error as? BackendError ?? .network).localizedDescription) }
                await notifySessionChange(expected: accountID)
            }
        }
    }
    private func receive(_ event: ChatStreamEvent, revision: UUID, accountID: String) throws {
        guard self.accountID == accountID, chatRevision == revision else { throw CancellationError() }
        try progress.receive(event)
    }
    private func notifySessionChange(expected accountID: String) async {
        do {
            if try await backend?.session()?.accountID != accountID { await onSessionInvalidated?() }
        } catch { }
    }
    func cancelChat() {
        let wasChatting = chatting
        chatTask?.cancel(); chatTask = nil; chatRevision = UUID(); chatting = false
        if wasChatting, !progress.finished { progress.fail("응답을 중단했어요") }
    }
    func stop() {
        cancelChat()
        rankTask?.cancel(); rankTask = nil; rankRevision = UUID(); rankingBusy = false
    }
}

struct PhoneExtrasView: View {
    @ObservedObject var model: PhoneExtrasModel
    let development: Bool
    @State private var game = MiniGame.shooting
    @FocusState private var questionFocused: Bool
    @Environment(\.scenePhase) private var phase
    var body: some View {
        List {
            if development { Text("개발 모의 랭킹·AI 응답 · 외부 전송 없음").font(.caption).foregroundStyle(.orange) }
            Section("게임 랭킹") {
                Picker("게임",selection:$game) { ForEach(MiniGame.allCases,id:\.self) { Text($0.title).tag($0) } }
                if model.rankingBusy { ProgressView() }
                if let ranking = model.ranking {
                    if ranking.entries.isEmpty { Text("등록된 기록이 없어요") }
                    ForEach(Array(ranking.entries.enumerated()),id:\.offset) { _,row in
                        HStack {
                            Text("\(row.rank)위").foregroundStyle(.secondary)
                            Text(row.name); Spacer()
                            VStack(alignment:.trailing) {
                                Text("\(row.score)\(game == .shooting ? "점" : "계단")")
                                if game == .starStair { Text("콤보 \(row.maxCombo)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if let message = model.rankMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button("랭킹 새로고침") { model.load(game) }.disabled(model.rankingBusy)
                Text("게임은 Apple Watch에서 플레이할 수 있어요.").font(.caption).foregroundStyle(.secondary)
            }
            Section("펫과 AI 대화") {
                TextField("질문을 입력해 주세요",text:$model.question,axis:.vertical).lineLimit(2...5).disabled(model.chatting).accessibilityIdentifier("chat.question")
                    .focused($questionFocused)
                Text("키보드의 마이크로도 입력할 수 있어요. 내용을 확인한 뒤 보내 주세요.").font(.caption).foregroundStyle(.secondary)
                Button("AI에 질문 보내기") { questionFocused = false; model.send() }.disabled(model.chatting || model.question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("chat.send")
                if model.chatting { ProgressView(); Button("응답 중단") { model.cancelChat() }.accessibilityIdentifier("chat.cancel") }
                Text(model.progress.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("chat.status")
                if !model.progress.text.isEmpty { Text(model.progress.text).textSelection(.enabled).accessibilityIdentifier("chat.answer") }
            }
        }.navigationTitle("게임과 대화")
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { questionFocused = false }.accessibilityIdentifier("chat.dismissKeyboard")
                }
            }
            .task { model.load(game) }
            .onChange(of:game) { _,value in model.load(value) }
            .onDisappear { model.stop() }
            .onChange(of:phase) { _,value in
                if value == .background { model.stop() }
                else if value == .active { model.load(game) }
            }
    }
}
