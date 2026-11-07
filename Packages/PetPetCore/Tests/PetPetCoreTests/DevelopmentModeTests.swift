#if DEBUG
import XCTest
@testable import PetPetCore

final class DevelopmentModeTests: XCTestCase {
    func testMockLoginCannotUseProductionClientOrAnyNetworkTransport() async throws {
        let http = RejectDevelopmentHTTP()
        for url in [URL(string: "https://api.example.test/")!, LocalDevelopmentBackend.baseURL] {
            let client = try BackendClient(baseURL: url, transport: http, store: TestSessionStore())
            do { _ = try await client.signInForDevelopment(); XCTFail() }
            catch { XCTAssertEqual(error as? BackendError, .configurationMissing) }
        }
        let server = LocalDevelopmentBackend(fileURL: folder().appendingPathComponent("server"))
        do { _ = try await server.send(URLRequest(url: URL(string: "https://www.stepmatecp.com/api/v1/backup")!)); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .configurationMissing) }
    }

    func testMockLoginAndIncrementalBackupSurviveAppRestart() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = TestSessionStore()
        let file = root.appendingPathComponent("server.json")
        let client = try backend(file: file, store: store)
        let session = try await client.signInForDevelopment()
        XCTAssertEqual(session.accountID, String(LocalDevelopmentBackend.accountID))
        XCTAssertNil(session.identityProvider) // never trigger a real Apple credential check
        try await client.saveBackup(request([("2026-11-06", 4000), ("2026-11-07", 1000)]), accountID: session.accountID)
        try await client.saveBackup(request([("2026-11-07", 2500)], level: 2), accountID: session.accountID)
        let restarted = try backend(file: file, store: store)
        let restored = try await restarted.restore(accountID: session.accountID)
        XCTAssertEqual(restored.pet.level, 2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: restored.steps.map { ($0.date, $0.stepCount) }),
                       ["2026-11-06": 4000, "2026-11-07": 2500])
        try await restarted.saveBackup(request([("2026-11-07", 500)], level: 2), accountID: session.accountID)
        let lower = try await restarted.restore(accountID: session.accountID)
        XCTAssertEqual(lower.steps.first { $0.date == "2026-11-07" }?.stepCount, 2500)
    }

    func testRestoreBeforeFirstMockBackupShowsUsefulError() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let client = try backend(file: root.appendingPathComponent("server"), store: TestSessionStore())
        let session = try await client.signInForDevelopment()
        do { _ = try await client.restore(accountID: session.accountID); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .noBackup) }
    }

    func testMockUnauthorizedRequestRefreshesOnlyLocalTokens() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("server")
        let store = TestSessionStore()
        let first = try backend(file: file, store: store)
        let session = try await first.signInForDevelopment()
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        archive["accessToken"] = "expired-access-replacement"
        try JSONSerialization.data(withJSONObject: archive).write(to: file)
        let restarted = try backend(file: file, store: store)
        try await restarted.saveBackup(request([("2026-11-07", 2000)]), accountID: session.accountID)
        let refreshed = try await store.load()
        XCTAssertNotEqual(refreshed?.accessToken, session.accessToken)
        XCTAssertNotEqual(refreshed?.refreshToken, session.refreshToken)
        XCTAssertEqual(refreshed?.serverOrigin, LocalDevelopmentBackend.baseURL.absoluteString)
    }

    func testFailedMockSaveKeepsLastBackupAndCanRetry() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("server-folder")
        let file = parent.appendingPathComponent("server.json")
        let client = try backend(file: file, store: TestSessionStore())
        let session = try await client.signInForDevelopment()
        try await client.saveBackup(request([("2026-11-07", 1000)]), accountID: session.accountID)
        let oldData = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: parent)
        try Data("blocked directory".utf8).write(to: parent)
        do { try await client.saveBackup(request([("2026-11-07", 3000)], level: 2), accountID: session.accountID); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .storage) }
        let unchanged = try await client.restore(accountID: session.accountID)
        XCTAssertEqual(unchanged.pet.level, 1)
        XCTAssertEqual(unchanged.steps.first?.stepCount, 1000)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try oldData.write(to: file)
        try await client.saveBackup(request([("2026-11-07", 3000)], level: 2), accountID: session.accountID)
        let retried = try await client.restore(accountID: session.accountID)
        XCTAssertEqual(retried.pet.level, 2)
        XCTAssertEqual(retried.steps.first?.stepCount, 3000)
    }

    func testCorruptMockBackupIsNotSilentlyReset() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("server")
        let original = Data("not valid JSON".utf8)
        try original.write(to: file)
        let client = try backend(file: file, store: TestSessionStore())
        do { _ = try await client.signInForDevelopment(); XCTFail() } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testDevelopmentGameCopiesActiveStateWithoutChangingProductionAccountOrRewards() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("production")
        let target = root.appendingPathComponent("development")
        let now = Date()
        let production = FileGameRepository(directory: source)
        try await production.save(DailyStepRecord(date: StepDay(containing: now).date, stepCount: 2500))
        let originalExport = try await production.prepareBackup(operationID: UUID(), accountID: "real-user")
        let original = try await production.load()
        let originalData = try Data(contentsOf: source.appendingPathComponent("game-state-v1.json"))
        let development = FileGameRepository(developmentDirectory: target, seedDirectory: source)
        let copied = try await development.load()
        XCTAssertEqual(copied, original)
        let challenge = try await development.challenge()
        XCTAssertNil(challenge.ownerID)
        XCTAssertNotEqual(challenge.storeID, originalExport.storeID)
        let export = try await development.prepareBackup(operationID: UUID(), accountID: "mock-user")
        _ = try await development.confirmBackup(CloudBackupReceipt(export: export, completedAt: now))
        _ = try await development.perform(.feed(foodID: 1))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("game-state-v1.json")), originalData)
        let restart = FileGameRepository(developmentDirectory: target, seedDirectory: source)
        let reloaded = try await restart.load()
        XCTAssertNotEqual(reloaded, original)
        let retained = try await development.load()
        XCTAssertEqual(reloaded, retained)
    }

    func testDevelopmentGameCopiesLegacyFilesWithoutMigratingProductionDirectory() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("production")
        let target = root.appendingPathComponent("development")
        let legacy = FilePetProgressRepository(fileURL: source.appendingPathComponent("pet-progress-v1.json"))
        let original = try await legacy.load()
        let history = FileStepHistoryRepository(fileURL: source.appendingPathComponent("step-history-v1.json"))
        try await history.save(DailyStepRecord(date: "2026-11-07", stepCount: 1234))
        let originalData = try Data(contentsOf: source.appendingPathComponent("pet-progress-v1.json"))
        let development = FileGameRepository(developmentDirectory: target, seedDirectory: source)
        let copied = try await development.load()
        let record = try await development.record(for: "2026-11-07")
        XCTAssertEqual(copied, original)
        XCTAssertEqual(record?.stepCount, 1234)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("pet-progress-v1.json")), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("game-state-v1.json").path))
    }

    func testControlAndBackupFilesCannotCrossDebugAndReleaseEnvironments() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let game = FileGameRepository(directory: root)
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "7")
        for mode in [CloudEnvironment.development, .production] {
            let other: CloudEnvironment = mode == .development ? .production : .development
            let control = try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test")), environment: mode)
            XCTAssertNoThrow(try CloudWire.decodeControl(control, environment: mode))
            XCTAssertThrowsError(try CloudWire.decodeControl(control, environment: other)) {
                XCTAssertEqual($0 as? BackendError, .environmentMismatch)
            }
            let data = try CloudWire.encodeFile(.backup(export), environment: mode)
            XCTAssertNoThrow(try CloudWire.decodeFile(data, environment: mode))
            XCTAssertThrowsError(try CloudWire.decodeFile(data, environment: other)) {
                XCTAssertEqual($0 as? BackendError, .environmentMismatch)
            }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["version"] as? Int, mode == .development ? 2 : 1)
        }
    }

    func testDevelopmentRestoreChallengeRejectsLegacyOrProductionStore() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let game = FileGameRepository(directory: root)
        let target = try await game.challenge()
        let legacy = try JSONEncoder().encode(target)
        XCTAssertEqual(try CloudWire.decodeChallenge(legacy, environment: .production), target)
        XCTAssertThrowsError(try CloudWire.decodeChallenge(legacy, environment: .development))
        let tagged = try CloudWire.encodeChallenge(target, environment: .development)
        XCTAssertEqual(try CloudWire.decodeChallenge(tagged, environment: .development), target)
        XCTAssertThrowsError(try CloudWire.decodeChallenge(tagged, environment: .production))
    }

    private func backend(file: URL, store: TestSessionStore) throws -> BackendClient {
        try BackendClient(baseURL: LocalDevelopmentBackend.baseURL,
                          transport: LocalDevelopmentBackend(fileURL: file), store: store)
    }
    private func request(_ records: [(String, Int)], level: Int64 = 1) throws -> ServerBackupRequest {
        var pet = PetProgress.newUser(at: Date()).pet
        pet.level = level
        return try ServerBackupRequest(pet: pet, steps: records.map { DailyStepRecord(date: $0.0, stepCount: $0.1) }, timeZone: .current)
    }
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("PetPetDevelopment-\(UUID())") }
}

private actor RejectDevelopmentHTTP: BackendHTTPTransport {
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        XCTFail("Development login must never reach a network transport")
        throw BackendError.network
    }
}
#endif
