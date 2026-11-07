import Foundation

@MainActor
public final class WatchNicknameRelay {
    private let transport: any CloudTransport
    private let environment: CloudEnvironment
    private var account: CloudAccount?
    private var generation = 0

    public init(transport: any CloudTransport, environment: CloudEnvironment) {
        self.transport = transport; self.environment = environment
    }
    public func setAccount(_ value: CloudAccount?) {
        if value?.id != account?.id { generation += 1 }
        account = value
    }
    public func check(_ value: String) async throws -> Bool {
        let result = try await send(.check, value: value)
        guard case let .availability(available) = result else { throw BackendError.invalidResponse }
        return available
    }
    public func update(_ value: String) async throws -> String {
        let result = try await send(.update, value: value)
        guard case let .updated(nickname) = result else { throw BackendError.invalidResponse }
        return nickname
    }
    private func send(_ action: NicknameRequest.Action, value: String) async throws -> NicknameReply.Result {
        try NicknameRules.validate(value)
        guard let account else { throw BackendError.authenticationRequired }
        let token = generation
        let request = NicknameRequest(accountID: account.id, action: action, nickname: value)
        // A rename uses a live reply, never a background mutation queue that
        // could unexpectedly apply hours after the editor timed out.
        let data = try await transport.requestProfile(CloudWire.encodeProfileRequest(request, environment: environment))
        try Task.checkCancellation()
        guard token == generation, self.account?.id == account.id else { throw BackendError.sessionChanged }
        let reply = try CloudWire.decodeProfileReply(data, environment: environment)
        guard reply.id == request.id, reply.accountID == account.id else { throw BackendError.invalidResponse }
        if case let .failure(reason) = reply.result { throw reason.error }
        return reply.result
    }
}
