import Foundation

@MainActor public protocol CompanionFeatureTransport: AnyObject {
    var onFeatureRequest: ((Data) async throws -> Data)? { get set }
    func requestFeature(_ data: Data) async throws -> Data
}
public struct CompanionFeatureRequest: Codable, Sendable {
    public enum Action: Codable, Sendable {
        case ranking(MiniGame), submit(GameScore)
        case startChat(UUID, String), pollChat(UUID), cancelChat(UUID)
    }
    public let id: UUID
    public let accountID: String
    public let environment: CloudEnvironment
    public let action: Action
    public init(id: UUID = UUID(), accountID: String, environment: CloudEnvironment, action: Action) {
        self.id = id; self.accountID = accountID; self.environment = environment; self.action = action
    }
}
public struct CompanionFeatureReply: Codable, Sendable {
    public enum Result: Codable, Sendable {
        case ranking(GameRanking), chat(ChatProgress), accepted
        case failure(ProfileFailure)
    }
    public let id: UUID
    public let accountID: String
    public let environment: CloudEnvironment
    public let result: Result
    public init(request: CompanionFeatureRequest, result: Result) {
        id = request.id; accountID = request.accountID; environment = request.environment; self.result = result
    }
}

@MainActor public final class WatchFeatureClient {
    private let transport: any CompanionFeatureTransport
    private let environment: CloudEnvironment
    public init(transport: any CompanionFeatureTransport, environment: CloudEnvironment) { self.transport = transport; self.environment = environment }
    public func request(_ action: CompanionFeatureRequest.Action, accountID: String) async throws -> CompanionFeatureReply.Result {
        try Task.checkCancellation()
        let request = CompanionFeatureRequest(accountID: accountID, environment: environment, action: action)
        let data = try await transport.requestFeature(JSONEncoder().encode(request))
        try Task.checkCancellation()
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let reply = try JSONDecoder().decode(CompanionFeatureReply.self, from: data)
        guard reply.environment == environment else { throw BackendError.environmentMismatch }
        guard reply.id == request.id, reply.accountID == accountID else { throw BackendError.sessionChanged }
        if case let .failure(failure) = reply.result { throw failure.error }
        return reply.result
    }
}
