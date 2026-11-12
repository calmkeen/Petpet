import Foundation

public struct WatchStandaloneState: Equatable, Sendable {
    public var isSelected = false
    public var account: CloudAccount?
    public var isBusy = false
    public var lastBackupAt: Date?
    public var message: String?
    public init() {}
}

/// A credential-owning watch host. Neither credentials nor direct requests go
/// through WatchConnectivity. The same HTTP/refresh/SSE client serves both OSes.
@MainActor
public final class WatchStandaloneService {
    public private(set) var state = WatchStandaloneState()
    public var onStateChange: ((WatchStandaloneState) -> Void)?
    private struct Mode: Codable { var version = 1; var selected: Bool }
    private let backend: BackendClient
    private let game: FileGameRepository
    private let receipts: FileCloudReceiptStore
    private let modeURL: URL
    private let featureWire: LocalFeatureWire
    private let features: PhoneFeatureCoordinator
    private var generation = 0
    private var started = false
    private var modeError = false
    private let now: () -> Date

    public init(backend: BackendClient, game: FileGameRepository, receipts: FileCloudReceiptStore,
                modeURL: URL, environment: CloudEnvironment, now: @escaping () -> Date = Date.init) {
        self.backend = backend; self.game = game; self.receipts = receipts; self.modeURL = modeURL; self.now = now
        let wire = LocalFeatureWire(); featureWire = wire
        features = PhoneFeatureCoordinator(backend: backend, transport: wire, environment: environment)
        if FileManager.default.fileExists(atPath: modeURL.path) {
            if let data = try? Data(contentsOf: modeURL), let mode = try? JSONDecoder().decode(Mode.self, from: data), mode.version == 1 {
                state.isSelected = mode.selected
            } else { state.isSelected = true; modeError = true }
        }
        features.onSessionInvalidated = { [weak self] in await self?.refreshSession() }
    }

    public func start() async throws {
        guard !started else { await refreshSession(); return }
        guard !modeError else { throw BackendError.storage }
        started = true
        await backend.setSessionInvalidationHandler { [weak self] in await self?.refreshSession() }
        do {
            if try await backend.session() != nil, !state.isSelected { try select(true) }
            try await recoverReceipts()
            state.lastBackupAt = try await game.lastBackupAt()
            await refreshSession()
        } catch { started = false; state.message = error.localizedDescription; emit(); throw error }
    }

    public func refreshSession() async {
        guard state.isSelected else { return }
        do {
            let session = try await backend.session()
            let account = session.map(Self.account)
            if state.account?.id != account?.id {
                features.accountChanged()
                if state.account != nil, account == nil {
                    generation += 1; state.isBusy = false
                    state.message = "워치 계정이 만료됐어요. 워치에서 다시 로그인해 주세요."
                }
            }
            state.account = account; emit()
        } catch { state.message = BackendError.storage.localizedDescription; emit() }
    }

    public func signIn(_ identity: AppleIdentity) async throws {
        try await authenticate { try await self.backend.signIn(identity) }
    }
    #if DEBUG
    public func signInForDevelopment() async throws {
        try await authenticate { try await self.backend.signInForDevelopment() }
    }
    #endif
    private func authenticate(_ action: () async throws -> BackendSession) async throws {
        guard !state.isBusy else { throw BackendError.operationExpired }
        try select(true)
        generation += 1; let token = generation
        features.accountChanged(); state.account = nil; state.isBusy = true; state.message = nil; emit()
        defer { if token == generation { state.isBusy = false; emit() } }
        do {
            let session = try await action()
            guard token == generation else { throw BackendError.sessionChanged }
            state.account = Self.account(session); state.message = "워치 단독 연결이 완료됐어요."; emit()
        } catch {
            if token == generation { await refreshSession(); state.message = error.localizedDescription; emit() }
            throw error
        }
    }
    public func signOut() async throws {
        generation += 1; features.accountChanged()
        do { try await backend.signOut() }
        catch { state.isBusy = false; await refreshSession(); throw error }
        state.account = nil; state.isBusy = false; state.message = "워치에서 로그아웃했어요."; emit()
    }
    public func useCompanion() async throws {
        try await signOut()
        try select(false)
        state.message = nil; emit()
    }
    public func checkAppleCredential(using check: (String) async throws -> Bool) async {
        guard state.isSelected, let session = try? await backend.session(), session.identityProvider == .apple,
              let subject = session.providerSubject else { return }
        let token = generation
        do {
            let valid = try await check(subject)
            guard token == generation, try await backend.session() == session else { return }
            if !valid { try await signOut(); state.message = "Apple 연결이 해제됐어요. 워치에서 다시 로그인해 주세요."; emit() }
        } catch { /* A failed state query does not prove revocation. */ }
    }

    public func checkNickname(_ value: String, accountID: String) async throws -> Bool {
        try await requireAccount(accountID)
        do { return try await backend.checkNickname(value, accountID: accountID) }
        catch { await refreshSession(); throw error }
    }
    public func updateNickname(_ value: String, accountID: String) async throws -> String {
        try await requireAccount(accountID)
        do {
            let name = try await backend.updateNickname(value, accountID: accountID)
            await refreshSession(); return name
        } catch { await refreshSession(); throw error }
    }
    public func refreshProfile() async throws {
        guard state.isSelected, let id = state.account?.id else { return }
        _ = try await backend.profileNickname(accountID: id)
        await refreshSession()
    }
    public func requestFeature(_ data: Data) async throws -> Data {
        guard state.isSelected else { throw BackendError.sessionChanged }
        return try await featureWire.requestFeature(data)
    }

    public func backup() async throws {
        guard !state.isBusy else { throw BackendError.operationExpired }
        guard let id = state.account?.id else { throw BackendError.authenticationRequired }
        state.isBusy = true; state.message = "워치에서 직접 백업하고 있어요."; emit()
        let token = generation, operationID = UUID()
        var savedReceipt = false
        defer { if token == generation { state.isBusy = false; emit() } }
        do {
            try await requireAccount(id)
            try await recoverReceipts()
            let export = try await game.prepareBackup(operationID: operationID, accountID: id)
            guard token == generation else { throw BackendError.sessionChanged }
            try await backend.saveBackup(export.request(), accountID: id)
            guard token == generation else { throw BackendError.sessionChanged }
            let receipt = CloudBackupReceipt(export: export, completedAt: now())
            // Commit the server acknowledgement before awarding local food.
            try await receipts.save(receipt); savedReceipt = true
            _ = try await game.confirmBackup(receipt)
            try await receipts.acknowledge(operationID: receipt.operationID, storeID: receipt.storeID)
            if token == generation {
                state.lastBackupAt = receipt.completedAt
                state.message = "워치 단독 백업과 걸음수 보상을 완료했어요."; emit()
            }
        } catch {
            if !savedReceipt { try? await game.cancelBackup(operationID: operationID) }
            if token == generation {
                state.message = savedReceipt ? "서버 저장은 완료됐어요. 앱을 다시 열면 보상을 마저 반영해요." : error.localizedDescription
                await refreshSession(); emit()
            }
            throw error
        }
    }
    public func prepareRestore() async throws -> WatchRestoreImport {
        guard !state.isBusy, let id = state.account?.id else { throw BackendError.authenticationRequired }
        try await requireAccount(id)
        let token = generation
        let target = try await game.challenge()
        let restored = try await backend.restore(accountID: id)
        guard token == generation else { throw BackendError.sessionChanged }
        return WatchRestoreImport(target: target, state: restored)
    }
    public func restore(_ command: WatchRestoreImport) async throws {
        guard !state.isBusy else { throw BackendError.operationExpired }
        try await requireAccount(command.state.accountID)
        state.isBusy = true; emit()
        let token = generation
        defer { if token == generation { state.isBusy = false; emit() } }
        try await receipts.saveRestore(command)
        guard token == generation else {
            try await receipts.completeRestore(operationID: command.operationID)
            throw BackendError.sessionChanged
        }
        do { _ = try await game.restore(command) }
        catch let error as BackendError where error == .localStateChanged || error == .accountMismatch {
            try await receipts.completeRestore(operationID: command.operationID, storeID: command.target.storeID)
            throw error
        }
        try await receipts.completeRestore(operationID: command.operationID, storeID: command.target.storeID)
        state.lastBackupAt = try await game.lastBackupAt()
        state.message = "워치에서 백업 기록을 복원했어요."; emit()
    }
    private func recoverReceipts() async throws {
        for receipt in try await receipts.pending() {
            _ = try await game.confirmBackup(receipt)
            try await receipts.acknowledge(operationID: receipt.operationID, storeID: receipt.storeID)
        }
        state.lastBackupAt = try await game.lastBackupAt()
        if let id = try await backend.session()?.accountID, state.isSelected {
            for command in try await receipts.pendingRestores(accountID: id) {
                do {
                    _ = try await game.restore(command)
                    try await receipts.completeRestore(operationID: command.operationID, storeID: command.target.storeID)
                } catch let error as BackendError where error == .localStateChanged || error == .accountMismatch {
                    // Never overwrite play that changed after the approved preview.
                    try await receipts.completeRestore(operationID: command.operationID, storeID: command.target.storeID)
                    state.message = error.localizedDescription
                }
            }
        }
    }
    private func requireAccount(_ id: String) async throws {
        guard state.isSelected, try await backend.session()?.accountID == id else { throw BackendError.authenticationRequired }
    }
    private static func account(_ session: BackendSession) -> CloudAccount {
        CloudAccount(id: session.accountID, displayName: session.nickname ?? session.name ?? "내 계정")
    }
    private func select(_ selected: Bool) throws {
        try FileManager.default.createDirectory(at: modeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Mode(selected: selected)).write(to: modeURL, options: .atomic)
        state.isSelected = selected
    }
    private func emit() { onStateChange?(state) }
}

@MainActor private final class LocalFeatureWire: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    func requestFeature(_ data: Data) async throws -> Data {
        guard let onFeatureRequest else { throw BackendError.configurationMissing }
        return try await onFeatureRequest(data)
    }
}
