import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor
final class WatchCompanionModelTests: XCTestCase {
    func testZeroHealthShootingSceneImmediatelyEmitsFinishedResult() {
        let scene = ShootingScene(pet: nil)
        scene.game = ShootingGame(attack: 50, health: 0, seed: 1)
        var scores: [Int] = []
        scene.onFinish = { scores.append($0.score) }
        scene.start()
        XCTAssertTrue(scene.finished); XCTAssertEqual(scene.health, 0)
        scene.start()
        XCTAssertTrue(scene.finished); XCTAssertEqual(scores, [0, 0])
    }
    func testFinishedChatAllowsNextQuestionBeforeCleanupReply() async throws {
        let (services, wire, directory, _) = try await setup()
        defer { wire.releaseAll(); try? FileManager.default.removeItem(at: directory) }
        let model = WatchChatViewModel(services: services)
        defer { model.stop(); wire.releaseAll() }
        model.question = "first"; model.send()
        await until { wire.cleanup != nil }
        XCTAssertTrue(model.progress.finished)
        XCTAssertFalse(model.busy, "A completed reply must release the input before best-effort cleanup returns")
    }

    func testFailedChatAlsoReleasesInputBeforeCleanupReply() async throws {
        let (services, wire, directory, _) = try await setup()
        defer { wire.releaseAll(); try? FileManager.default.removeItem(at: directory) }
        wire.failPoll = true
        let model = WatchChatViewModel(services: services)
        defer { model.stop(); wire.releaseAll() }
        model.question = "failure"; model.send()
        await until { wire.cleanup != nil }
        XCTAssertTrue(model.progress.failed)
        XCTAssertFalse(model.busy)
    }

    func testOldCleanupCannotReleaseANewChat() async throws {
        let (services, wire, directory, _) = try await setup()
        defer { wire.releaseAll(); try? FileManager.default.removeItem(at: directory) }
        let model = WatchChatViewModel(services: services)
        defer { model.stop(); wire.releaseAll() }
        model.question = "first"; model.send()
        await until { wire.cleanup != nil }
        wire.holdNextStart = true
        model.question = "second"; model.send()
        await until { wire.pendingStart != nil }
        XCTAssertEqual(wire.starts, 2)
        XCTAssertTrue(model.busy)
        wire.releaseCleanup()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.busy, "Late cleanup for the old ID cannot unlock the new request")
        XCTAssertFalse(model.progress.finished)
    }

    func testRankingFailureKeepsBestAndRetrySubmitsCurrentRun() async throws {
        let (base, _, directory, _) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wire = RankingModelWire()
        let services = WatchGameServices(client: WatchFeatureClient(transport: wire, environment: .development), records: base.records, cloud: base.cloud)
        let model = WatchGameResultModel(services: services)
        wire.fail = true; model.finish(GameScore(game: .shooting, score: 42))
        await until { model.message != nil }
        XCTAssertEqual(model.best?.score, 42); XCTAssertFalse(model.busy)
        wire.fail = false; model.retry()
        await until { model.ranking != nil }
        XCTAssertEqual(model.ranking?.entries.first?.score, 42)
        XCTAssertEqual(wire.submissions.last?.score, 42)
    }

    func testAccountChangeClearsRankingAndDoesNotUploadPreviousAccountsBest() async throws {
        let (base, _, directory, cloudWire) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wire = RankingModelWire()
        let services = WatchGameServices(client: WatchFeatureClient(transport: wire, environment: .development), records: base.records, cloud: base.cloud)
        let model = WatchGameResultModel(services: services)
        model.finish(GameScore(game: .shooting, score: 42))
        await until { model.ranking != nil }
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(nil), environment: .development))
        await base.cloud.finishWork()
        XCTAssertNil(model.ranking); XCTAssertEqual(model.best?.score, 42)
        model.finish(GameScore(game: .shooting, score: 0))
        await until { model.message?.contains("로컬 기록") == true }
        XCTAssertEqual(wire.submissions.count, 1)
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "8", displayName: "Other")), environment: .development))
        await base.cloud.finishWork()
        model.retry(); await until { model.ranking != nil }
        XCTAssertEqual(model.best?.score, 42)
        XCTAssertEqual(wire.lastAccount, "8"); XCTAssertEqual(wire.submissions.last?.score, 0)
        XCTAssertEqual(model.ranking?.entries.first?.score, 0)
    }

    func testLoggedOutChatDoesNotSendARequest() async throws {
        let (services, wire, directory, cloudWire) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(nil), environment: .development))
        await services.cloud.finishWork()
        let model = WatchChatViewModel(services: services)
        model.question = "hello"; model.send()
        XCTAssertTrue(model.progress.failed); XCTAssertFalse(model.busy); XCTAssertEqual(wire.starts, 0)
    }

    func testAccountSwitchCannotRetryAnotherAccountsFinishedRun() async throws {
        let (base, _, directory, cloudWire) = try await setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wire = RankingModelWire()
        let services = WatchGameServices(client: WatchFeatureClient(transport: wire, environment: .development), records: base.records, cloud: base.cloud)
        let model = WatchGameResultModel(services: services)
        model.finish(GameScore(game: .shooting, score: 42))
        await until { model.ranking != nil }
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "8", displayName: "Other")), environment: .development))
        await base.cloud.finishWork()
        XCTAssertFalse(model.canRetry)
        model.retry()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(wire.submissions.count, 1, "A finished run from account 7 cannot be resubmitted as account 8")
        XCTAssertEqual(model.best?.score, 42)
    }

    private func setup() async throws -> (WatchGameServices, ChatModelWire, URL, PreviewCloudTransport) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let game = FileGameRepository(directory: directory)
        let cloudWire = PreviewCloudTransport()
        let home = WatchHomeViewModel(stepCounter: PreviewStepCounter(), repository: game)
        let pet = PetProgressViewModel(repository: game, history: game)
        let cloud = WatchCloudController(game: game, transport: cloudWire, home: home, pet: pet, directory: directory, environment: .development)
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test")), environment: .development))
        await cloud.finishWork()
        let wire = ChatModelWire()
        return (WatchGameServices(client: WatchFeatureClient(transport: wire, environment: .development), records: FileMiniGameRecords(fileURL: directory.appendingPathComponent("records.json")), cloud: cloud), wire, directory, cloudWire)
    }
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 { if condition() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        XCTFail("The expected request did not arrive")
    }
}

@MainActor private final class RankingModelWire: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    var fail = false
    var submissions: [GameScore] = []
    var lastAccount: String?
    private var best: [String: Int] = [:]
    func requestFeature(_ data: Data) async throws -> Data {
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        if fail { throw BackendError.watchUnavailable }
        guard case let .submit(score) = request.action else { throw BackendError.invalidResponse }
        submissions.append(score); lastAccount = request.accountID
        best[request.accountID] = max(best[request.accountID] ?? 0, score.score)
        let value = GameRanking(game: score.game, position: 1, entries: [GameRankEntry(rank: 1, userID: Int64(request.accountID), name: "Test", score: best[request.accountID]!)])
        return try JSONEncoder().encode(CompanionFeatureReply(request: request, result: .ranking(value)))
    }
}

@MainActor
private final class ChatModelWire: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    var failPoll = false
    var holdNextStart = false
    var starts = 0
    var cleanup: (CompanionFeatureRequest, CheckedContinuation<Data, Error>)?
    var pendingStart: (CompanionFeatureRequest, CheckedContinuation<Data, Error>)?
    private var heldCleanup = false
    func requestFeature(_ data: Data) async throws -> Data {
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        switch request.action {
        case .startChat:
            starts += 1
            if holdNextStart { return try await withCheckedThrowingContinuation { pendingStart = (request, $0) } }
            return try reply(request, .accepted)
        case .pollChat:
            if failPoll { throw BackendError.network }
            var progress = ChatProgress(); try progress.receive(ChatStreamEvent(name: "token", data: "answer")); progress.end()
            return try reply(request, .chat(progress))
        case .cancelChat:
            if !heldCleanup {
                heldCleanup = true
                return try await withCheckedThrowingContinuation { cleanup = (request, $0) }
            }
            return try reply(request, .accepted)
        default: throw BackendError.invalidResponse
        }
    }
    func releaseCleanup() {
        if let (request, continuation) = cleanup { cleanup = nil; continuation.resume(returning: try! reply(request, .accepted)) }
    }
    func releaseAll() {
        releaseCleanup()
        if let (request, continuation) = pendingStart { pendingStart = nil; continuation.resume(returning: try! reply(request, .accepted)) }
    }
    private func reply(_ request: CompanionFeatureRequest, _ value: CompanionFeatureReply.Result) throws -> Data {
        try JSONEncoder().encode(CompanionFeatureReply(request: request, result: value))
    }
}
