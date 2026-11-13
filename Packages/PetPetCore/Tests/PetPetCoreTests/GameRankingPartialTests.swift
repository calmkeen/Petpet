import XCTest
@testable import PetPetCore

final class GameRankingPartialTests: XCTestCase {
    func testBothGamesKeepSubmittedPositionWhenTopTenFailsAndRetryRecovers() async throws {
        for game in MiniGame.allCases {
            let http = PartialRankHTTP(), backend = try client(http)
            let score = GameScore(game: game, score: 4, maxCombo: 2)
            let partial = try await backend.ranking(game, submitting: score, accountID: "7")
            XCTAssertEqual(partial.position, 3); XCTAssertTrue(partial.entries.isEmpty)
            XCTAssertTrue(partial.warning?.contains("TOP 10") == true)
            let relayed = try JSONDecoder().decode(GameRanking.self, from: JSONEncoder().encode(partial))
            XCTAssertEqual(relayed, partial)
            await http.recover()
            let retried = try await backend.ranking(game, submitting: score, accountID: "7")
            XCTAssertEqual(retried.position, 3); XCTAssertEqual(retried.entries.first?.score, 9)
            XCTAssertNil(retried.warning)
        }
    }

    func testTopTenFailureWithoutSubmissionStillThrows() async throws {
        let backend = try client(PartialRankHTTP())
        do { _ = try await backend.ranking(.shooting, accountID: "7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .http(503)) }
    }

    func testLogoutDuringFailedTopTenCannotReturnPreviousAccountsPosition() async throws {
        let entered = expectation(description: "Top ten entered"), http = PartialRankHTTP()
        await http.hold(entered)
        let backend = try client(http)
        let work = Task { try await backend.ranking(.shooting, submitting: GameScore(game: .shooting, score: 4), accountID: "7") }
        await fulfillment(of: [entered], timeout: 2)
        try await backend.signOut(); await http.release()
        do { _ = try await work.value; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .sessionChanged) }
    }

    func testCancellationDoesNotReturnPartialSuccess() async throws {
        let entered = expectation(description: "Top ten entered"), http = PartialRankHTTP()
        await http.hold(entered)
        let backend = try client(http)
        let work = Task { try await backend.ranking(.shooting, submitting: GameScore(game: .shooting, score: 4), accountID: "7") }
        await fulfillment(of: [entered], timeout: 2)
        work.cancel(); await http.release()
        do { _ = try await work.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testExpiredAuthenticationDoesNotReturnPartialSuccess() async throws {
        let http = PartialRankHTTP(status: 401), backend = try client(http)
        do { _ = try await backend.ranking(.shooting, submitting: GameScore(game: .shooting, score: 4), accountID: "7"); XCTFail() }
        catch { XCTAssertTrue([BackendError.sessionChanged, .authenticationRequired].contains(error as? BackendError ?? .network)) }
        let session = try await backend.session(); XCTAssertNil(session)
    }

    private func client(_ http: PartialRankHTTP) throws -> BackendClient {
        try BackendClient(baseURL: URL(string: "https://api.example.test/")!, transport: http,
            store: TestSessionStore(session: BackendSession(accountID: "7", serverOrigin: "https://api.example.test/",
                accessToken: "access", refreshToken: "refresh", email: nil, name: nil, nickname: "여우")))
    }
}

private actor PartialRankHTTP: BackendHTTPTransport {
    var status: Int
    private var entered: XCTestExpectation?
    private var continuation: CheckedContinuation<Void,Never>?
    init(status: Int = 503) { self.status = status }
    func recover() { status = 200 }
    func hold(_ entered: XCTestExpectation) { self.entered = entered }
    func release() { continuation?.resume(); continuation = nil }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        let path = request.url!.path
        if path.hasSuffix("refresh") { return BackendHTTPResponse(statusCode: 401) }
        if path.hasSuffix("score") { return BackendHTTPResponse(statusCode: 200) }
        if path.hasSuffix("position") { return BackendHTTPResponse(statusCode: 200, data: Data(#"{"rank":3,"userId":7}"#.utf8)) }
        if let entered { self.entered = nil; await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        return BackendHTTPResponse(statusCode: status, data: Data(#"{"ranks":[{"rank":1,"userId":8,"userName":"친구","score":9,"maxStep":9,"maxCombo":2}]}"#.utf8))
    }
}
