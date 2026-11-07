import CoreMotion
import Foundation
import PetPetCore

@MainActor
final class CoreMotionStepCounter: StepCounting {
    private let pedometer = CMPedometer()

    func steps(from start: Date, to end: Date) async throws -> Int {
        if let error = availabilityError() { throw error }
        guard start <= end else { throw StepCountingError.updateFailed }
        if start == end { return 0 }
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                let count = data?.numberOfSteps.intValue
                let failed = error != nil
                Task { @MainActor in
                    if !failed, let count {
                        continuation.resume(returning: count)
                    } else {
                        continuation.resume(throwing: Self.updateError())
                    }
                }
            }
        }
    }

    func startUpdates(
        from date: Date,
        onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void
    ) {
        if let error = availabilityError() {
            onUpdate(.failure(error))
            return
        }

        pedometer.startUpdates(from: date) { data, error in
            let steps = data?.numberOfSteps.intValue
            let didFail = error != nil
            Task { @MainActor in
                if !didFail, let steps {
                    onUpdate(.success(steps))
                } else if didFail {
                    onUpdate(.failure(Self.updateError()))
                }
            }
        }
    }

    func stopUpdates() {
        pedometer.stopUpdates()
    }

    private func availabilityError() -> StepCountingError? {
        guard CMPedometer.isStepCountingAvailable() else { return .unavailable }
        let authorization = CMPedometer.authorizationStatus()
        return authorization == .denied || authorization == .restricted ? .permissionDenied : nil
    }

    private static func updateError() -> StepCountingError {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted ? .permissionDenied : .updateFailed
    }
}
