import Combine
import Foundation
import PetPetCore

@MainActor
final class PhoneHomeViewModel: ObservableObject {
    @Published private(set) var state: PhoneSnapshotState
    private let receiver: PhoneSnapshotReceiver?

    init(receiver: PhoneSnapshotReceiver? = nil, initialState: PhoneSnapshotState = PhoneSnapshotState()) {
        self.receiver = receiver
        state = initialState
        receiver?.onStateChange = { [weak self] in self?.state = $0 }
    }

    var todaySteps: DailyStepRecord? { state.cached?.steps(on: Date()) }
    var stepCountText: String { todaySteps.map { $0.stepCount.formatted() } ?? "—" }
    var snapshot: WatchSnapshot? { state.cached?.snapshot }

    var connectionText: String {
        let connection = state.connection
        if !connection.isSupported { return "이 기기는 워치 동기화를 지원하지 않아요" }
        if !connection.isActivated { return "워치 연결 준비 중" }
        if !connection.isPaired { return "Apple Watch를 연결해 주세요" }
        if !connection.isCounterpartInstalled { return "워치에 PetPet을 설치해 주세요" }
        return connection.isReachable ? "워치와 연결됨" : "워치의 다음 연결을 기다리는 중"
    }

    var syncNote: String {
        if state.hasStorageError { return "아이폰에 기록을 저장하지 못했어요. 다시 동기화해 주세요." }
        if state.hasTransferError && state.connection.isReachable { return "기록을 받지 못했어요. 다시 동기화해 주세요." }
        if state.cached == nil { return "워치에서 PetPet을 열면 걸음수와 펫 상태를 가져와요." }
        if !state.connection.isReachable { return "마지막으로 받은 기록이에요. 워치에서 PetPet을 열면 최신 상태를 받아요." }
        if todaySteps == nil { return "아직 오늘의 워치 기록이 없어요. 워치에서 PetPet을 열어 주세요." }
        return "워치에서 걷고 펫을 돌보면 여기도 함께 업데이트돼요."
    }

    func start() async { await receiver?.start() }
    func refresh() async { await receiver?.refresh() }
    func refreshDate() { objectWillChange.send() }
}
