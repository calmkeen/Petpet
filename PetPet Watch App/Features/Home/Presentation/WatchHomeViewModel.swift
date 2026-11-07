import Combine
import PetPetCore

@MainActor
final class WatchHomeViewModel: ObservableObject {
    @Published private(set) var state: DailyStepState
    private let tracker: DailyStepTracker

    init(stepCounter: any StepCounting, repository: any StepHistoryRepository) {
        tracker = DailyStepTracker(counter: stepCounter, repository: repository)
        state = tracker.state
        tracker.onStateChange = { [weak self] state in
            self?.state = state
        }
    }

    var errorMessage: String? {
        switch state.error {
        case .unavailable:
            return "이 기기에서는 걸음 수를 측정할 수 없어요."
        case .permissionDenied:
            return "동작 및 피트니스 권한을 허용해 주세요."
        case .updateFailed:
            return "걸음 수를 불러오지 못했어요. 앱을 다시 열어 주세요."
        case nil:
            return state.hasStorageError ? "걸음 수 기록을 저장하지 못했어요." : nil
        }
    }

    func start() async { await tracker.start() }
    func refresh() async { await tracker.refresh() }
    func stop() {
        tracker.stop()
        Task { [tracker] in await tracker.flush() }
    }
}
