import Combine
import SwiftUI
import WatchKit
import PetPetCore

@MainActor final class WatchChatViewModel: ObservableObject {
    @Published var question = ""
    @Published private(set) var progress = ChatProgress()
    @Published private(set) var busy = false
    private let services: WatchGameServices
    private var task: Task<Void,Never>?
    private var jobID: UUID?
    private var accountID: String?
    init(services: WatchGameServices) { self.services = services }
    func dictate() {
        guard !busy, let controller = WKExtension.shared().visibleInterfaceController else { return }
        let accountAtInput = services.cloud.account?.id
        controller.presentTextInputController(withSuggestions:nil,allowedInputMode:.plain) { [weak self] values in
            guard let self, self.services.cloud.account?.id == accountAtInput else { return }
            if let text = values?.first as? String { self.question = String(text.prefix(2000)) }
        }
    }
    func send() {
        guard !busy else { return }
        let text = question.trimmingCharacters(in:.whitespacesAndNewlines)
        do { try ChatProgress.validate(question:text) } catch { progress.fail("질문을 1~2,000자로 입력해 주세요"); return }
        guard let account = services.cloud.account?.id else { progress.fail("아이폰에서 로그인해 주세요"); return }
        let id = UUID(); jobID = id; accountID = account
        busy = true; progress = ChatProgress()
        task = Task {
            defer { if self.jobID == id { self.busy = false } }
            do {
                _ = try await services.client.request(.startChat(id,text),accountID:account)
                while !Task.isCancelled, self.jobID == id {
                    guard services.cloud.account?.id == account else { throw BackendError.sessionChanged }
                    let reply = try await services.client.request(.pollChat(id),accountID:account)
                    guard self.jobID == id, services.cloud.account?.id == account else { return }
                    guard case let .chat(value) = reply else { throw BackendError.invalidResponse }
                    progress = value
                    if value.finished {
                        _ = try? await services.client.request(.cancelChat(id),accountID:account)
                        if self.jobID == id { self.jobID = nil; self.accountID = nil; self.busy = false }
                        return
                    }
                    try await Task.sleep(for:.milliseconds(300))
                }
            } catch is CancellationError { }
            catch { if self.jobID == id { progress.fail((error as? BackendError ?? .network).localizedDescription) } }
            if self.jobID == id { _ = try? await services.client.request(.cancelChat(id),accountID:account) }
        }
    }
    func stop(clear: Bool = false) {
        let wasBusy = busy
        task?.cancel(); task = nil
        if let id = jobID, let accountID {
            Task { [services] in _ = try? await services.client.request(.cancelChat(id),accountID:accountID) }
        }
        jobID = nil; accountID = nil; busy = false
        if clear { question = ""; progress = ChatProgress() }
        else if wasBusy && !progress.finished { progress.fail("응답을 중단했어요") }
    }
}

struct WatchChatOverview: View {
    let services: WatchGameServices
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:"bubble.left.and.bubble.right.fill").font(.largeTitle).foregroundStyle(.cyan)
            Text("펫과 대화").font(.headline)
            Text("음성으로 질문하고\n답변을 받아요").font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            NavigationLink("AI 대화 열기") { WatchChatView(services:services) }.accessibilityIdentifier("watch.openChat")
        }.padding(.horizontal,16)
    }
}
struct WatchChatView: View {
    @StateObject private var model: WatchChatViewModel
    @ObservedObject private var cloud: WatchCloudController
    @Environment(\.scenePhase) private var phase
    init(services: WatchGameServices) {
        _model = StateObject(wrappedValue:WatchChatViewModel(services:services)); cloud = services.cloud
    }
    var body: some View {
        List {
            if cloud.isDevelopment { Text("개발용 모의 AI · 외부 전송 없음").font(.caption2).foregroundStyle(.orange) }
            Section("질문") {
                Button { model.dictate() } label: { Label("음성으로 입력",systemImage:"mic.fill") }.disabled(model.busy).accessibilityIdentifier("chat.dictate")
                TextField("질문 입력·수정",text:$model.question).disabled(model.busy).accessibilityIdentifier("chat.question")
                Text("입력한 내용을 확인한 뒤 보내 주세요.").font(.caption2).foregroundStyle(.secondary)
                Button("AI에 질문 보내기") { model.send() }.disabled(model.busy || model.question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("chat.send")
            }
            Section("답변") {
                Text(model.progress.status).font(.caption2).foregroundStyle(model.progress.failed ? .orange : .secondary).accessibilityIdentifier("chat.status")
                if !model.progress.text.isEmpty { Text(model.progress.text).font(.caption).accessibilityIdentifier("chat.answer") }
                if model.busy { ProgressView(); Button("응답 중단") { model.stop() } }
            }
            Text("아이폰의 PetPet과 연결이 필요해요.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("AI 대화")
            .onDisappear { model.stop() }
            .onChange(of:phase) { _,value in if value == .background { model.stop() } }
            .onChange(of:cloud.account?.id) { _,_ in model.stop(clear:true) }
    }
}
