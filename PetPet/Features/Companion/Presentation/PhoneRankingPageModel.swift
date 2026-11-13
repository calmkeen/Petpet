import Combine
import Foundation
import PetPetCore

@MainActor final class PhoneRankingPageModel: ObservableObject {
    enum Kind { case steps, game(MiniGame) }
    @Published private(set) var stepPage: StepRankingPage?
    @Published private(set) var gamePage: GameRankingPage?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var accountID: String?
    let kind: Kind
    private let backend: BackendClient?
    private var subscription: AnyCancellable?
    private var task: Task<Void,Never>?
    private var revision = UUID()
    var page: Int { stepPage?.page ?? gamePage?.request.page ?? 1 }
    var hasNext: Bool { stepPage?.hasNext ?? gamePage?.hasNext ?? false }
    init(kind: Kind, backend: BackendClient?, account: AccountViewModel) {
        self.kind = kind; self.backend = backend; accountID = account.session?.accountID
        subscription = account.$session.map { $0?.accountID }.removeDuplicates().dropFirst().sink { [weak self] id in
            self?.stop(); self?.accountID = id; self?.stepPage = nil; self?.gamePage = nil; self?.error = nil
        }
    }
    func load(_ page: Int = 1) {
        stop()
        guard let backend, let id = accountID else { error = "계정에서 로그인한 뒤 랭킹을 확인해 주세요."; return }
        let token = revision, request = RankingPageRequest(page: page, size: 5)
        busy = true; error = nil
        task = Task {
            defer { if revision == token { busy = false } }
            do {
                switch kind {
                case .steps:
                    let value = try await backend.stepRanking(request, accountID: id)
                    guard revision == token, accountID == id, !Task.isCancelled else { return }; stepPage = value
                case let .game(game):
                    let value = try await backend.gameRankingPage(game, page: request, accountID: id)
                    guard revision == token, accountID == id, !Task.isCancelled else { return }; gamePage = value
                }
            } catch is CancellationError { }
            catch { if revision == token { self.error = (error as? BackendError ?? .network).localizedDescription } }
        }
    }
    func stop() { task?.cancel(); task = nil; revision = UUID(); busy = false }
    func finishWork() async { await task?.value }
}
