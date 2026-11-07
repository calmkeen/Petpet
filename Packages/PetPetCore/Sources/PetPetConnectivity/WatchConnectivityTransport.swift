#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import PetPetCore

/// A single session owner per process. Main-actor callbacks are the boundary
/// between WCSession's background delegate queue and application state.
@MainActor
public final class WatchConnectivityTransport: NSObject, SnapshotTransport, CloudTransport {
    private static let snapshotKey = "petpet.snapshot.v1"
    private static let requestKey = "petpet.requestSnapshot.v1"
    private static let cloudControlKey = "petpet.cloudControl.v1"
    private static let cloudChallengeKey = "petpet.cloudChallenge.v1"
    private static let cloudFileKey = "petpet.cloudFile.v1"
    public private(set) var connection = SnapshotConnection()
    public var onConnectionChange: ((SnapshotConnection) -> Void)?
    public var onSnapshot: ((Data, String) -> Void)?
    public var onSnapshotRequest: (() async throws -> Data)?
    public var onCloudControl: ((Data) -> Void)?
    public var onCloudFile: ((URL) -> Void)?
    public var onCloudChallenge: (() async throws -> Data)?
    public var onCloudTransferError: ((String?) -> Void)?
    private let session: WCSession?
    private var deliveredCloudFiles: Set<URL> = []

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
            recoverCloudInbox()
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

    public func enqueueCloudControl(_ data: Data) throws {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        guard let session, session.activationState == .activated else { throw BackendError.watchUnavailable }
        session.transferUserInfo([Self.cloudControlKey: data])
    }

    public func enqueueCloudFile(_ url: URL) throws {
        guard let session, session.activationState == .activated else { throw BackendError.watchUnavailable }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= CloudWire.maximumFileBytes else { throw BackendError.transferTooLarge }
        session.transferFile(url, metadata: [Self.cloudFileKey: true])
    }

    public func requestCloudChallenge() async throws -> Data {
        guard let session, session.activationState == .activated, session.isReachable else {
            throw BackendError.watchUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage([Self.cloudChallengeKey: true], replyHandler: { reply in
                guard let data = reply[Self.cloudChallengeKey] as? Data else {
                    continuation.resume(throwing: BackendError.watchUnavailable); return
                }
                continuation.resume(returning: data)
            }, errorHandler: { _ in continuation.resume(throwing: BackendError.watchUnavailable) })
        }
    }

    public func waitForPendingContent() async {
        for _ in 0..<100 {
            guard session?.hasContentPending == true else { return }
            try? await Task.sleep(for: .milliseconds(50))
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

    private func deliverCloudFile(_ url: URL) {
        guard let onCloudFile, !deliveredCloudFiles.contains(url) else { return }
        deliveredCloudFiles.insert(url)
        onCloudFile(url)
    }

    private func recoverCloudInbox() {
        // A process may stop after moving an SDK file but before handling it.
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PetPet/CloudInbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" { deliverCloudFile(file) }
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            self?.updateConnection()
            self?.recordDiagnostic("activation", error: error)
            self?.receiveContext(session.receivedApplicationContext)
            if activationState == .activated { self?.recoverCloudInbox() }
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
        let requestsCloud = message[Self.cloudChallengeKey] as? Bool == true
        Task { @MainActor [weak self] in
            if requestsCloud {
                guard let request = self?.onCloudChallenge else { replyHandler(["error": true]); return }
                do { replyHandler([Self.cloudChallengeKey: try await request()]) }
                catch { replyHandler(["error": true]) }
                return
            }
            guard requestsSnapshot, let request = self?.onSnapshotRequest else {
                replyHandler(["error": true]); return
            }
            do { replyHandler([Self.snapshotKey: try await request()]) }
            catch { replyHandler(["error": true]) }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[Self.cloudControlKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.onCloudControl?(data) }
    }

    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[Self.cloudFileKey] as? Bool == true else { return }
        do {
            let size = try file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= CloudWire.maximumFileBytes else { throw BackendError.transferTooLarge }
            let directory = URL.applicationSupportDirectory.appendingPathComponent("PetPet/CloudInbox", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
            // The system deletes WCSessionFile after this callback returns.
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
            Task { @MainActor [weak self] in self?.deliverCloudFile(destination) }
        } catch {
            Task { @MainActor [weak self] in self?.onCloudTransferError?(nil) }
        }
    }

    nonisolated public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard fileTransfer.file.metadata?[Self.cloudFileKey] as? Bool == true else { return }
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
        else { Task { @MainActor [weak self] in self?.onCloudTransferError?(nil) } }
    }

    nonisolated public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, userInfoTransfer.userInfo[Self.cloudControlKey] != nil else { return }
        Task { @MainActor [weak self] in self?.onCloudTransferError?(nil) }
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
