import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor
final class WatchCompanionModelTests: XCTestCase {
    func testFinishedChatAllowsNextQuestionBeforeCleanupReply() async throws {
        let (services, wire, directory) = try await setup()
        defer { wire.releaseAll(); try? FileManager.default.removeItem(at: directory) }
        let model = WatchChatViewModel(services: services)
        defer { model.stop(); wire.releaseAll() }
        model.question = "first"; model.send()
        await until { wire.cleanup != nil }
        XCTAssertTrue(model.progress.finished)
        XCTAssertFalse(model.busy, "A completed reply must release the input before best-effort cleanup returns")
    }

    func testFailedChatAlsoReleasesInputBeforeCleanupReply() async throws {
        let (services, wire, directory) = try await setup()
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
        let (services, wire, directory) = try await setup()
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

    private func setup() async throws -> (WatchGameServices, ChatModelWire, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let game = FileGameRepository(directory: directory)
        let cloudWire = PreviewCloudTransport()
        let home = WatchHomeViewModel(stepCounter: PreviewStepCounter(), repository: game)
        let pet = PetProgressViewModel(repository: game, history: game)
        let cloud = WatchCloudController(game: game, transport: cloudWire, home: home, pet: pet, directory: directory, environment: .development)
        cloudWire.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test")), environment: .development))
        await cloud.finishWork()
        let wire = ChatModelWire()
        return (WatchGameServices(client: WatchFeatureClient(transport: wire, environment: .development), records: FileMiniGameRecords(fileURL: directory.appendingPathComponent("records.json")), cloud: cloud), wire, directory)
    }
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        XCTFail("The expected request did not arrive")
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
