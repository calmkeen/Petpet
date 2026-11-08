import Combine
import Foundation
import PetPetCore

@MainActor final class WatchGameServices: ObservableObject {
    let client: WatchFeatureClient
    let records: FileMiniGameRecords
    let cloud: WatchCloudController
    init(client: WatchFeatureClient, records: FileMiniGameRecords, cloud: WatchCloudController) {
        self.client = client; self.records = records; self.cloud = cloud
    }
}

@MainActor final class WatchGameResultModel: ObservableObject {
    @Published private(set) var score: GameScore?
    @Published private(set) var best: GameScore?
    @Published private(set) var ranking: GameRanking?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private let services: WatchGameServices
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var accountSubscription: AnyCancellable?
    init(services: WatchGameServices) {
        self.services = services
        accountSubscription = services.cloud.$account.map { $0?.id }.removeDuplicates().dropFirst().sink { [weak self] id in
            guard let self else { return }
            self.stop(); self.ranking = nil
            self.message = id == nil ? "아이폰에서 로그인한 뒤 랭킹을 다시 확인해 주세요." : "계정이 바뀌었어요. 로컬 기록은 유지돼요. 랭킹을 다시 확인해 주세요."
        }
    }
    func loadBest(_ game: MiniGame) async {
        do { best = try await services.records.best(game) }
        catch { message = "최고 기록을 불러오지 못했어요" }
    }
    func finish(_ score: GameScore) {
        stop(); self.score = score; ranking = nil; message = nil
        let revision = revision
        task = Task {
            do { let best = try await services.records.record(score); guard self.revision == revision else { return }; self.best = best }
            catch { guard self.revision == revision else { return }; message = "최고 기록 저장에 실패했어요. 다시 시도해 주세요."; return }
            await send(score, revision: revision)
        }
    }
    func retry() { if let score { finish(score) } }
    func loadRanking(_ game: MiniGame) {
        stop(); score = nil; ranking = nil; message = nil
        let revision = revision
        task = Task { await fetch(.ranking(game), revision: revision) }
    }
    func stop() { task?.cancel(); task = nil; revision = UUID(); busy = false }
    func clear() { stop(); score = nil; ranking = nil; message = nil }
    private func send(_ score: GameScore, revision: UUID) async { await fetch(.submit(score), revision: revision) }
    private func fetch(_ action: CompanionFeatureRequest.Action, revision: UUID) async {
        guard let accountID = services.cloud.account?.id else { message = "로컬 기록은 유지돼요. 랭킹은 아이폰에서 로그인한 뒤 확인해 주세요."; return }
        busy = true
        defer { if self.revision == revision { busy = false } }
        do {
            let result = try await services.client.request(action, accountID: accountID)
            guard self.revision == revision, services.cloud.account?.id == accountID, !Task.isCancelled else { return }
            if case let .ranking(value) = result { ranking = value }
            else { throw BackendError.invalidResponse }
        } catch is CancellationError { }
        catch { guard self.revision == revision else { return }; message = (error as? BackendError ?? .network).localizedDescription }
    }
}
