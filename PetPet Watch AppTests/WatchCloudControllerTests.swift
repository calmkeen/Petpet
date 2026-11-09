import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor
final class WatchCloudControllerTests: XCTestCase {
    func testConcurrentWatchBackupTapsQueueOneExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { await controller.requestBackup() } }
            await group.waitForAll()
        }
        XCTAssertTrue(controller.isBusy)
        XCTAssertEqual(transport.files.count, 1)
        let exports = try transport.files.map { try CloudWire.decodeFile(Data(contentsOf: $0)) }
        XCTAssertEqual(exports.count, 1)
    }

    func testFailedWatchExportReleasesBusyAndCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        transport.rejectFiles = true
        await controller.requestBackup()
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(transport.files.isEmpty)
        transport.rejectFiles = false
        await controller.requestBackup()
        XCTAssertTrue(controller.isBusy)
        XCTAssertEqual(transport.files.count, 1)
    }

    func testLogoutReleasesWaitingBackupAndReloginCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        await controller.requestBackup()
        transport.onCloudControl?(try CloudWire.encodeControl(.account(nil)))
        await controller.finishWork()
        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.message)
        transport.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test"))))
        await controller.finishWork()
        await controller.requestBackup()
        XCTAssertEqual(transport.files.count, 2)
    }

    func testNicknameUpdateKeepsCurrentBackupBusy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        await controller.requestBackup()
        transport.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Renamed"))))
        await controller.finishWork()
        XCTAssertTrue(controller.isBusy)
        await controller.requestBackup()
        XCTAssertEqual(transport.files.count, 1)
    }

    func testLateReceiptAfterLogoutStillAppliesOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        await controller.requestBackup()
        guard case let .backup(export) = try CloudWire.decodeFile(Data(contentsOf: transport.files[0])) else { return XCTFail() }
        transport.onCloudControl?(try CloudWire.encodeControl(.account(nil)))
        await controller.finishWork()
        let receipt = CloudBackupReceipt(export: export, completedAt: Date())
        for _ in 0..<2 { transport.onCloudControl?(try CloudWire.encodeControl(.backupSucceeded(receipt))); await controller.finishWork() }
        XCTAssertNil(controller.account); XCTAssertFalse(controller.isBusy)
        let progress = try await FileGameRepository(directory: directory).load()
        XCTAssertEqual(progress.quantity(of: 2), 1, "A valid queued receipt must survive logout and reward only once")
    }

    func testOldFailureCannotUnlockNewBackupAfterRelogin() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, transport) = try await setup(directory)
        await controller.requestBackup()
        guard case let .backup(old) = try CloudWire.decodeFile(Data(contentsOf: transport.files[0])) else { return XCTFail() }
        transport.onCloudControl?(try CloudWire.encodeControl(.account(nil)))
        await controller.finishWork()
        transport.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test"))))
        await controller.finishWork(); await controller.requestBackup()
        transport.onCloudControl?(try CloudWire.encodeControl(.failed(operationID: old.operationID, reason: BackendError.network.rawDescription)))
        await controller.finishWork()
        XCTAssertEqual(transport.files.count, 2); XCTAssertTrue(controller.isBusy)
    }

    private func setup(_ directory: URL) async throws -> (WatchCloudController, WatchBackupProbe) {
        let game = FileGameRepository(directory: directory)
        let transport = WatchBackupProbe()
        let home = WatchHomeViewModel(stepCounter: IdleFlowCounter(), repository: game)
        let pet = PetProgressViewModel(repository: game, history: game)
        let controller = WatchCloudController(game: game, transport: transport, home: home, pet: pet, directory: directory)
        transport.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test"))))
        await controller.finishWork()
        return (controller, transport)
    }
}

@MainActor private final class IdleFlowCounter: StepCounting {
    func steps(from start: Date, to end: Date) async throws -> Int { 0 }
    func startUpdates(from date: Date, onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void) {}
    func stopUpdates() {}
}
@MainActor private final class WatchBackupProbe: CloudTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: true, isCounterpartInstalled: true, isReachable: true)
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    var files: [URL] = []
    var rejectFiles = false
    func enqueueCloudControl(_ data: Data) {}
    func enqueueCloudFile(_ url: URL) throws {
        if rejectFiles { throw BackendError.watchUnavailable }
        files.append(url)
    }
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
}
