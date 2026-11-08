import XCTest
@testable import PetPetCore

@MainActor
final class PhoneCloudCoordinatorTests: XCTestCase {
    private let now = Date()

    func testRepeatedBackupRequestDoesNotReplaceAnOperationWaitingForWatch() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, _, _) = try setup(folder: folder)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { await coordinator.requestBackup() } }
            await group.waitForAll()
        }
        let original = coordinator.state.operationID
        await coordinator.requestBackup()
        let requests = try transport.controls.map { try CloudWire.decodeControl($0) }.filter {
            if case .exportRequested = $0 { return true }; return false
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(coordinator.state.operationID, original)
    }

    func testBackupRequestKeepsARestoreResumedDuringAccountSynchronization() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, receipts, _) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let target = try await game.challenge()
        let command = WatchRestoreImport(target: target, state: try ServerRestoreState(accountID: "7", pet: target.pet, steps: []))
        try await receipts.saveRestore(command)
        await coordinator.requestBackup()
        XCTAssertEqual(coordinator.state.phase, .restoring)
        XCTAssertEqual(coordinator.state.operationID, command.operationID)
        XCTAssertEqual(transport.files.count, 1)
        let exports = try transport.controls.map { try CloudWire.decodeControl($0) }.filter {
            if case .exportRequested = $0 { return true }; return false
        }
        XCTAssertTrue(exports.isEmpty)
    }

    func testDevelopmentExportIsRejectedBeforeProductionServerRequest() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, _, http) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        let url = folder.appendingPathComponent("development-export.json")
        try CloudWire.encodeFile(.backup(export), environment: .development).write(to: url)
        transport.onCloudFile?(url)
        await coordinator.finishWork()
        let count = await http.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(coordinator.state.error, .environmentMismatch)
    }

    func testServerSuccessThenReceiptAndReplayNeverUploadOrRewardTwice() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, receipts, http) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let day = StepDay(containing: now).date
        try await game.save(DailyStepRecord(date: day, stepCount: 2500))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        await coordinator.synchronizeAccount()
        transport.onCloudFile?(try file(.backup(export), in: folder))
        await coordinator.finishWork()
        XCTAssertEqual(coordinator.state.phase, .waitingForReceipt)
        let storedReceipt = try await receipts.receipt(operationID: export.operationID)
        let receipt = try XCTUnwrap(storedReceipt)
        let paid = try await game.confirmBackup(receipt)
        XCTAssertEqual(paid.quantity(of: 1), 5)
        XCTAssertEqual(paid.quantity(of: 2), 1)
        transport.onCloudControl?(try CloudWire.encodeControl(.backupApplied(operationID: export.operationID, storeID: export.storeID)))
        await coordinator.finishWork()
        XCTAssertEqual(coordinator.state.phase, .idle)
        transport.onCloudFile?(try file(.backup(export), in: folder))
        await coordinator.finishWork()
        let count = await http.count
        XCTAssertEqual(count, 1)
        let duplicate = try await game.confirmBackup(receipt)
        XCTAssertEqual(duplicate, paid)
    }

    func testFailedServerRequestDoesNotCreateSuccessReceipt() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, receipts, _) = try setup(folder: folder, status: 500)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        transport.onCloudFile?(try file(.backup(export), in: folder))
        await coordinator.finishWork()
        XCTAssertEqual(coordinator.state.error, .http(500))
        let pending = try await receipts.pending()
        XCTAssertTrue(pending.isEmpty)
        let controls = try transport.controls.map { try CloudWire.decodeControl($0) }
        XCTAssertFalse(controls.contains { if case .backupSucceeded = $0 { return true }; return false })
        let local = try await game.load()
        XCTAssertEqual(local.quantity(of: 1), 3)
    }

    func testDisconnectedSuccessReceiptResendsAfterRestartWithoutAnotherHTTPPost() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, _, http) = try setup(folder: folder)
        transport.rejectReceipts = true
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        transport.onCloudFile?(try file(.backup(export), in: folder))
        await coordinator.finishWork()
        XCTAssertEqual(coordinator.state.phase, .waitingForReceipt)
        let store = FileCloudReceiptStore(fileURL: folder.appendingPathComponent("receipts"))
        let pending = try await store.pending()
        XCTAssertEqual(pending.count, 1)
        transport.rejectReceipts = false
        let backend = try BackendClient(baseURL: URL(string: "https://api.example.test/")!, transport: http, store: sessionStore())
        let restarted = PhoneCloudCoordinator(backend: backend, transport: transport, receipts: store, directory: folder.appendingPathComponent("outbox"))
        await restarted.synchronizeAccount()
        let controls = try transport.controls.map { try CloudWire.decodeControl($0) }
        XCTAssertTrue(controls.contains { if case .backupSucceeded = $0 { return true }; return false })
        let count = await http.count
        XCTAssertEqual(count, 1)
    }

    func testOlderExportCannotOverwriteNewerServerBackupOrHidePendingReceipt() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, _, http) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let old = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        try await game.save(DailyStepRecord(date: StepDay(containing: now).date, stepCount: 3000))
        let new = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        transport.onCloudFile?(try file(.backup(new), in: folder))
        await coordinator.finishWork()
        transport.onCloudFile?(try file(.backup(old), in: folder))
        await coordinator.finishWork()
        XCTAssertEqual(coordinator.state.operationID, new.operationID)
        XCTAssertEqual(coordinator.state.phase, .waitingForReceipt)
        let count = await http.count
        XCTAssertEqual(count, 1)
    }

    func testWrongAccountExportIsRejectedBeforeAnyServerRequest() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, _, http) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "different-account")
        transport.onCloudFile?(try file(.backup(export), in: folder))
        await coordinator.finishWork()
        let count = await http.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(coordinator.state.error, .authenticationRequired)
    }

    func testRestoreCommandPersistsUntilWatchAcknowledgesAndReplaysIdentically() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (coordinator, transport, receipts, _) = try setup(folder: folder)
        let game = FileGameRepository(directory: folder.appendingPathComponent("watch"))
        let target = try await game.challenge()
        var pet = target.pet
        pet.level = 4; pet.experience = 1
        let restored = try ServerRestoreState(accountID: "7", pet: pet, steps: [])
        let command = WatchRestoreImport(target: target, state: restored)
        await coordinator.restore(command)
        let pending = try await receipts.pendingRestores(accountID: "7")
        XCTAssertEqual(pending, [command])
        let applied = try await game.restore(command)
        XCTAssertEqual(applied.pet.level, 4)
        await coordinator.synchronizeAccount()
        let replay = try CloudWire.decodeFile(Data(contentsOf: transport.files.last!))
        guard case let .restore(replayed) = replay else { return XCTFail() }
        XCTAssertEqual(replayed, command)
        let duplicate = try await game.restore(replayed)
        XCTAssertEqual(duplicate, applied)
        transport.onCloudControl?(try CloudWire.encodeControl(.restoreApplied(operationID: command.operationID, storeID: target.storeID)))
        await coordinator.finishWork()
        let remaining = try await receipts.pendingRestores(accountID: "7")
        XCTAssertTrue(remaining.isEmpty)
    }

    private func setup(folder: URL, status: Int = 200) throws -> (PhoneCloudCoordinator, TestCloudTransport, FileCloudReceiptStore, CloudHTTP) {
        let http = CloudHTTP(status: status)
        let backend = try BackendClient(baseURL: URL(string: "https://api.example.test/")!, transport: http, store: sessionStore())
        let transport = TestCloudTransport()
        let receipts = FileCloudReceiptStore(fileURL: folder.appendingPathComponent("receipts"))
        return (PhoneCloudCoordinator(backend: backend, transport: transport, receipts: receipts,
                                      directory: folder.appendingPathComponent("outbox")), transport, receipts, http)
    }
    private func sessionStore() -> TestSessionStore {
        TestSessionStore(session: BackendSession(accountID: "7", serverOrigin: "https://api.example.test/",
                                                accessToken: "access", refreshToken: "refresh", email: nil, name: nil, nickname: nil))
    }
    private func file(_ value: CloudFile, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString)
        try CloudWire.encodeFile(value).write(to: url)
        return url
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
}

private actor CloudHTTP: BackendHTTPTransport {
    let status: Int
    var count = 0
    init(status: Int) { self.status = status }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        count += 1
        return BackendHTTPResponse(statusCode: status, data: Data("{}".utf8))
    }
}

@MainActor
private final class TestCloudTransport: CloudTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: true, isCounterpartInstalled: true, isReachable: true, peerID: "watch")
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    var controls: [Data] = []
    var files: [URL] = []
    var rejectReceipts = false
    func enqueueCloudControl(_ data: Data) throws {
        if rejectReceipts, case .backupSucceeded = try CloudWire.decodeControl(data) { throw BackendError.watchUnavailable }
        controls.append(data)
    }
    func enqueueCloudFile(_ url: URL) { files.append(url) }
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
}
