import Foundation

public struct SnapshotConnection: Equatable, Sendable {
    public var isSupported: Bool
    public var isActivated: Bool
    public var isPaired: Bool
    public var isCounterpartInstalled: Bool
    public var isReachable: Bool
    public var peerID: String?

    public init(isSupported: Bool = true, isActivated: Bool = false, isPaired: Bool = false,
                isCounterpartInstalled: Bool = false, isReachable: Bool = false, peerID: String? = nil) {
        self.isSupported = isSupported
        self.isActivated = isActivated
        self.isPaired = isPaired
        self.isCounterpartInstalled = isCounterpartInstalled
        self.isReachable = isReachable
        self.peerID = peerID
    }
}

@MainActor
public protocol SnapshotTransport: AnyObject {
    var connection: SnapshotConnection { get }
    var onConnectionChange: ((SnapshotConnection) -> Void)? { get set }
    var onSnapshot: ((Data, String) -> Void)? { get set }
    var onSnapshotRequest: (() async throws -> Data)? { get set }
    func activate()
    func publish(_ data: Data) throws
    func requestLatest() async throws -> Data
}
