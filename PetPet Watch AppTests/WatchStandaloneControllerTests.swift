import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor final class WatchStandaloneControllerTests: XCTestCase {
    func testDirectWatchAccountIgnoresLatePhoneLoginAndLogout() async throws {
        let f = try Context(); defer { f.remove() }
        await f.controller.start(); await f.controller.signInStandaloneForDevelopment()
        let watch = f.controller.account
        XCTAssertNotNil(watch); XCTAssertTrue(f.controller.usesStandalone)
        for account in [CloudAccount(id: "other-phone-user", displayName: "Phone"), nil] {
            f.transport.onCloudControl?(try CloudWire.encodeControl(.account(account), environment: .development))
            await f.controller.finishWork()
            XCTAssertEqual(f.controller.account, watch)
        }
        f.transport.onCloudTransferError?("phone disconnected")
        XCTAssertEqual(f.controller.account, watch)
        XCTAssertFalse(f.controller.message?.contains("연결할 수 없어요") ?? false)
    }
    func testDirectBackupAndRestoreSendNoPhoneFiles() async throws {
        let f = try Context(); defer { f.remove() }
        await f.controller.start(); await f.controller.signInStandaloneForDevelopment()
        await f.controller.requestBackup()
        XCTAssertFalse(f.controller.isBusy); XCTAssertNotNil(f.controller.lastBackupAt)
        XCTAssertEqual(f.transport.files, 0)
        await f.controller.prepareStandaloneRestore()
        XCTAssertNotNil(f.controller.restorePreview)
        await f.controller.confirmStandaloneRestore()
        XCTAssertNil(f.controller.restorePreview)
        XCTAssertEqual(f.controller.message, "워치에서 백업 기록을 복원했어요.")
        XCTAssertEqual(f.transport.files, 0)
    }
    func testExplicitCompanionSwitchRestoresLatestPhoneAccount() async throws {
        let f = try Context(); defer { f.remove() }
        await f.controller.start(); await f.controller.signInStandaloneForDevelopment()
        let phone = CloudAccount(id: "phone", displayName: "Phone account")
        f.transport.onCloudControl?(try CloudWire.encodeControl(.account(phone), environment: .development))
        await f.controller.finishWork()
        await f.controller.signOutStandalone()
        XCTAssertTrue(f.controller.usesStandalone); XCTAssertNil(f.controller.account)
        await f.controller.useCompanion()
        XCTAssertFalse(f.controller.usesStandalone); XCTAssertEqual(f.controller.account, phone)
    }
}
@MainActor private struct Context {
    let root: URL
    let controller: WatchCloudController
    let transport = StandaloneCloudProbe()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let game = FileGameRepository(directory: root)
        let client = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL,
            transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server")), store: StandaloneMemorySession())
        let service = WatchStandaloneService(backend: client, game: game,
            receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts")),
            modeURL: root.appendingPathComponent("mode"), environment: .development)
        controller = WatchCloudController(game: game, transport: transport,
            home: WatchHomeViewModel(stepCounter: StandaloneIdleCounter(), repository: game),
            pet: PetProgressViewModel(repository: game, history: game), directory: root, environment: .development, standalone: service)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private actor StandaloneMemorySession: BackendSessionStore {
    var value: BackendSession?
    func load() throws -> BackendSession? { value }
    func save(_ session: BackendSession) throws { value = session }
    func clear() throws { value = nil }
}
@MainActor private final class StandaloneIdleCounter: StepCounting {
    func steps(from start: Date, to end: Date) async throws -> Int { 0 }
    func startUpdates(from date: Date, onUpdate: @escaping @MainActor (Result<Int, StepCountingError>) -> Void) {}
    func stopUpdates() {}
}
@MainActor private final class StandaloneCloudProbe: CloudTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: false, isCounterpartInstalled: false, isReachable: false)
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    var files = 0
    func enqueueCloudControl(_ data: Data) {}
    func enqueueCloudFile(_ url: URL) throws { files += 1; throw BackendError.watchUnavailable }
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
}
