#if DEBUG
import XCTest
@testable import PetPetCore

@MainActor final class WatchStandaloneTests: XCTestCase {
    func testNoPhoneNicknameBackupBothRankingsAndStreamingChat() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.start(); try await f.service.signInForDevelopment()
        let id = try XCTUnwrap(f.service.state.account?.id)
        let reserved = try await f.service.checkNickname("StepMate", accountID: id)
        XCTAssertFalse(reserved)
        let name = try await f.service.updateNickname("SoloWatch", accountID: id)
        XCTAssertEqual(name, "SoloWatch"); XCTAssertEqual(f.service.state.account?.displayName, name)
        try await f.game.save(DailyStepRecord(date: StepDay(containing: Date()).date, stepCount: 1000))
        try await f.service.backup()
        let once = try await f.game.load()
        XCTAssertEqual(once.quantity(of: 1), 4); XCTAssertEqual(once.quantity(of: 2), 1)
        try await f.service.backup()
        let twice = try await f.game.load(); XCTAssertEqual(twice, once)
        XCTAssertNotNil(f.service.state.lastBackupAt)
        for game in MiniGame.allCases {
            guard case let .ranking(rank) = try await f.features.request(.submit(GameScore(game: game, score: 42, maxCombo: 12)), accountID: id) else { return XCTFail() }
            XCTAssertEqual(rank.position, 1); XCTAssertEqual(rank.entries.first?.name, name)
        }
        let chat = UUID()
        _ = try await f.features.request(.startChat(chat, "산책하자"), accountID: id)
        var completed = false
        for _ in 0..<150 {
            if case let .chat(reply) = try await f.features.request(.pollChat(chat), accountID: id), reply.finished {
                XCTAssertFalse(reply.failed); XCTAssertTrue(reply.text.contains("산책하자")); completed = true; break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(completed)
        _ = try await f.features.request(.cancelChat(chat), accountID: id)
        XCTAssertEqual(f.phone.calls, 0)
        let loadedSession = try await f.backend.session()
        let session = try XCTUnwrap(loadedSession)
        for file in ["mode.json", "receipts.json", "game-state-v1.json"] {
            let bytes = try Data(contentsOf: f.root.appendingPathComponent(file))
            XCTAssertNil(bytes.range(of: Data(session.accessToken.utf8)))
            XCTAssertNil(bytes.range(of: Data((session.refreshToken ?? "missing-refresh").utf8)))
        }
    }

    func testRestartRestoresLocalLoginAndNicknameWithoutPhone() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.signInForDevelopment()
        let id = try XCTUnwrap(f.service.state.account?.id)
        _ = try await f.service.updateNickname("RestartFox", accountID: id)
        let restarted = try f.restart()
        try await restarted.start(); try await restarted.refreshProfile()
        XCTAssertTrue(restarted.state.isSelected)
        XCTAssertEqual(restarted.state.account?.displayName, "RestartFox")
        XCTAssertEqual(f.phone.calls, 0)
    }

    func testLogoutDoesNotSilentlyFallBackAndExplicitSwitchUsesPhone() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.signInForDevelopment()
        let id = try XCTUnwrap(f.service.state.account?.id)
        try await f.service.signOut()
        XCTAssertTrue(f.service.state.isSelected); XCTAssertNil(f.service.state.account)
        do { _ = try await f.features.request(.ranking(.shooting), accountID: id); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .authenticationRequired) }
        XCTAssertEqual(f.phone.calls, 0)
        try await f.service.useCompanion()
        do { _ = try await f.features.request(.ranking(.shooting), accountID: id); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .watchUnavailable) }
        XCTAssertEqual(f.phone.calls, 1)
    }

    func testRestorePreviewDoesNotMutateAndConfirmedRestoreKeepsFood() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.signInForDevelopment(); try await f.service.backup()
        let backedUp = try await f.game.load()
        _ = try await f.game.perform(.feed(foodID: 1))
        let fed = try await f.game.load()
        let command = try await f.service.prepareRestore()
        let afterPreview = try await f.game.load(); XCTAssertEqual(afterPreview, fed)
        try await f.service.restore(command)
        let restored = try await f.game.load()
        XCTAssertEqual(restored.pet.experience, backedUp.pet.experience)
        XCTAssertEqual(restored.inventory, fed.inventory)
        try await f.service.restore(command) // completed operation is idempotent
        let repeated = try await f.game.load(); XCTAssertEqual(repeated, restored)
        XCTAssertEqual(f.phone.calls, 0)
    }

    func testStaleRestoreCannotOverwriteFeedingAndIsNotRetriedOnRestart() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.signInForDevelopment(); try await f.service.backup()
        let preview = try await f.service.prepareRestore()
        _ = try await f.game.perform(.feed(foodID: 1))
        let fed = try await f.game.load()
        do { try await f.service.restore(preview); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .localStateChanged) }
        let pending = try await f.receipts.pendingRestores(accountID: preview.state.accountID)
        XCTAssertTrue(pending.isEmpty)
        try await f.restart().start()
        let retained = try await f.game.load(); XCTAssertEqual(retained, fed)
    }

    func testDurableBackupReceiptRecoversExactlyOnceAfterRestart() async throws {
        let f = try Fixture(); defer { f.remove() }
        try await f.service.signInForDevelopment()
        let id = try XCTUnwrap(f.service.state.account?.id)
        try await f.game.save(DailyStepRecord(date: StepDay(containing: Date()).date, stepCount: 1000))
        let export = try await f.game.prepareBackup(operationID: UUID(), accountID: id)
        try await f.backend.saveBackup(export.request(), accountID: id)
        try await f.receipts.save(CloudBackupReceipt(export: export, completedAt: Date()))
        for _ in 0..<2 { try await f.restart().start() }
        let state = try await FileGameRepository(directory: f.root).load()
        XCTAssertEqual(state.quantity(of: 1), 4); XCTAssertEqual(state.quantity(of: 2), 1)
        let pending = try await FileCloudReceiptStore(fileURL: f.root.appendingPathComponent("receipts.json")).pending(); XCTAssertTrue(pending.isEmpty)
    }

    func testConcurrentBackupTapsIssueOneServerRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let http = HeldBackupHTTP()
        let store = TestSessionStore(session: standaloneSession())
        let backend = try BackendClient(baseURL: URL(string: "https://api.example.test/")!, transport: http, store: store)
        let game = FileGameRepository(directory: root)
        let service = WatchStandaloneService(backend: backend, game: game,
            receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts")),
            modeURL: root.appendingPathComponent("mode"), environment: .development)
        try await service.start()
        let first = Task { try await service.backup() }
        for _ in 0..<200 { if await http.calls > 0 { break }; await Task.yield() }
        XCTAssertTrue(service.state.isBusy)
        do { try await service.backup(); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .operationExpired) }
        await http.release(); try await first.value
        let calls = await http.calls; XCTAssertEqual(calls, 1); XCTAssertFalse(service.state.isBusy)
    }

    func testExpiredWatchSessionStaysDirectUntilExplicitModeSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = try BackendClient(baseURL: URL(string: "https://api.example.test/")!, transport: UnauthorizedStandaloneHTTP(), store: TestSessionStore(session: standaloneSession()))
        let service = WatchStandaloneService(backend: backend, game: FileGameRepository(directory: root),
            receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts")), modeURL: root.appendingPathComponent("mode"), environment: .development)
        try await service.start()
        let phone = OfflineStandalonePhone()
        let features = WatchFeatureClient(transport: WatchFeatureRouter(direct: service, companion: phone), environment: .development)
        do { _ = try await features.request(.ranking(.shooting), accountID: "7"); XCTFail() } catch {}
        await service.refreshSession()
        XCTAssertNil(service.state.account); XCTAssertTrue(service.state.isSelected); XCTAssertEqual(phone.calls, 0)
    }
}

@MainActor private struct Fixture {
    let root: URL
    let store = TestSessionStore()
    let backend: BackendClient
    let game: FileGameRepository
    let receipts: FileCloudReceiptStore
    let service: WatchStandaloneService
    let phone: OfflineStandalonePhone
    let features: WatchFeatureClient
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WatchStandalone-\(UUID())")
        backend = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL,
            transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server.json")), store: store)
        game = FileGameRepository(directory: root)
        receipts = FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts.json"))
        service = WatchStandaloneService(backend: backend, game: game, receipts: receipts,
            modeURL: root.appendingPathComponent("mode.json"), environment: .development)
        phone = OfflineStandalonePhone()
        features = WatchFeatureClient(transport: WatchFeatureRouter(direct: service, companion: phone), environment: .development)
    }
    func restart() throws -> WatchStandaloneService {
        let backend = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL,
            transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server.json")), store: store)
        return WatchStandaloneService(backend: backend, game: FileGameRepository(directory: root),
            receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts.json")),
            modeURL: root.appendingPathComponent("mode.json"), environment: .development)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
@MainActor private final class OfflineStandalonePhone: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    var calls = 0
    func requestFeature(_ data: Data) async throws -> Data { calls += 1; throw BackendError.watchUnavailable }
}
private func standaloneSession() -> BackendSession {
    BackendSession(accountID: "7", serverOrigin: "https://api.example.test/", accessToken: "test-access", refreshToken: "test-refresh", email: nil, name: nil, nickname: "여우")
}
private actor HeldBackupHTTP: BackendHTTPTransport {
    var calls = 0
    var waiter: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        calls += 1
        await withCheckedContinuation { waiter = $0 }
        return BackendHTTPResponse(statusCode: 200, data: Data("{}".utf8))
    }
    func release() { waiter?.resume(); waiter = nil }
}
private struct UnauthorizedStandaloneHTTP: BackendHTTPTransport {
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse { BackendHTTPResponse(statusCode: 401) }
}
#endif
