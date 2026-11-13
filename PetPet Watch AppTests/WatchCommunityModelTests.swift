import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor final class WatchCommunityModelTests: XCTestCase {
    func testFailedNextPageKeepsCurrentPageAndCanRetry() async throws {
        let f = try await CommunityContext(); defer { f.remove() }
        let model = WatchRankingPageModel(kind: .steps, client: f.client, cloud: f.cloud)
        model.load(); await model.finishWork(); XCTAssertEqual(model.page, 1)
        f.wire.rejectSecondPage = true
        model.load(2); await model.finishWork()
        XCTAssertEqual(model.page, 1); XCTAssertNotNil(model.error); XCTAssertFalse(model.busy)
        f.wire.rejectSecondPage = false
        model.load(2); await model.finishWork()
        XCTAssertEqual(model.page, 2); XCTAssertNil(model.error)
        XCTAssertEqual(f.wire.pages, [1, 2, 2])
    }
    func testLogoutDiscardsLateRankingReply() async throws {
        let f = try await CommunityContext(); defer { f.remove() }
        let entered = expectation(description: "Rank request entered")
        f.wire.entered = entered; f.wire.hold = true
        let model = WatchRankingPageModel(kind: .steps, client: f.client, cloud: f.cloud)
        let work = Task { model.load(); await model.finishWork() }
        await fulfillment(of: [entered], timeout: 3)
        f.transport.onCloudControl?(try CloudWire.encodeControl(.account(nil), environment: .development))
        await f.cloud.finishWork()
        f.wire.release(); await work.value
        XCTAssertNil(model.stepPage); XCTAssertNil(model.gamePage); XCTAssertFalse(model.busy)
    }
    func testProfileRetryClearsErrorAndLogoutDisablesEditing() async throws {
        let f = try await CommunityContext(); defer { f.remove() }
        let model = WatchProfileImageModel(client: f.client, cloud: f.cloud)
        f.wire.rejectProfile = true; await model.load()
        XCTAssertNotNil(model.message); XCTAssertTrue(model.canEdit)
        f.wire.rejectProfile = false; await model.load()
        XCTAssertEqual(model.profile?.nickname, "Test"); XCTAssertNil(model.message)
        f.transport.onCloudControl?(try CloudWire.encodeControl(.account(nil), environment: .development))
        await f.cloud.finishWork()
        XCTAssertNil(model.profile); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.message, "계정에서 로그인해 주세요.")
    }
    func testLogoutDiscardsLateProfileAndReleasesBusyState() async throws {
        let f = try await CommunityContext(); defer { f.remove() }
        let entered = expectation(description: "Profile entered"); f.wire.entered = entered; f.wire.hold = true
        let model = WatchProfileImageModel(client: f.client, cloud: f.cloud)
        let work = Task { await model.load() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertFalse(model.canEdit)
        f.transport.onCloudControl?(try CloudWire.encodeControl(.account(nil), environment: .development))
        await f.cloud.finishWork(); f.wire.release(); await work.value
        XCTAssertNil(model.profile); XCTAssertFalse(model.busy); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.message, "계정에서 로그인해 주세요.")
    }
}
@MainActor private struct CommunityContext {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let transport = CommunityCloudProbe()
    let wire = CommunityRankWire()
    let cloud: WatchCloudController
    let client: WatchFeatureClient
    init() async throws {
        let game = FileGameRepository(directory: root)
        cloud = WatchCloudController(game: game, transport: transport,
            home: WatchHomeViewModel(stepCounter: CommunityIdleCounter(), repository: game),
            pet: PetProgressViewModel(repository: game, history: game), directory: root, environment: .development)
        client = WatchFeatureClient(transport: wire, environment: .development)
        transport.onCloudControl?(try CloudWire.encodeControl(.account(CloudAccount(id: "7", displayName: "Test")), environment: .development))
        await cloud.finishWork()
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
@MainActor private final class CommunityRankWire: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    var rejectSecondPage = false
    var rejectProfile = false
    var hold = false
    var entered: XCTestExpectation?
    var pages: [Int] = []
    var continuation: CheckedContinuation<Void,Never>?
    func requestFeature(_ data: Data) async throws -> Data {
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        if hold { await withCheckedContinuation { continuation = $0; entered?.fulfill() } }
        if case .profile = request.action {
            if rejectProfile { throw BackendError.network }
            return try JSONEncoder().encode(CompanionFeatureReply(request: request,
                result: .profile(AccountProfileDetails(nickname: "Test", pictureURL: URL(string: "https://image.example.test/pet.jpg")))))
        }
        guard case let .stepPage(page) = request.action else { throw BackendError.invalidResponse }
        pages.append(page.page)
        if rejectSecondPage && page.page == 2 { throw BackendError.network }
        let records = (0..<5).map { offset in ["rank": (page.page - 1) * 5 + offset + 1, "userId": offset + 10, "nickname": "친구", "totalStepCount": 100] as [String: Any] }
        let value = try JSONDecoder().decode(StepRankingPage.self, from: JSONSerialization.data(withJSONObject: ["page": page.page, "size": 5, "totalUsers": 12, "rankings": records]))
        return try JSONEncoder().encode(CompanionFeatureReply(request: request, result: .stepPage(value)))
    }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor private final class CommunityCloudProbe: CloudTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: false, isCounterpartInstalled: false, isReachable: false)
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    func enqueueCloudControl(_ data: Data) {}
    func enqueueCloudFile(_ url: URL) throws { throw BackendError.watchUnavailable }
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
}
@MainActor private final class CommunityIdleCounter: StepCounting {
    func steps(from start: Date, to end: Date) async throws -> Int { 0 }
    func startUpdates(from date: Date, onUpdate: @escaping @MainActor (Result<Int,StepCountingError>) -> Void) {}
    func stopUpdates() {}
}
