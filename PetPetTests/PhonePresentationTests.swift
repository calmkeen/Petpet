import XCTest
import PetPetCore
@testable import PetPet

@MainActor
final class PhonePresentationTests: XCTestCase {
    private let base = URL(string: "https://phone.example.test/")!
    private let petJSON = #"{"userId":7,"userMateId":42,"mateId":1,"level":3,"experience":1,"affection":2,"attack":52,"defense":4,"health":9,"status":"HAPPY","lastFedAt":null}"#

    func testServerPetFallbackKeepsWatchProgressAuthoritativeAndClearsOnLogout() async throws {
        let backend = try client(PhoneViewHTTP(body: petJSON))
        let home = PhoneHomeViewModel(backend: backend)
        home.setAccount("7")
        await home.refreshServerPet()
        XCTAssertEqual(home.displayedPet?.level, 3)
        XCTAssertTrue(home.isShowingServerPet)
        XCTAssertNil(home.todaySteps, "Server history must not pretend to be live watch steps")

        let pet = PetProgress.newUser(at: Date()).pet
        let snapshot = WatchSnapshot(sourceID: UUID(), revision: 1, generatedAt: Date(), steps: [], pet: pet, inventory: [])
        let watchHome = PhoneHomeViewModel(initialState: PhoneSnapshotState(cached: CachedWatchSnapshot(snapshot: snapshot, receivedAt: Date(), peerID: "watch")), backend: backend)
        watchHome.setAccount("7")
        await watchHome.refreshServerPet()
        XCTAssertEqual(watchHome.displayedPet, pet)
        XCTAssertFalse(watchHome.isShowingServerPet)
        home.setAccount(nil)
        XCTAssertNil(home.displayedPet)
        XCTAssertNil(home.serverPetError)
    }

    func testServerPetCacheRemainsVisibleOfflineAndCannotLeakToAnotherAccount() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileAccountPetCache(fileURL: directory.appendingPathComponent("pet.json"))
        let pet = PetProgress.newUser(at: Date()).pet
        try await cache.save(pet, accountID: "7", at: Date())
        let home = PhoneHomeViewModel(backend: try client(PhoneViewHTTP(status: 500)), petCache: cache)
        home.setAccount("7")
        await home.refreshServerPet()
        XCTAssertEqual(home.displayedPet, pet)
        XCTAssertNotNil(home.serverPetError)
        home.setAccount("8")
        await home.refreshServerPet()
        XCTAssertNil(home.displayedPet)
        XCTAssertFalse(home.isServerPetLoading)
    }

    func testFailedStreakReadPreservesCacheAndLogoutClearsIt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileAccountStepCache(fileURL: directory.appendingPathComponent("steps.json"))
        try await cache.save([DailyStepRecord(date: "2026-11-07", stepCount: 2500)], accountID: "7")
        let model = PhoneStreakViewModel(backend: try client(PhoneViewHTTP(status: 404)), cache: cache)
        await model.refresh(accountID: "7")
        XCTAssertEqual(model.summary.counts["2026-11-07"], 2500)
        XCTAssertNotNil(model.error)
        await model.refresh(accountID: nil)
        XCTAssertTrue(model.summary.counts.isEmpty)
        XCTAssertNil(model.error)
    }

    func testNewDayBypassesRefreshThrottleAndUpdatesHeatmap() async throws {
        let clock = PhoneTestClock()
        clock.date = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
        let http = PhoneViewHTTP(body: #"{"userId":7,"stepCounts":[{"date":"2026-11-07","stepCount":2500}]}"#)
        let model = PhoneStreakViewModel(backend: try client(http), now: { clock.date }, uptime: { clock.uptime })
        await model.refresh(accountID: "7")
        await model.refresh(accountID: "7")
        var calls = await http.calls
        XCTAssertEqual(calls, 1)
        clock.date = clock.date.addingTimeInterval(86400)
        model.refreshDate()
        XCTAssertEqual(model.summary.today, "2026-11-08")
        XCTAssertEqual(model.weeks.flatMap { $0 }.compactMap { $0 }.last, "2026-11-08")
        await model.refresh(accountID: "7")
        calls = await http.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.summary.currentDays, 1)
    }

    func testStreakShowsFreshDataEvenIfCacheCannotBeWritten() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: parentFile)
        let model = PhoneStreakViewModel(backend: try client(PhoneViewHTTP(body: #"{"userId":7,"stepCounts":[{"date":"2026-11-07","stepCount":2500}]}"#)), cache: FileAccountStepCache(fileURL: parentFile.appendingPathComponent("steps.json")))
        await model.refresh(accountID: "7")
        XCTAssertEqual(model.summary.counts["2026-11-07"], 2500)
        XCTAssertTrue(model.error?.contains("저장하지 못했어요") == true)
    }

    func testIdleChatCancellationDoesNotInventFailureOrCancelRanking() async throws {
        let model = PhoneExtrasModel(backend: try client(PhoneViewHTTP(status: 500)))
        let initial = model.progress
        model.stop()
        XCTAssertEqual(model.progress, initial)
        model.setAccount("7")
        model.load(.shooting)
        XCTAssertTrue(model.rankingBusy)
        model.cancelChat()
        XCTAssertTrue(model.rankingBusy)
        XCTAssertEqual(model.progress, initial)
        model.stop()
        XCTAssertFalse(model.rankingBusy)
    }

    private func client(_ http: PhoneViewHTTP) throws -> BackendClient {
        try BackendClient(baseURL: base, transport: http, store: PhoneViewSessionStore(BackendSession(accountID: "7", serverOrigin: base.absoluteString, accessToken: "test-access", refreshToken: nil, email: nil, name: nil, nickname: "Tester")))
    }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
}

@MainActor private final class PhoneTestClock { var date = Date(); var uptime: TimeInterval = 100 }
private actor PhoneViewSessionStore: BackendSessionStore {
    private var value: BackendSession?
    init(_ value: BackendSession) { self.value = value }
    func load() -> BackendSession? { value }
    func save(_ session: BackendSession) { value = session }
    func clear() { value = nil }
}
private actor PhoneViewHTTP: BackendHTTPTransport {
    let response: BackendHTTPResponse
    private(set) var calls = 0
    init(status: Int = 200, body: String = "") { response = BackendHTTPResponse(statusCode: status, data: Data(body.utf8)) }
    func send(_ request: URLRequest) -> BackendHTTPResponse { calls += 1; return response }
}
