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
    @Published private(set) var accountID: String?
    var isSignedIn: Bool { accountID != nil }
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
    var account: AccountViewModel? = nil
    private enum Pane: Hashable { case rankings, chat }
    @State private var pane: Pane = .rankings
    @State private var game = MiniGame.shooting
    @State private var editingQuestion = false
    @State private var questionDraft = ""
    @FocusState private var questionFocused: Bool
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                paneButton("랭킹", target: .rankings, id: "phone.showRankings")
                paneButton("대화", target: .chat, id: "phone.showChat")
            }.padding(.horizontal, 16).padding(.vertical, 8)
            if pane == .rankings { rankings } else { conversation }
        }
        .background(PhoneDesign.background).tint(PhoneDesign.accent)
        .navigationTitle("게임과 대화").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $editingQuestion) { questionEditor }
        .task(id: pane) {
            model.stop()
            if pane == .rankings { model.load(game) }
        }
        .onChange(of: game) { _, value in if pane == .rankings { model.load(value) } }
        .onChange(of: model.accountID) { _, _ in
            questionFocused = false; editingQuestion = false; questionDraft = ""
            if pane == .rankings { model.load(game) }
        }
        .onDisappear { model.stop() }
        .onChange(of: phase) { _, value in
            if value == .background { model.stop() }
            else if value == .active && pane == .rankings { model.load(game) }
        }
    }

    private func paneButton(_ title: String, target: Pane, id: String) -> some View {
        Button(title) { pane = target }
            .buttonStyle(PhoneSectionSwitchStyle(selected: pane == target))
            .accessibilityAddTraits(pane == target ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private var rankings: some View {
        List {
            if !model.isSignedIn {
                Text("홈의 계정·백업에서 로그인하면 랭킹을 확인할 수 있어요.")
                    .font(.callout).accessibilityIdentifier("phone.rankingLoginNotice")
            }
            Section("게임 선택") {
                Picker("게임", selection: $game) {
                    ForEach(MiniGame.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(minHeight: 44).accessibilityLabel("게임 선택")
                .accessibilityIdentifier("phone.rankGame")
            }
            Section {
                if model.rankingBusy { ProgressView("랭킹 확인 중") }
                if let ranking = model.ranking {
                    if ranking.entries.isEmpty { Text("등록된 기록이 없어요") }
                    ForEach(Array(ranking.entries.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(row.rank)위").font(.caption).foregroundStyle(PhoneDesign.accent)
                                Text(row.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("phone.rankName.\(row.userID.map(String.init) ?? "place\(row.rank)")")
                            }
                            Text("\(row.score)\(game == .shooting ? "점" : "계단")")
                                .font(.title3.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("phone.rankScore.\(row.userID.map(String.init) ?? "place\(row.rank)")")
                            if game == .starStair { Text("콤보 \(row.maxCombo)").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                }
                if let message = model.rankMessage, model.isSignedIn { Text(message).font(.callout).foregroundStyle(.secondary) }
                Button("랭킹 새로고침") { model.load(game) }.buttonStyle(PhoneActionStyle())
                    .disabled(model.rankingBusy || !model.isSignedIn).accessibilityIdentifier("phone.refreshRanking")
            } header: { Text("TOP 10") } footer: { Text("게임은 Apple Watch에서 플레이할 수 있어요.") }
            if let account {
                Section("전체 랭킹") {
                    NavigationLink("\(game.title) · 구간 랭킹") { PhoneRankingPageView(kind: .game(game), account: account) }
                        .accessibilityIdentifier("phone.openGameRange")
                }
            }
            if development { Text("Debug · 개발 모의 랭킹").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var conversation: some View {
        ScrollViewReader { scroll in
            List {
                if !model.isSignedIn {
                    Text("홈의 계정·백업에서 로그인하면 AI 대화를 사용할 수 있어요.")
                        .font(.callout).accessibilityIdentifier("phone.chatLoginNotice")
                }
                Section {
                    Button { questionDraft = model.question; editingQuestion = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("질문 작성·수정", systemImage: "square.and.pencil").font(.caption).foregroundStyle(PhoneDesign.accent)
                            Text(model.question.isEmpty ? "질문을 입력해 주세요" : model.question)
                                .foregroundStyle(model.question.isEmpty ? .secondary : .primary).lineLimit(3)
                        }.padding(.vertical, 4)
                    }.disabled(model.chatting || !model.isSignedIn).accessibilityIdentifier("chat.editQuestion")
                    Button("질문 보내기") { model.send() }.buttonStyle(PhoneActionStyle())
                        .disabled(model.chatting || !model.isSignedIn || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("chat.send")
                } header: { Text("질문") } footer: { Text("키보드의 마이크로도 입력할 수 있어요. 내용을 확인한 뒤 보내 주세요.") }
                Section("답변") {
                    Text(model.progress.status).font(.callout).foregroundStyle(model.progress.failed ? .orange : .secondary)
                        .accessibilityIdentifier("chat.status")
                    if model.chatting {
                        Button("응답 중단") { model.cancelChat() }.buttonStyle(PhoneActionStyle())
                            .accessibilityIdentifier("chat.cancel").id("phone.chat.cancellation")
                        ProgressView()
                    }
                    if !model.progress.text.isEmpty {
                        Text(model.progress.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .accessibilityIdentifier("chat.answer")
                    }
                }
                if development { Text("Debug · 모의 AI 응답 · 외부 전송 없음").font(.caption).foregroundStyle(.secondary) }
            }
            .task(id: model.chatting) {
                guard model.chatting else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, model.chatting else { return }
                withAnimation { scroll.scrollTo("phone.chat.cancellation", anchor: .center) }
            }
        }
    }

    private var questionEditor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $questionDraft).font(.body)
                    .padding(8).scrollContentBackground(.hidden)
                    .background(PhoneDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("질문을 입력해 주세요").accessibilityIdentifier("chat.question")
                    .focused($questionFocused)
                Text("\(questionDraft.count.formatted()) / 2,000자")
                    .font(.footnote).foregroundStyle(questionDraft.count > 2000 ? .orange : .secondary)
                    .accessibilityIdentifier("chat.characterCount")
            }
            .padding(16).background(PhoneDesign.background)
            .navigationTitle("질문 작성").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { questionFocused = false; editingQuestion = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(PhoneIconStyle()).accessibilityLabel("취소").accessibilityIdentifier("chat.cancelEditing")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { model.question = questionDraft; questionFocused = false; editingQuestion = false } label: { Image(systemName: "checkmark") }
                        .buttonStyle(PhoneIconStyle()).accessibilityLabel("완료").disabled(questionDraft.count > 2000)
                        .accessibilityIdentifier("chat.dismissKeyboard")
                }
            }
            .task { questionFocused = true }
        }.tint(PhoneDesign.accent)
    }
}
