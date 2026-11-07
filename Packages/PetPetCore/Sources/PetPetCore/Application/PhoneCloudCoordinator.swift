import Foundation

public enum CloudPhase: String, Equatable, Sendable {
    case idle, waitingForWatch, uploading, waitingForReceipt, restoring
}

public struct PhoneCloudState: Equatable, Sendable {
    public var phase: CloudPhase = .idle
    public var operationID: UUID?
    public var lastBackupAt: Date?
    public var message: String?
    public var error: BackendError?
    public init() {}
}

@MainActor
public final class PhoneCloudCoordinator {
    public private(set) var state = PhoneCloudState()
    public var onStateChange: ((PhoneCloudState) -> Void)?
    public var onSessionChange: ((BackendSession?) -> Void)?
    private let environment: CloudEnvironment
    private let backend: BackendClient
    private let transport: any CloudTransport
    private let receipts: FileCloudReceiptStore
    private let directory: URL
    private let now: () -> Date
    private var activeAccountID: String?
    private var work: Task<Void, Never>?

    public init(backend: BackendClient, transport: any CloudTransport, receipts: FileCloudReceiptStore,
                directory: URL, environment: CloudEnvironment = .production, now: @escaping () -> Date = { Date() }) {
        self.backend = backend; self.transport = transport; self.receipts = receipts
        self.directory = directory; self.now = now; self.environment = environment
        transport.onCloudFile = { [weak self] url in self?.enqueue { await self?.receiveFile(url) } }
        transport.onCloudControl = { [weak self] data in self?.enqueue { await self?.receiveControl(data) } }
        transport.onCloudTransferError = { [weak self] _ in self?.fail(.watchUnavailable) }
    }

    public func synchronizeAccount() async {
        do {
            let session = try await backend.session()
            if activeAccountID != session?.accountID {
                state = PhoneCloudState(); activeAccountID = session?.accountID
            }
            state.lastBackupAt = try await session.mapAsync { try await self.receipts.lastBackupAt(accountID: $0.accountID) } ?? nil
            onSessionChange?(session)
            emit()
            guard transport.connection.isActivated else { return }
            try transport.enqueueCloudControl(encodeControl(.account(session.map {
                CloudAccount(id: $0.accountID, displayName: $0.nickname ?? $0.name ?? $0.email ?? "내 계정")
            })))
            for receipt in try await receipts.pending() {
                try transport.enqueueCloudControl(encodeControl(.backupSucceeded(receipt)))
            }
            if let session {
                for command in try await receipts.pendingRestores(accountID: session.accountID) {
                    try transport.enqueueCloudFile(outgoingFile(encodeFile(.restore(command)), operationID: command.operationID))
                    state.phase = .restoring; state.operationID = command.operationID
                    state.message = "워치의 복원 완료를 기다리고 있어요."
                }
                emit()
            }
        } catch { fail(error as? BackendError ?? .storage) }
    }

    public func requestBackup() async {
        do {
            guard let session = try await backend.session() else { throw BackendError.authenticationRequired }
            await synchronizeAccount()
            guard transport.connection.isActivated, transport.connection.isCounterpartInstalled else { throw BackendError.watchUnavailable }
            let operationID = UUID()
            state.operationID = operationID; state.phase = .waitingForWatch
            state.error = nil; state.message = "워치의 전체 기록을 기다리고 있어요."
            emit()
            try transport.enqueueCloudControl(encodeControl(.exportRequested(
                operationID: operationID,
                account: CloudAccount(id: session.accountID, displayName: session.nickname ?? session.email ?? "내 계정")
            )))
        } catch { fail(error as? BackendError ?? .network) }
    }

    public func prepareRestore() async throws -> WatchRestoreImport {
        guard let session = try await backend.session() else { throw BackendError.authenticationRequired }
        guard state.phase == .idle else { throw BackendError.watchUnavailable }
        let accountID = session.accountID
        let challengeData = try await transport.requestCloudChallenge()
        let target = try CloudWire.decodeChallenge(challengeData, environment: environment)
        let restored = try await backend.restore(accountID: accountID)
        guard try await backend.session()?.accountID == accountID else { throw BackendError.sessionChanged }
        return WatchRestoreImport(target: target, state: restored)
    }

    public func restore(_ command: WatchRestoreImport) async {
        do {
            guard try await backend.session()?.accountID == command.state.accountID else { throw BackendError.sessionChanged }
            state.phase = .restoring; state.operationID = command.operationID
            state.error = nil; state.message = "워치에 복원할 기록을 보내고 있어요."
            emit()
            let data = try encodeFile(.restore(command))
            try await receipts.saveRestore(command)
            let url = try outgoingFile(data, operationID: command.operationID)
            try transport.enqueueCloudFile(url)
        } catch { fail(error as? BackendError ?? .storage) }
    }

    public func finishWork() async { await work?.value }

    private func receiveFile(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        var operationID: UUID?
        var serverReceiptSaved = false
        do {
            guard case let .backup(export) = try CloudWire.decodeFile(Data(contentsOf: url), environment: environment) else { throw BackendError.invalidResponse }
            operationID = export.operationID
            guard let session = try await backend.session(), session.accountID == export.accountID else { throw BackendError.authenticationRequired }
            activeAccountID = session.accountID
            guard export.sequence > 0 else { throw BackendError.invalidResponse }
            if let receipt = try await receipts.receipt(operationID: export.operationID) {
                serverReceiptSaved = true
                try transport.enqueueCloudControl(encodeControl(.backupSucceeded(receipt)))
                return
            }
            let latest = try await receipts.latestSequence(accountID: export.accountID, storeID: export.storeID)
            guard export.sequence > latest else { throw BackendError.operationExpired }
            guard now().timeIntervalSince(export.capturedAt) < 86400 else { throw BackendError.operationExpired }
            state.phase = .uploading; state.operationID = export.operationID
            state.error = nil; state.message = "서버에 기록을 백업하고 있어요."
            emit()
            try await backend.saveBackup(export.request(), accountID: export.accountID)
            guard try await backend.session()?.accountID == export.accountID else { throw BackendError.sessionChanged }
            let receipt = CloudBackupReceipt(export: export, completedAt: now())
            try await receipts.save(receipt)
            serverReceiptSaved = true
            state.phase = .waitingForReceipt; state.lastBackupAt = receipt.completedAt
            state.message = "서버 저장 완료. 워치의 보상 지급을 기다리고 있어요."
            emit()
            try transport.enqueueCloudControl(encodeControl(.backupSucceeded(receipt)))
        } catch {
            let reason = error as? BackendError ?? .network
            if serverReceiptSaved {
                state.phase = .waitingForReceipt
                state.message = "서버 저장 완료. 워치가 연결되면 보상을 전달해요."
                state.error = nil
                emit()
                return
            }
            if let operationID {
                try? transport.enqueueCloudControl(encodeControl(.failed(operationID: operationID, reason: reason.rawDescription)))
            }
            if state.operationID == nil || state.operationID == operationID { fail(reason) }
            onSessionChange?(try? await backend.session())
        }
    }

    private func receiveControl(_ data: Data) async {
        do {
            switch try CloudWire.decodeControl(data, environment: environment) {
            case let .backupApplied(operationID, storeID):
                try await receipts.acknowledge(operationID: operationID, storeID: storeID)
                if state.operationID == operationID { complete("백업과 걸음수 보상을 완료했어요.") }
            case let .restoreApplied(operationID, storeID):
                try await receipts.completeRestore(operationID: operationID, storeID: storeID)
                if state.operationID == operationID { complete("워치에 기록을 복원했어요.") }
            case let .failed(operationID, reason):
                try await receipts.completeRestore(operationID: operationID)
                if state.operationID == operationID { fail(BackendError(rawDescription: reason)) }
            default: break
            }
        } catch { fail(.invalidResponse) }
    }

    private func encodeControl(_ value: CloudControl) throws -> Data {
        try CloudWire.encodeControl(value, environment: environment)
    }
    private func encodeFile(_ value: CloudFile) throws -> Data {
        try CloudWire.encodeFile(value, environment: environment)
    }
    private func enqueue(_ operation: @escaping () async -> Void) {
        let previous = work
        work = Task { await previous?.value; await operation() }
    }
    private func outgoingFile(_ data: Data, operationID: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(operationID.uuidString).appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }
    private func complete(_ message: String) {
        state.phase = .idle; state.operationID = nil; state.error = nil; state.message = message; emit()
    }
    private func fail(_ error: BackendError) {
        state.phase = .idle; state.operationID = nil; state.error = error; state.message = nil; emit()
    }
    private func emit() { onStateChange?(state) }
}

extension BackendError {
    public var rawDescription: String {
        switch self {
        case .accountMismatch: "accountMismatch"
        case .localStateChanged: "localStateChanged"
        case .authenticationRequired: "authenticationRequired"
        case .operationExpired: "operationExpired"
        default: "transferFailed"
        }
    }
    public init(rawDescription: String) {
        switch rawDescription {
        case "accountMismatch": self = .accountMismatch
        case "localStateChanged": self = .localStateChanged
        case "authenticationRequired": self = .authenticationRequired
        case "operationExpired": self = .operationExpired
        default: self = .network
        }
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        if let value = self { return try await transform(value) }
        return nil
    }
}
