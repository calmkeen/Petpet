import Combine
import Foundation
import PetPetCore
import AuthenticationServices

@MainActor
final class WatchCloudController: ObservableObject {
    @Published private(set) var account: CloudAccount?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var lastBackupAt: Date?
    @Published private(set) var usesStandalone = false
    @Published private(set) var restorePreview: WatchRestoreImport?
    @Published private(set) var isPreparingRestore = false
    var supportsStandalone: Bool { standalone != nil }
    var connectionNote: String {
        usesStandalone ? (isDevelopment ? "Debug · 워치 내부 모의 서버로 연결해요." : "워치에서 직접 연결해요. 인터넷이 필요해요.") : "아이폰의 PetPet과 연결이 필요해요."
    }
    let environment: CloudEnvironment
    var isDevelopment: Bool { environment == .development }
    private let game: FileGameRepository
    private let transport: any CloudTransport
    private let home: WatchHomeViewModel
    private let pet: PetProgressViewModel
    private let directory: URL
    private let nicknameRelay: WatchNicknameRelay
    private let standalone: WatchStandaloneService?
    private let apple = WatchAppleSignInProvider()
    private var companionAccount: CloudAccount?
    private var profileRefresh: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var activeOperation: UUID?

    init(game: FileGameRepository, transport: any CloudTransport,
         home: WatchHomeViewModel, pet: PetProgressViewModel, directory: URL, environment: CloudEnvironment = .production,
         standalone: WatchStandaloneService? = nil) {
        self.game = game; self.transport = transport
        self.home = home; self.pet = pet; self.directory = directory; self.environment = environment
        self.standalone = standalone
        nicknameRelay = WatchNicknameRelay(transport: transport, environment: environment)
        let cached = directory.appendingPathComponent("cloud-account-v1.json")
        if let data = try? Data(contentsOf: cached) { account = try? JSONDecoder().decode(CloudAccount?.self, from: data) }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("cloud-companion-account-v1.json")) {
            companionAccount = try? JSONDecoder().decode(CloudAccount?.self, from: data)
        } else if standalone?.state.isSelected != true { companionAccount = account }
        nicknameRelay.setAccount(account)
        transport.onCloudControl = { [weak self] data in self?.enqueue { await self?.receiveControl(data) } }
        transport.onCloudFile = { [weak self] url in self?.enqueue { await self?.receiveFile(url) } }
        transport.onCloudChallenge = { [weak game] in
            guard let game else { throw BackendError.watchUnavailable }
            return try CloudWire.encodeChallenge(await game.challenge(), environment: environment)
        }
        transport.onCloudTransferError = { [weak self] _ in
            guard let self, !self.usesStandalone else { return }
            self.fail(.watchUnavailable)
        }
        standalone?.onStateChange = { [weak self] state in self?.applyStandalone(state) }
        if let standalone { applyStandalone(standalone.state) }
    }

    func start() async {
        do { try await standalone?.start() } catch { message = error.localizedDescription }
        lastBackupAt = try? await game.lastBackupAt()
        profileRefresh?.cancel()
        if usesStandalone {
            profileRefresh = Task { [weak self] in
                guard let self, let standalone else { return }
                await standalone.checkAppleCredential { try await self.apple.credentialIsAuthorized(for: $0) }
                try? await standalone.refreshProfile()
            }
        }
    }
    func finishWork() async { await work?.value }

    func makeNicknameEditor() -> NicknameEditor {
        let id = account?.id
        return NicknameEditor(currentNickname: account?.displayName ?? "미설정", check: { [weak self] value in
            guard let self, let id, self.account?.id == id else { throw BackendError.authenticationRequired }
            if let direct = self.standalone, self.usesStandalone { return try await direct.checkNickname(value, accountID: id) }
            return try await self.nicknameRelay.check(value)
        }, update: { [weak self] value in
            guard let self, let id, self.account?.id == id else { throw BackendError.authenticationRequired }
            let name: String
            if let direct = self.standalone, self.usesStandalone { name = try await direct.updateNickname(value, accountID: id) }
            else { name = try await self.nicknameRelay.update(value) }
            guard self.account?.id == id else { throw BackendError.sessionChanged }
            let updated = CloudAccount(id: id, displayName: name)
            try JSONEncoder().encode(updated).write(to: self.directory.appendingPathComponent("cloud-account-v1.json"), options: .atomic)
            self.account = updated; self.nicknameRelay.setAccount(updated)
            return name
        })
    }

    func requestBackup() async {
        guard !isBusy else { return }
        guard let account else { fail(.authenticationRequired); return }
        if let standalone, usesStandalone {
            // Reserve the UI operation before flushing sensor storage suspends.
            isBusy = true
            defer { isBusy = standalone.state.isBusy }
            do {
                await home.flush()
                guard !home.state.hasStorageError else { throw BackendError.storage }
                try await standalone.backup()
                await pet.reload(); lastBackupAt = try await game.lastBackupAt()
            } catch { message = error.localizedDescription }
            return
        }
        let operationID = UUID()
        activeOperation = operationID
        isBusy = true
        await export(operationID: operationID, account: account)
    }

    private func export(operationID: UUID, account: CloudAccount) async {
        do {
            if try await game.isBackupComplete(operationID: operationID) { return }
            guard self.account?.id == account.id else { throw BackendError.authenticationRequired }
            activeOperation = operationID
            isBusy = true; message = "아이폰으로 백업 기록을 보내고 있어요."
            await home.flush()
            guard self.account?.id == account.id, activeOperation == operationID else { throw BackendError.sessionChanged }
            guard !home.state.hasStorageError else { throw BackendError.storage }
            let export = try await game.prepareBackup(operationID: operationID, accountID: account.id)
            guard self.account?.id == account.id, activeOperation == operationID else { throw BackendError.sessionChanged }
            let data = try encodeFile(.backup(export))
            let outbox = directory.appendingPathComponent("CloudOutbox", isDirectory: true)
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let url = outbox.appendingPathComponent("\(operationID.uuidString)-\(UUID().uuidString)").appendingPathExtension("json")
            try data.write(to: url, options: .atomic)
            try transport.enqueueCloudFile(url)
            message = "아이폰의 서버 백업 완료를 기다리고 있어요."
        } catch {
            try? await game.cancelBackup(operationID: operationID)
            if activeOperation == operationID { fail(error as? BackendError ?? .storage) }
            try? transport.enqueueCloudControl(encodeControl(.failed(operationID: operationID,
                reason: (error as? BackendError ?? .storage).rawDescription)))
        }
    }

    private func receiveControl(_ data: Data) async {
        var operationID: UUID?
        do {
            switch try CloudWire.decodeControl(data, environment: environment) {
            case let .account(account):
                companionAccount = account
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(account).write(to: directory.appendingPathComponent("cloud-companion-account-v1.json"), options: .atomic)
                if usesStandalone { return }
                if self.account?.id != account?.id {
                    activeOperation = nil
                    isBusy = false
                    message = nil
                }
                self.account = account
                nicknameRelay.setAccount(account)
                if !isBusy { message = nil }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(account).write(to: directory.appendingPathComponent("cloud-account-v1.json"), options: .atomic)
            case let .exportRequested(operationID, account):
                if usesStandalone, isBusy {
                    try? transport.enqueueCloudControl(encodeControl(.failed(operationID: operationID, reason: BackendError.operationExpired.rawDescription)))
                    return
                }
                await export(operationID: operationID, account: account)
            case let .backupSucceeded(receipt):
                operationID = receipt.operationID
                _ = try await game.confirmBackup(receipt)
                await pet.reload()
                lastBackupAt = try await game.lastBackupAt()
                if !usesStandalone, activeOperation == nil || activeOperation == receipt.operationID {
                    isBusy = false; activeOperation = nil; message = "서버 백업과 걸음수 보상을 완료했어요."
                }
                try transport.enqueueCloudControl(encodeControl(.backupApplied(
                    operationID: receipt.operationID, storeID: receipt.storeID)))
            case let .failed(failedID, reason):
                operationID = failedID
                try await game.cancelBackup(operationID: failedID)
                if !usesStandalone, activeOperation == nil || activeOperation == failedID { fail(BackendError(rawDescription: reason)) }
            default: break
            }
        } catch {
            if !usesStandalone, activeOperation == nil || activeOperation == operationID { fail(error as? BackendError ?? .storage) }
        }
    }

    private func receiveFile(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        var operationID: UUID?
        do {
            guard case let .restore(command) = try CloudWire.decodeFile(Data(contentsOf: url), environment: environment) else { throw BackendError.invalidResponse }
            if usesStandalone, isBusy {
                try? transport.enqueueCloudControl(encodeControl(.failed(operationID: command.operationID, reason: BackendError.operationExpired.rawDescription)))
                return
            }
            operationID = command.operationID
            activeOperation = command.operationID
            guard account?.id == command.state.accountID else { throw BackendError.accountMismatch }
            isBusy = true; message = "서버 기록을 복원하고 있어요."
            await home.suspendForRestore()
            defer { Task { await home.resumeAfterRestore() } }
            _ = try await game.restore(command)
            await pet.reload()
            lastBackupAt = try await game.lastBackupAt()
            isBusy = false; activeOperation = nil; message = "서버 기록을 복원했어요."
            try transport.enqueueCloudControl(encodeControl(.restoreApplied(
                operationID: command.operationID, storeID: command.target.storeID)))
        } catch {
            let error = error as? BackendError ?? .storage
            fail(error)
            if let operationID { try? transport.enqueueCloudControl(encodeControl(.failed(operationID: operationID, reason: error.rawDescription))) }
        }
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
    private func fail(_ error: BackendError) { isBusy = false; activeOperation = nil; message = error.localizedDescription }

    private func applyStandalone(_ state: WatchStandaloneState) {
        let wasSelected = usesStandalone
        usesStandalone = state.isSelected
        if state.isSelected {
            account = state.account; isBusy = state.isBusy; message = state.message
            if let date = state.lastBackupAt { lastBackupAt = date }
        } else if wasSelected {
            account = companionAccount; isBusy = false; message = nil
        }
        nicknameRelay.setAccount(account)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(account).write(to: directory.appendingPathComponent("cloud-account-v1.json"), options: .atomic)
    }
    #if DEBUG
    func signInStandaloneForDevelopment() async {
        do { try await standalone?.signInForDevelopment() } catch { message = error.localizedDescription }
    }
    #endif
    func beginStandaloneSignIn(_ request: ASAuthorizationAppleIDRequest) {
        do { try apple.configure(request) } catch { message = error.localizedDescription }
    }
    func completeStandaloneSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            let identity = try apple.identity(from: result)
            guard let standalone else { throw BackendError.configurationMissing }
            try await standalone.signIn(identity)
            apple.confirmProfile(for: identity.userIdentifier)
        } catch is CancellationError { }
        catch { message = error.localizedDescription }
    }
    func signOutStandalone() async {
        do { try await standalone?.signOut(); restorePreview = nil } catch { message = error.localizedDescription }
    }
    func useCompanion() async {
        do { try await standalone?.useCompanion(); restorePreview = nil } catch { message = error.localizedDescription }
    }
    func prepareStandaloneRestore() async {
        guard let standalone, usesStandalone, !isPreparingRestore else { return }
        isPreparingRestore = true; defer { isPreparingRestore = false }
        do { restorePreview = try await standalone.prepareRestore() } catch { message = error.localizedDescription }
    }
    func cancelStandaloneRestorePreview() { restorePreview = nil }
    func confirmStandaloneRestore() async {
        guard let standalone, let preview = restorePreview else { return }
        do {
            await home.suspendForRestore()
            defer { Task { await self.home.resumeAfterRestore() } }
            try await standalone.restore(preview)
            await pet.reload(); restorePreview = nil
        } catch { message = error.localizedDescription; restorePreview = nil }
    }
}
