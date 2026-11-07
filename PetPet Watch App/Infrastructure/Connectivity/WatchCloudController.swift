import Combine
import Foundation
import PetPetCore

@MainActor
final class WatchCloudController: ObservableObject {
    @Published private(set) var account: CloudAccount?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var lastBackupAt: Date?
    let environment: CloudEnvironment
    var isDevelopment: Bool { environment == .development }
    private let game: FileGameRepository
    private let transport: any CloudTransport
    private let home: WatchHomeViewModel
    private let pet: PetProgressViewModel
    private let directory: URL
    private var work: Task<Void, Never>?
    private var activeOperation: UUID?

    init(game: FileGameRepository, transport: any CloudTransport,
         home: WatchHomeViewModel, pet: PetProgressViewModel, directory: URL, environment: CloudEnvironment = .production) {
        self.game = game; self.transport = transport
        self.home = home; self.pet = pet; self.directory = directory; self.environment = environment
        let cached = directory.appendingPathComponent("cloud-account-v1.json")
        if let data = try? Data(contentsOf: cached) { account = try? JSONDecoder().decode(CloudAccount?.self, from: data) }
        transport.onCloudControl = { [weak self] data in self?.enqueue { await self?.receiveControl(data) } }
        transport.onCloudFile = { [weak self] url in self?.enqueue { await self?.receiveFile(url) } }
        transport.onCloudChallenge = { [weak game] in
            guard let game else { throw BackendError.watchUnavailable }
            return try CloudWire.encodeChallenge(await game.challenge(), environment: environment)
        }
        transport.onCloudTransferError = { [weak self] _ in self?.fail(.watchUnavailable) }
    }

    func start() async { lastBackupAt = try? await game.lastBackupAt() }
    func finishWork() async { await work?.value }

    func requestBackup() async {
        guard !isBusy else { return }
        guard let account else { fail(.authenticationRequired); return }
        await export(operationID: UUID(), account: account)
    }

    private func export(operationID: UUID, account: CloudAccount) async {
        do {
            if try await game.isBackupComplete(operationID: operationID) { return }
            guard self.account?.id == account.id else { throw BackendError.authenticationRequired }
            activeOperation = operationID
            isBusy = true; message = "아이폰으로 백업 기록을 보내고 있어요."
            await home.flush()
            guard !home.state.hasStorageError else { throw BackendError.storage }
            let export = try await game.prepareBackup(operationID: operationID, accountID: account.id)
            let data = try encodeFile(.backup(export))
            let outbox = directory.appendingPathComponent("CloudOutbox", isDirectory: true)
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let url = outbox.appendingPathComponent("\(operationID.uuidString)-\(UUID().uuidString)").appendingPathExtension("json")
            try data.write(to: url, options: .atomic)
            try transport.enqueueCloudFile(url)
            message = "아이폰의 서버 백업 완료를 기다리고 있어요."
        } catch {
            try? await game.cancelBackup(operationID: operationID)
            fail(error as? BackendError ?? .storage)
            try? transport.enqueueCloudControl(encodeControl(.failed(operationID: operationID,
                reason: (error as? BackendError ?? .storage).rawDescription)))
        }
    }

    private func receiveControl(_ data: Data) async {
        var operationID: UUID?
        do {
            switch try CloudWire.decodeControl(data, environment: environment) {
            case let .account(account):
                self.account = account
                if !isBusy { message = nil }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(account).write(to: directory.appendingPathComponent("cloud-account-v1.json"), options: .atomic)
            case let .exportRequested(operationID, account):
                await export(operationID: operationID, account: account)
            case let .backupSucceeded(receipt):
                operationID = receipt.operationID
                _ = try await game.confirmBackup(receipt)
                await pet.reload()
                lastBackupAt = try await game.lastBackupAt()
                if activeOperation == nil || activeOperation == receipt.operationID {
                    isBusy = false; activeOperation = nil; message = "서버 백업과 걸음수 보상을 완료했어요."
                }
                try transport.enqueueCloudControl(encodeControl(.backupApplied(
                    operationID: receipt.operationID, storeID: receipt.storeID)))
            case let .failed(failedID, reason):
                operationID = failedID
                try await game.cancelBackup(operationID: failedID)
                if activeOperation == nil || activeOperation == failedID { fail(BackendError(rawDescription: reason)) }
            default: break
            }
        } catch {
            if activeOperation == nil || activeOperation == operationID { fail(error as? BackendError ?? .storage) }
        }
    }

    private func receiveFile(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        var operationID: UUID?
        do {
            guard case let .restore(command) = try CloudWire.decodeFile(Data(contentsOf: url), environment: environment) else { throw BackendError.invalidResponse }
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
}
