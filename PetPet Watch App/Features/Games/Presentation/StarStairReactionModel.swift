import Combine
import Foundation
import WatchKit
import PetPetCore

/// Android: directional pose 1 for 80ms, pose 2 for 100ms, then idle.
/// Only the latest success can update the image; failures vibrate immediately.
@MainActor
final class StarStairReactionModel: ObservableObject {
    @Published private(set) var imageName = "stepmate_fox_idle"
    private var animation: Task<Void, Never>?
    private var generation = UUID()

    func receive(_ feedback: StarStairFeedback, animate: Bool, haptics: Bool) {
        stop()
        switch feedback {
        case let .correct(direction):
            guard animate else { return }
            let token = generation
            let prefix = "stepmate_game_snowfox_baby_\(direction.rawValue)_running"
            imageName = prefix + "1"
            animation = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.imageName = prefix + "2"
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.generation == token, !Task.isCancelled else { return }
                self.imageName = "stepmate_fox_idle"
                self.animation = nil
            }
        case .wrong, .timeout:
            if haptics { WKInterfaceDevice.current().play(.failure) }
        }
    }
    func stop() {
        generation = UUID()
        animation?.cancel(); animation = nil
        imageName = "stepmate_fox_idle"
    }
}
