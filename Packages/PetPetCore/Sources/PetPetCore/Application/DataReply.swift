import Foundation

/// Bounds a callback-based request without retrying a possibly applied mutation.
public enum DataReply {
    @MainActor public static func wait(
        timeout: Duration = .seconds(30),
        start: (@escaping @Sendable (Result<Data, Error>) -> Void) -> Void
    ) async throws -> Data {
        try Task.checkCancellation()
        let state = ReplyState()
        let timer = Task {
            do { try await Task.sleep(for: timeout); state.finish(.failure(BackendError.watchUnavailable)) }
            catch { }
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation) else { return }
                start { state.finish($0) }
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
        }
    }
}

private final class ReplyState: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    private var continuation: CheckedContinuation<Data, Error>?
    func install(_ continuation: CheckedContinuation<Data, Error>) -> Bool {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result); return false }
        self.continuation = continuation; lock.unlock(); return true
    }
    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation; self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
