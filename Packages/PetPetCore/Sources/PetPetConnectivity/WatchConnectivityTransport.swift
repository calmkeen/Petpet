#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import PetPetCore

/// A single session owner per process. Main-actor callbacks are the boundary
/// between WCSession's background delegate queue and application state.
@MainActor
public final class WatchConnectivityTransport: NSObject, SnapshotTransport {
    private static let snapshotKey = "petpet.snapshot.v1"
    private static let requestKey = "petpet.requestSnapshot.v1"
    public private(set) var connection = SnapshotConnection()
    public var onConnectionChange: ((SnapshotConnection) -> Void)?
    public var onSnapshot: ((Data, String) -> Void)?
    public var onSnapshotRequest: (() async throws -> Data)?
    private let session: WCSession?

    public override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        if session == nil { connection.isSupported = false }
    }

    public func activate() {
        guard let session else { onConnectionChange?(connection); return }
        if session.activationState == .activated {
            updateConnection()
            receiveContext(session.receivedApplicationContext)
        } else {
            session.activate()
        }
    }

    public func publish(_ data: Data) throws {
        guard let session, session.activationState == .activated else { throw SnapshotSyncError.notActivated }
        // Context delivery persists while unreachable and coalesces updates.
        try session.updateApplicationContext([Self.snapshotKey: data])
        recordDiagnostic("queued")
        if session.isReachable {
            session.sendMessage([Self.snapshotKey: data], replyHandler: nil, errorHandler: { _ in
                // The queued application context remains the fallback.
            })
        }
    }

    public func requestLatest() async throws -> Data {
        guard let session, session.activationState == .activated else { throw SnapshotSyncError.notActivated }
        guard session.isReachable else { throw SnapshotSyncError.notReachable }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage([Self.requestKey: true], replyHandler: { reply in
                if let data = reply[Self.snapshotKey] as? Data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: SnapshotSyncError.transferFailed)
                }
            }, errorHandler: { _ in continuation.resume(throwing: SnapshotSyncError.transferFailed) })
        }
    }

    private func updateConnection() {
        guard let session else { onConnectionChange?(connection); return }
        #if os(iOS)
        connection = SnapshotConnection(
            isActivated: session.activationState == .activated,
            isPaired: session.isPaired, isCounterpartInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            peerID: session.activationState == .notActivated ? nil : session.watchDirectoryURL?.absoluteString
        )
        #else
        connection = SnapshotConnection(
            isActivated: session.activationState == .activated,
            isPaired: true, isCounterpartInstalled: session.isCompanionAppInstalled,
            isReachable: session.isReachable
        )
        #endif
        onConnectionChange?(connection)
        recordDiagnostic("connection")
    }

    /// Local development diagnostics contain connection flags only, never
    /// activity values, pet data, account information or a device identifier.
    private func recordDiagnostic(_ event: String, error: Error? = nil) {
        #if DEBUG
        var flags: [String: Any] = [
            "event": event, "activated": connection.isActivated,
            "paired": connection.isPaired, "installed": connection.isCounterpartInstalled,
            "reachable": connection.isReachable, "hasPeerID": connection.peerID != nil,
            "outgoingKeys": session?.applicationContext.keys.sorted() ?? [],
            "incomingKeys": session?.receivedApplicationContext.keys.sorted() ?? []
        ]
        if let error {
            flags["errorCode"] = (error as NSError).code
            flags["errorDomain"] = (error as NSError).domain
        }
        let url = URL.applicationSupportDirectory.appendingPathComponent("PetPet", isDirectory: true)
            .appendingPathComponent("connectivity-debug.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: flags).write(to: url, options: .atomic)
        } catch { /* Diagnostics must not affect the actual transfer. */ }
        #endif
    }

    private func receiveContext(_ context: [String: Any]) {
        #if os(iOS)
        guard let data = context[Self.snapshotKey] as? Data, let peer = connection.peerID else { return }
        onSnapshot?(data, peer)
        #endif
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            self?.updateConnection()
            self?.recordDiagnostic("activation", error: error)
            self?.receiveContext(session.receivedApplicationContext)
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateConnection() }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[Self.snapshotKey] as? Data
        Task { @MainActor [weak self] in
            guard let self, let data, let peer = self.connection.peerID else { return }
            self.recordDiagnostic("receivedContext")
            self.onSnapshot?(data, peer)
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message[Self.snapshotKey] as? Data
        Task { @MainActor [weak self] in
            guard let self, let data, let peer = self.connection.peerID else { return }
            self.recordDiagnostic("receivedMessage")
            self.onSnapshot?(data, peer)
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let requestsSnapshot = message[Self.requestKey] as? Bool == true
        Task { @MainActor [weak self] in
            guard requestsSnapshot, let request = self?.onSnapshotRequest else {
                replyHandler(["error": true]); return
            }
            do { replyHandler([Self.snapshotKey: try await request()]) }
            catch { replyHandler(["error": true]) }
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateConnection() }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.activate() }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.updateConnection()
            self?.receiveContext(session.receivedApplicationContext)
        }
    }
    #endif
}
#endif
