import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol BackendChatTransport: Sendable {
    func stream(_ request: URLRequest, onEvent: @escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws
}

extension URLSessionBackendTransport: BackendChatTransport {
    public func stream(_ request: URLRequest, onEvent: @escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw BackendError.http(response.statusCode) }
            guard response.mimeType?.lowercased() == "text/event-stream" else { throw BackendError.invalidResponse }
            var parser = ChatSSEParser()
            for try await line in bytes.lines {
                try Task.checkCancellation()
                if let event = try parser.line(line) {
                    try await onEvent(event)
                    if event.name == "done" || event.name == "error" { return }
                }
            }
            if let event = parser.finish() { try await onEvent(event) }
        } catch is CancellationError { throw CancellationError() }
        catch let error as BackendError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw BackendError.network }
    }
}
