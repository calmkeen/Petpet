import CoreMotion
import PetPetCore

@MainActor
final class CoreMotionActivityDetector: MotionDetecting {
    private let manager = CMMotionManager()

    func start(onMovement: @escaping @MainActor (Bool) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.5
        manager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let acceleration = data?.userAcceleration else { return }
            let magnitude = (
                acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
            ).squareRoot()
            Task { @MainActor in onMovement(magnitude > 1.2) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
