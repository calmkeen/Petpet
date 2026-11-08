import Combine
import Foundation
import PetPetCore

@MainActor
final class PhoneHomeViewModel: ObservableObject {
    @Published private(set) var state: PhoneSnapshotState
    @Published private(set) var serverPet: CachedServerPet?
    @Published private(set) var isServerPetLoading = false
    @Published private(set) var serverPetError: String?
    private let receiver: PhoneSnapshotReceiver?
    private let backend: BackendClient?
    private let petCache: FileAccountPetCache?
    private let uptime: () -> TimeInterval
    private var accountID: String?
    private var serverRevision = 0
    private var lastServerLoad: TimeInterval?

    init(receiver: PhoneSnapshotReceiver? = nil, initialState: PhoneSnapshotState = PhoneSnapshotState(),
         backend: BackendClient? = nil, petCache: FileAccountPetCache? = nil,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.receiver = receiver
        self.backend = backend; self.petCache = petCache; self.uptime = uptime
        state = initialState
        receiver?.onStateChange = { [weak self] in self?.state = $0 }
    }

    var todaySteps: DailyStepRecord? { state.cached?.steps(on: Date()) }
    var stepCountText: String { todaySteps.map { $0.stepCount.formatted() } ?? "—" }
    var snapshot: WatchSnapshot? { state.cached?.snapshot }
    var displayedPet: PetProfile? { snapshot?.pet ?? serverPet?.pet }
    var isShowingServerPet: Bool { snapshot == nil && serverPet != nil }
    var isRefreshing: Bool { state.isRefreshing || isServerPetLoading }

    func setAccount(_ id: String?) {
        guard id != accountID else { return }
        accountID = id; serverRevision += 1; lastServerLoad = nil
        serverPet = nil; serverPetError = nil; isServerPetLoading = false
    }

    func refreshServerPet(force: Bool = false) async {
        guard let accountID, let backend else { return }
        if !force, isServerPetLoading { return }
        if !force, let lastServerLoad, uptime() - lastServerLoad < 30 { return }
        serverRevision += 1
        let revision = serverRevision
        isServerPetLoading = true
        defer { if serverRevision == revision { isServerPetLoading = false } }
        if serverPet == nil, let saved = try? await petCache?.load(accountID: accountID), serverRevision == revision { serverPet = saved }
        do {
            let pet = try await backend.petProfile(accountID: accountID)
            guard serverRevision == revision, self.accountID == accountID, !Task.isCancelled else { return }
            let fetchedAt = Date()
            serverPet = CachedServerPet(accountID: accountID, pet: pet, fetchedAt: fetchedAt)
            serverPetError = nil; lastServerLoad = uptime()
            do { try await petCache?.save(pet, accountID: accountID, at: fetchedAt) }
            catch { if serverRevision == revision { serverPetError = "최신 서버 펫을 불러왔지만 아이폰에 저장하지 못했어요." } }
        } catch is CancellationError { }
        catch {
            guard serverRevision == revision, self.accountID == accountID else { return }
            if error as? BackendError == .http(404) || error as? BackendError == .noBackup {
                serverPetError = serverPet == nil ? "서버에 저장된 펫이 없어요. 워치 기록을 백업하면 여기서도 볼 수 있어요." : "서버 펫을 찾지 못했어요. 마지막 서버 기록을 표시해요."
            } else {
                serverPetError = serverPet == nil ? "서버 펫을 불러오지 못했어요. 잠시 후 다시 시도해 주세요." : "서버 펫을 불러오지 못했어요. 마지막 서버 기록을 표시해요."
            }
        }
    }

    var connectionText: String {
        let connection = state.connection
        if !connection.isSupported { return "이 기기는 워치 동기화를 지원하지 않아요" }
        if !connection.isActivated { return "워치 연결 준비 중" }
        if !connection.isPaired { return "Apple Watch를 연결해 주세요" }
        if !connection.isCounterpartInstalled { return "워치에 PetPet을 설치해 주세요" }
        return connection.isReachable ? "워치와 연결됨" : "워치의 다음 연결을 기다리는 중"
    }

    var syncNote: String {
        if state.hasEnvironmentMismatch { return "아이폰과 워치에 같은 테스트 앱 또는 정식 앱을 설치한 뒤 다시 동기화해 주세요." }
        if state.hasStorageError { return "아이폰에 기록을 저장하지 못했어요. 다시 동기화해 주세요." }
        if state.hasTransferError && state.connection.isReachable { return "기록을 받지 못했어요. 다시 동기화해 주세요." }
        if state.cached == nil { return "워치에서 PetPet을 열면 걸음수와 펫 상태를 가져와요." }
        if !state.connection.isReachable { return "마지막으로 받은 기록이에요. 워치에서 PetPet을 열면 최신 상태를 받아요." }
        if todaySteps == nil { return "아직 오늘의 워치 기록이 없어요. 워치에서 PetPet을 열어 주세요." }
        return "워치에서 걷고 펫을 돌보면 여기도 함께 업데이트돼요."
    }

    func start() async { await receiver?.start() }
    func refresh() async {
        async let watch: Void = refreshWatch()
        async let pet: Void = refreshServerPet(force: true)
        _ = await (watch, pet)
    }
    private func refreshWatch() async { await receiver?.refresh() }
    func refreshDate() { objectWillChange.send() }
}
