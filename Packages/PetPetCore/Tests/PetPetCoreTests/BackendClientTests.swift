import XCTest
@testable import PetPetCore

final class BackendClientTests: XCTestCase {
    private let base = URL(string: "https://api.example.test/")!

    func testGoogleExchangeUsesIDTokenAndAcceptsAndroidResponseAliases() async throws {
        let store = TestSessionStore()
        let http = TestBackendHTTP { request in
            XCTAssertEqual(request.url?.path, "/api/v1/google")
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            XCTAssertEqual(body, ["idToken": "google-id-token"])
            return response(200, #"{"access_token":"access","refresh_token":"refresh","userId":7,"selected_mate_id":1,"newUser":true}"#)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let session = try await client.signIn(GoogleIdentity(subject: "google-sub", idToken: "google-id-token", email: "test@example.test", name: "Test"))
        XCTAssertEqual(session.accountID, "7")
        XCTAssertEqual(session.email, "test@example.test")
        XCTAssertTrue(session.isNewUser)
        let saved = try await store.load()
        XCTAssertEqual(saved, session)
        XCTAssertFalse(String(describing: session).contains("refresh"))
    }

    func testConcurrent401sShareOneRefreshAndPreserveRefreshTokenWhenOmitted() async throws {
        let store = TestSessionStore(session: saved())
        let http = TestBackendHTTP { request in
            if request.url?.path == "/api/v1/auth/refresh" { return response(200, #"{"accessToken":"new-access"}"#) }
            return response(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? 200 : 401)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let backup = try request()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<15 { group.addTask { try await client.saveBackup(backup, accountID: "7") } }
            try await group.waitForAll()
        }
        let calls = await http.requests
        XCTAssertEqual(calls.filter { $0.url?.path == "/api/v1/auth/refresh" }.count, 1)
        let session = try await store.load()
        XCTAssertEqual(session?.accessToken, "new-access")
        XCTAssertEqual(session?.refreshToken, "refresh")
    }

    func testRefreshLegacyFallbackOnlyFor404Or405() async throws {
        for status in [404, 405, 500] {
            let store = TestSessionStore(session: saved())
            let http = TestBackendHTTP { request in
                switch request.url?.path {
                case "/api/v1/auth/refresh": return response(status)
                case "/api/v1/refresh": return response(200, #"{"accessToken":"new-access","refreshToken":"rotated"}"#)
                default: return response(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? 200 : 401)
                }
            }
            let client = try BackendClient(baseURL: base, transport: http, store: store)
            do { try await client.saveBackup(request(), accountID: "7"); XCTAssertNotEqual(status, 500) }
            catch { XCTAssertEqual(status, 500) }
            let calls = await http.requests
            XCTAssertEqual(calls.contains { $0.url?.path == "/api/v1/refresh" }, status != 500)
            let session = try await store.load()
            XCTAssertNotNil(session) // transient server failure does not sign out
        }
    }

    func testInvalidRefreshClearsSessionAndDoesNotRetryForever() async throws {
        let store = TestSessionStore(session: saved())
        let http = TestBackendHTTP { _ in response(401) }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        do { try await client.saveBackup(request(), accountID: "7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .authenticationRequired) }
        let saved = try await store.load()
        XCTAssertNil(saved)
        let calls = await http.requests
        XCTAssertEqual(calls.count, 2)
    }

    func testLogoutDuringRefreshCannotResurrectCredentials() async throws {
        let gate = BackendGate()
        let store = TestSessionStore(session: saved())
        let http = TestBackendHTTP { request in
            if request.url?.path == "/api/v1/auth/refresh" {
                await gate.pause()
                return response(200, #"{"accessToken":"stale-after-logout"}"#)
            }
            return response(401)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let backup = try request()
        let job = Task { try await client.saveBackup(backup, accountID: "7") }
        await gate.waitUntilPaused()
        try await client.signOut()
        await gate.release()
        do { try await job.value; XCTFail() } catch {}
        let persisted = try await store.load()
        let current = try await client.session()
        XCTAssertNil(persisted)
        XCTAssertNil(current)
    }

    func testOriginAndAccountGuardsPreventSendingAnotherSessionsToken() async throws {
        let store = TestSessionStore(session: saved(origin: "https://other.example.test/"))
        let http = TestBackendHTTP { _ in XCTFail("Must not send credentials"); return response(200) }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        do { try await client.saveBackup(request(), accountID: "7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .authenticationRequired) }
        XCTAssertThrowsError(try BackendClient(baseURL: URL(string: "http://api.example.test")!, transport: http, store: store))
    }

    func testAccountSwitchDoesNotAuthorizeOldAccountWorkDuringSignIn() async throws {
        let gate = BackendGate()
        let store = TestSessionStore(session: saved())
        let http = TestBackendHTTP { request in
            XCTAssertEqual(request.url?.path, "/api/v1/google")
            await gate.pause()
            return response(200, #"{"userId":"8","accessToken":"account-B","refreshToken":"refresh-B"}"#)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        _ = try await client.session()
        let login = Task {
            try await client.signIn(GoogleIdentity(subject: "B", idToken: "google-B", email: nil, name: nil))
        }
        await gate.waitUntilPaused()
        do { try await client.saveBackup(request(), accountID: "7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .authenticationRequired) }
        await gate.release()
        let session = try await login.value
        XCTAssertEqual(session.accountID, "8")
        let calls = await http.requests
        XCTAssertEqual(calls.count, 1)
    }

    func testBackupRequestMatchesAndroidFieldsAndLocalDateTime() throws {
        let data = try JSONEncoder().encode(request())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["userMateId", "stepCounts", "level", "experience", "affection", "attack", "defense", "health", "status", "lastFedAt"]))
        XCTAssertEqual(body["userMateId"] as? Int, 1)
        let lastFed = try XCTUnwrap(body["lastFedAt"] as? String)
        XCTAssertFalse(lastFed.hasSuffix("Z"))
        XCTAssertNotNil(ServerDateTime.date(lastFed, timeZone: TimeZone(identifier: "Asia/Seoul")!))
    }

    func testRestoreReadsBothEndpointsAndChecksSameServerUser() async throws {
        for mismatched in [false, true] {
            let store = TestSessionStore(session: saved())
            let http = TestBackendHTTP { request in
                if request.url?.path == "/api/v1/usermates/1" {
                    return response(200, #"{"userId":7,"userMateId":42,"mateId":1,"level":3,"experience":1,"affection":2,"attack":52,"defense":0,"health":8,"status":"HAPPY","lastFedAt":"2026-11-07T12:30:00"}"#)
                }
                return response(200, mismatched
                    ? #"{"userId":8,"stepCounts":[{"date":"2026-11-07","stepCount":1234}]}"#
                    : #"{"userId":7,"stepCounts":[{"date":"2026-11-07","stepCount":1234}]}"#)
            }
            let client = try BackendClient(baseURL: base, transport: http, store: store)
            do {
                let restored = try await client.restore(accountID: "7")
                XCTAssertFalse(mismatched)
                XCTAssertEqual(restored.pet.level, 3)
                XCTAssertEqual(restored.pet.id, 1) // catalog ID, not the server row ID 42
                XCTAssertEqual(restored.steps.first?.stepCount, 1234)
            } catch { XCTAssertTrue(mismatched); XCTAssertEqual(error as? BackendError, .accountMismatch) }
        }
    }

    private func saved(origin: String = "https://api.example.test/") -> BackendSession {
        BackendSession(accountID: "7", serverOrigin: origin, accessToken: "old-access", refreshToken: "refresh", email: nil, name: nil, nickname: nil)
    }
    private func request() throws -> ServerBackupRequest {
        try ServerBackupRequest(pet: PetProgress.newUser(at: Date()).pet,
                                steps: [DailyStepRecord(date: "2026-11-07", stepCount: 1234)],
                                timeZone: TimeZone(identifier: "Asia/Seoul")!)
    }
}

private func response(_ code: Int, _ body: String = "{}") -> BackendHTTPResponse {
    BackendHTTPResponse(statusCode: code, data: Data(body.utf8))
}

actor TestSessionStore: BackendSessionStore {
    var value: BackendSession?
    init(session: BackendSession? = nil) { value = session }
    func load() throws -> BackendSession? { value }
    func save(_ session: BackendSession) throws { value = session }
    func clear() throws { value = nil }
}

private actor TestBackendHTTP: BackendHTTPTransport {
    var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) async throws -> BackendHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> BackendHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

private actor BackendGate {
    var continuation: CheckedContinuation<Void, Never>?
    var paused = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        paused = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}
