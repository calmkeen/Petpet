import Combine
import Foundation
import PetPetCore

@MainActor final class WatchRankingPageModel: ObservableObject {
    enum Kind { case steps, game(MiniGame) }
    @Published private(set) var stepPage: StepRankingPage?
    @Published private(set) var gamePage: GameRankingPage?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    let kind: Kind
    private let client: WatchFeatureClient
    private let cloud: WatchCloudController
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var account: AnyCancellable?
    var page: Int { stepPage?.page ?? gamePage?.request.page ?? 1 }
    var hasNext: Bool { stepPage?.hasNext ?? gamePage?.hasNext ?? false }
    init(kind: Kind, client: WatchFeatureClient, cloud: WatchCloudController) {
        self.kind = kind; self.client = client; self.cloud = cloud
        account = cloud.$account.map { $0?.id }.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.stop(); self?.stepPage = nil; self?.gamePage = nil; self?.error = "계정이 바뀌었어요. 다시 불러와 주세요."
        }
    }
    func load(_ page: Int = 1) {
        stop()
        guard let id = cloud.account?.id else { error = "계정에서 로그인한 뒤 랭킹을 확인해 주세요."; return }
        let request = RankingPageRequest(page: page, size: 5)
        let token = revision; busy = true; error = nil
        task = Task {
            defer { if revision == token { busy = false } }
            do {
                let action: CompanionFeatureRequest.Action
                switch kind { case .steps: action = .stepPage(request); case let .game(game): action = .gamePage(game, request) }
                let result = try await client.request(action, accountID: id)
                guard revision == token, cloud.account?.id == id, !Task.isCancelled else { return }
                switch (kind, result) {
                case (.steps, let .stepPage(value)) where value.page == request.page && value.size == request.size: stepPage = value
                case (let .game(game), let .gamePage(value)) where value.game == game && value.request == request: gamePage = value
                default: throw BackendError.invalidResponse
                }
            } catch is CancellationError { }
            catch { guard revision == token else { return }; self.error = error.localizedDescription }
        }
    }
    func stop() { task?.cancel(); task = nil; revision = UUID(); busy = false }
    func finishWork() async { await task?.value }
}

@MainActor final class WatchProfileImageModel: ObservableObject {
    @Published private(set) var profile: AccountProfileDetails?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let client: WatchFeatureClient
    private let cloud: WatchCloudController
    private var revision = UUID()
    private var account: AnyCancellable?
    init(client: WatchFeatureClient, cloud: WatchCloudController) {
        self.client = client; self.cloud = cloud
        account = cloud.$account.map { $0?.id }.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.revision = UUID(); self?.profile = nil; self?.busy = false; self?.message = nil
        }
    }
    func load() async { await perform(.profile, success: nil) }
    func upload(_ data: Data) async {
        guard !busy else { return }
        do { let image = try RepresentativeImage.thumbnail(from: data); await perform(.updatePicture(image), success: "대표 이미지를 바꿨어요.") }
        catch { message = "사진을 읽지 못했어요. 다른 이미지를 선택해 주세요." }
    }
    private func perform(_ action: CompanionFeatureRequest.Action, success: String?) async {
        guard !busy else { return }
        guard let id = cloud.account?.id else { message = "계정에서 로그인해 주세요."; return }
        let token = revision; busy = true; message = nil
        defer { if revision == token { busy = false } }
        do {
            let result = try await client.request(action, accountID: id)
            guard token == revision, cloud.account?.id == id, !Task.isCancelled else { return }
            guard case let .profile(value) = result else { throw BackendError.invalidResponse }
            profile = value; message = success
        } catch is CancellationError { }
        catch { if revision == token { message = error.localizedDescription } }
    }
}
