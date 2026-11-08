import Foundation

public struct PhoneSnapshotState: Equatable, Sendable {
    public var cached: CachedWatchSnapshot?
    public var connection = SnapshotConnection()
    public var isRefreshing = false
    public var hasStorageError = false
    public var hasTransferError = false
    public var hasEnvironmentMismatch = false
    public init(cached: CachedWatchSnapshot? = nil) { self.cached = cached }
}

@MainActor
public final class PhoneSnapshotReceiver {
    public private(set) var state = PhoneSnapshotState()
    public var onStateChange: ((PhoneSnapshotState) -> Void)?
    private let repository: any PhoneSnapshotRepository
    private let transport: any SnapshotTransport
    private let now: () -> Date
    private let environment: CloudEnvironment
    private var started = false
    private var receiveTask: Task<Void, Never>?
    private var refreshID: UUID?

    public init(repository: any PhoneSnapshotRepository, transport: any SnapshotTransport,
                now: @escaping () -> Date = { Date() }, environment: CloudEnvironment = .production) {
        self.repository = repository
        self.transport = transport
        self.now = now
        self.environment = environment
        transport.onSnapshot = { [weak self] data, peer in self?.receive(data, from: peer) }
        transport.onConnectionChange = { [weak self] connection in self?.connectionChanged(connection) }
    }

    public func start() async {
        guard !started else { return }
        started = true
        do {
            let saved = try await repository.load()
            // Older Debug caches have no environment tag; wait for a fresh,
            // tagged snapshot instead of displaying potentially mixed data.
            state.cached = saved?.snapshot.resolvedEnvironment == environment ? saved : nil
        }
        catch { state.hasStorageError = true }
        emit()
        transport.activate()
    }

    public func refresh() async {
        guard !state.isRefreshing else { return }
        // Re-read the system's last context too, allowing a failed cache write
        // to recover even when the watch is no longer directly reachable.
        transport.activate()
        guard state.connection.isActivated, state.connection.isReachable,
              let peer = state.connection.peerID else {
            state.hasTransferError = true
            emit()
            return
        }
        let refreshID = UUID()
        self.refreshID = refreshID
        state.isRefreshing = true
        state.hasTransferError = false
        emit()
        defer {
            if self.refreshID == refreshID {
                self.refreshID = nil
                state.isRefreshing = false
                emit()
            }
        }
        do {
            let data = try await transport.requestLatest()
            guard peer == state.connection.peerID, self.refreshID == refreshID else { return }
            receive(data, from: peer)
            await finishReceiving()
        } catch {
            if peer == state.connection.peerID, self.refreshID == refreshID { state.hasTransferError = true }
        }
    }

    public func finishReceiving() async { await receiveTask?.value }

    private func receive(_ data: Data, from peer: String) {
        guard state.connection.isActivated, state.connection.peerID == peer else { return }
        let snapshot: WatchSnapshot
        do { snapshot = try WatchSnapshotCodec.decode(data) }
        catch { state.hasTransferError = true; emit(); return }
        guard snapshot.resolvedEnvironment == environment else {
            state.hasEnvironmentMismatch = true; emit(); return
        }
        let previous = receiveTask
        let receivedAt = now()
        receiveTask = Task { [weak self, repository] in
            await previous?.value
            guard let self, self.state.connection.peerID == peer else { return }
            do {
                let saved = try await repository.accept(snapshot, from: peer, at: receivedAt)
                guard self.state.connection.peerID == peer else { return }
                self.state.cached = saved
                self.state.hasStorageError = false
                self.state.hasTransferError = false
                self.state.hasEnvironmentMismatch = false
            } catch {
                guard self.state.connection.peerID == peer else { return }
                self.state.hasStorageError = true
            }
            self.emit()
        }
    }

    private func connectionChanged(_ connection: SnapshotConnection) {
        let wasReachable = state.connection.isReachable
        let oldPeer = state.connection.peerID
        state.connection = connection
        if oldPeer != connection.peerID || !connection.isPaired {
            refreshID = nil
            state.isRefreshing = false
            state.hasTransferError = false
            state.hasEnvironmentMismatch = false
        }
        if connection.isActivated {
            if !connection.isPaired {
                state.cached = nil
            } else if let peer = connection.peerID, state.cached?.peerID != peer {
                state.cached = nil
            }
        }
        emit()
        if connection.isActivated, connection.isReachable,
           !wasReachable || oldPeer != connection.peerID {
            Task { [weak self] in await self?.refresh() }
        }
    }

    private func emit() { onStateChange?(state) }
}
