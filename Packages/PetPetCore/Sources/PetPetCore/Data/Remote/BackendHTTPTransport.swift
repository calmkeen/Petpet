import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct BackendHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public init(statusCode: Int, data: Data = Data()) { self.statusCode = statusCode; self.data = data }
}

public protocol BackendHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse
}

public struct URLSessionBackendTransport: BackendHTTPTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoBackendRedirects(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
            return BackendHTTPResponse(statusCode: response.statusCode, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as BackendError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw BackendError.network
        }
    }
}

private final class NoBackendRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
