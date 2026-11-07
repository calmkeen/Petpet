import Combine
import Foundation
import PetPetCore

/// Preserves the existing reaction draft. The static home sprite is not yet
/// connected to these states; the pet interaction milestone will do that.
@MainActor
final class CharacterActivityViewModel: ObservableObject {
    @Published private(set) var activity: CharacterActivity = .idle
    private let detector: any MotionDetecting
    private var isDetecting = false
    private var isMoving = false
    private var stopTimer: Timer?
    private var idleTimer: Timer?
    private var reactionTask: Task<Void, Never>?

    init(detector: any MotionDetecting) {
        self.detector = detector
    }

    func start() {
        guard !isDetecting else { return }
        isDetecting = true
        detector.start { [weak self] moving in
            guard let self, self.isDetecting, moving != self.isMoving else { return }
            self.isMoving = moving
            self.reactionTask?.cancel()
            if moving {
                self.resetTimers()
                self.activity = .running
            } else {
                self.startStopTimer()
            }
        }
    }

    func handleTouch() {
        reactionTask?.cancel()
        activity = .touching
        resetActivity(after: 2_000_000_000)
    }

    func stop() {
        isDetecting = false
        isMoving = false
        detector.stop()
        resetTimers()
        reactionTask?.cancel()
        activity = .idle
    }

    private func startStopTimer() {
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isDetecting, !self.isMoving else { return }
                self.activity = .idle
                self.startIdleTimer()
            }
        }
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isDetecting, !self.isMoving else { return }
                self.activity = .stopped
                self.resetActivity(after: 1_000_000_000)
            }
        }
    }

    private func resetActivity(after nanoseconds: UInt64) {
        reactionTask?.cancel()
        reactionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard let self else { return }
            self.activity = self.isMoving ? .running : .idle
        }
    }

    private func resetTimers() {
        stopTimer?.invalidate()
        idleTimer?.invalidate()
    }
}
