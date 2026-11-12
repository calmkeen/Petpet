import Foundation

/// Select once, before sending. In particular an ambiguous direct POST must
/// never be retried through the phone. Chat jobs keep their original route.
@MainActor public final class WatchFeatureRouter: CompanionFeatureTransport {
    public var onFeatureRequest: ((Data) async throws -> Data)?
    private let direct: WatchStandaloneService
    private let companion: any CompanionFeatureTransport
    private var chats: [UUID: Bool] = [:]
    public init(direct: WatchStandaloneService, companion: any CompanionFeatureTransport) {
        self.direct = direct; self.companion = companion
    }
    public func requestFeature(_ data: Data) async throws -> Data {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        var selected = direct.state.isSelected
        var cleanup: UUID?
        switch request.action {
        case let .startChat(id, _):
            guard chats[id] != nil || chats.count < 64 else { throw BackendError.operationExpired }
            selected = chats[id] ?? selected; chats[id] = selected
        case let .pollChat(id): selected = chats[id] ?? selected
        case let .cancelChat(id): selected = chats[id] ?? selected; cleanup = id
        default: break
        }
        defer { if let cleanup { chats.removeValue(forKey: cleanup) } }
        if selected { return try await direct.requestFeature(data) }
        return try await companion.requestFeature(data)
    }
}
