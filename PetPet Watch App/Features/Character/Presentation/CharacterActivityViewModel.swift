import Combine
import Foundation
import PetPetCore

@MainActor
final class CharacterActivityViewModel: ObservableObject {
    @Published private(set) var state = PetAnimationState()
    private var completion: Task<Void, Never>?

    var canTouch: Bool {
        state.isActive && state.activity != .running && state.activity != .touching
    }

    func setActive(_ value: Bool, steps: DailyStepState) {
        state.setActive(value, at: Date())
        state.observe(steps, at: Date())
        scheduleCompletion()
    }
    func observe(_ steps: DailyStepState) {
        let deadline = state.expiresAt
        state.observe(steps, at: Date())
        if deadline != state.expiresAt { scheduleCompletion() }
    }
    @discardableResult
    func handleTouch() -> Bool {
        guard state.touch(at: Date()) else { return false }
        scheduleCompletion()
        return true
    }
    func stop() {
        state.setActive(false, at: Date())
        completion?.cancel(); completion = nil
    }
    private func scheduleCompletion() {
        completion?.cancel(); completion = nil
        guard let deadline = state.expiresAt else { return }
        completion = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard let self, !Task.isCancelled, self.state.expiresAt == deadline else { return }
            self.state.tick(at: max(Date(), deadline))
        }
    }
}
