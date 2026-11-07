import Combine
import PetPetCore

@MainActor
final class PhoneHomeViewModel: ObservableObject {
    @Published private(set) var todaySteps: DailyStepRecord?

    init(todaySteps: DailyStepRecord? = nil) {
        self.todaySteps = todaySteps
    }

    var stepCountText: String {
        todaySteps.map { $0.stepCount.formatted() } ?? "—"
    }
}
