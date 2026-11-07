import Foundation

@MainActor
public final class PhoneProfileCoordinator {
    public var onProfileChange: (() async -> Void)?
    private let backend: BackendClient
    private let environment: CloudEnvironment

    public init(backend: BackendClient, transport: any CloudTransport, environment: CloudEnvironment) {
        self.backend = backend; self.environment = environment
        transport.onProfileRequest = { [weak self] data in
            guard let self else { throw BackendError.watchUnavailable }
            return try await self.receive(data)
        }
    }

    public func refresh(accountID: String) async throws {
        do {
            _ = try await backend.profileNickname(accountID: accountID)
            await onProfileChange?()
        } catch { await onProfileChange?(); throw error }
    }
    public func check(_ value: String, accountID: String) async throws -> Bool {
        do { return try await backend.checkNickname(value, accountID: accountID) }
        catch { await onProfileChange?(); throw error }
    }
    public func update(_ value: String, accountID: String) async throws -> String {
        do {
            let nickname = try await backend.updateNickname(value, accountID: accountID)
            await onProfileChange?()
            return nickname
        } catch { await onProfileChange?(); throw error }
    }
    private func receive(_ data: Data) async throws -> Data {
        let request = try CloudWire.decodeProfileRequest(data, environment: environment)
        let result: NicknameReply.Result
        do {
            switch request.action {
            case .check: result = .availability(try await check(request.nickname, accountID: request.accountID))
            case .update: result = .updated(try await update(request.nickname, accountID: request.accountID))
            }
        } catch {
            result = .failure(ProfileFailure(error))
        }
        return try CloudWire.encodeProfileReply(NicknameReply(request: request, result: result), environment: environment)
    }
}
