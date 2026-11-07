import XCTest
@testable import PetPetCore

final class AppleAuthenticationTests: XCTestCase {
    private let base = URL(string: "https://api.example.test/")!

    func testNativeCredentialsUseDedicatedAppleEndpointAndBackendAccountID() async throws {
        let store = TestSessionStore()
        let http = AppleTestHTTP { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/apple")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            XCTAssertEqual(body, ["identityToken": "apple-id-token", "authorizationCode": "one-time-code",
                                  "rawNonce": String(repeating: "a", count: 64), "userIdentifier": "apple-sub", "name": "Pet Owner"])
            return appleResponse(200, #"{"userId":"7","accessToken":"access","refreshToken":"refresh","email":"relay@example.test"}"#)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let session = try await client.signIn(identity())
        XCTAssertEqual(session.accountID, "7")
        XCTAssertEqual(session.identityProvider, .apple)
        XCTAssertEqual(session.providerSubject, "apple-sub")
        XCTAssertEqual(session.name, "Pet Owner")
        XCTAssertEqual(session.email, "relay@example.test")
        XCTAssertFalse(String(describing: identity()).contains("one-time-code"))
        let persisted = try await store.load()
        XCTAssertEqual(persisted, session)
    }

    func testAppleExchangeRequiresInternalUserIDAndBothBackendTokens() async throws {
        for body in [#"{"accessToken":"access","refreshToken":"refresh"}"#,
                     #"{"userId":"7","accessToken":"access"}"#,
                     #"{"userId":"7","refreshToken":"refresh"}"#] {
            let store = TestSessionStore()
            let client = try BackendClient(baseURL: base, transport: AppleTestHTTP { _ in appleResponse(200, body) }, store: store)
            do { _ = try await client.signIn(identity()); XCTFail() }
            catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
            let persisted = try await store.load()
            XCTAssertNil(persisted)
        }
    }

    func testUnimplementedAppleRouteNeverFallsBackToGoogleOrRetriesCode() async throws {
        for status in [404, 405, 501, 401, 500] {
            let http = AppleTestHTTP { _ in appleResponse(status) }
            let client = try BackendClient(baseURL: base, transport: http, store: TestSessionStore())
            do { _ = try await client.signIn(identity()); XCTFail() }
            catch {
                XCTAssertEqual(error as? BackendError,
                               [404, 405, 501].contains(status) ? .appleLoginUnavailable : .http(status))
            }
            let calls = await http.requests
            XCTAssertEqual(calls.map { $0.url!.path }, ["/api/v1/auth/apple"])
        }
    }

    func testMalformedNativeCredentialCannotClearExistingSessionOrReachNetwork() async throws {
        let original = BackendSession(accountID: "7", serverOrigin: base.absoluteString, accessToken: "access", refreshToken: "refresh", email: nil, name: nil, nickname: nil)
        let store = TestSessionStore(session: original)
        let http = AppleTestHTTP { _ in XCTFail("No HTTP request expected"); return appleResponse(500) }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let malformed = AppleIdentity(userIdentifier: "apple-sub", identityToken: "token", authorizationCode: "", rawNonce: "short")
        do { _ = try await client.signIn(malformed); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .invalidAppleCredential) }
        let saved = try await store.load()
        XCTAssertEqual(saved, original)
    }

    func testRefreshPreservesAppleCredentialAssociationAndUsesBackendRefreshToken() async throws {
        let store = TestSessionStore()
        let http = AppleTestHTTP { request in
            switch request.url!.path {
            case "/api/v1/auth/apple":
                return appleResponse(200, #"{"userId":7,"accessToken":"old-access","refreshToken":"backend-refresh"}"#)
            case "/api/v1/auth/refresh":
                let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
                XCTAssertEqual(body, ["refreshToken": "backend-refresh"])
                return appleResponse(200, #"{"userId":7,"accessToken":"new-access","refreshToken":"rotated"}"#)
            default:
                return appleResponse(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? 200 : 401)
            }
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        _ = try await client.signIn(identity())
        try await client.saveBackup(ServerBackupRequest(pet: PetProgress.newUser(at: Date()).pet,
                                                       steps: [DailyStepRecord(date: "2026-11-07", stepCount: 1234)],
                                                       timeZone: .gmt), accountID: "7")
        let refreshed = try await store.load()
        XCTAssertEqual(refreshed?.identityProvider, .apple)
        XCTAssertEqual(refreshed?.providerSubject, "apple-sub")
        XCTAssertEqual(refreshed?.refreshToken, "rotated")
    }

    func testLegacyKeychainSessionsDecodeWithoutProviderFields() throws {
        let legacy = #"{"accountID":"7","serverOrigin":"https://api.example.test/","accessToken":"access","selectedMateID":1,"isNewUser":false}"#
        let session = try JSONDecoder().decode(BackendSession.self, from: Data(legacy.utf8))
        XCTAssertEqual(session.accountID, "7")
        XCTAssertNil(session.identityProvider)
        XCTAssertNil(session.providerSubject)
    }

    func testAuthorizationStateAndAgeRejectUnrelatedOrExpiredCallbacks() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let attempt = AppleSignInAttempt(rawNonce: String(repeating: "a", count: 64), state: "request-state", createdAt: now)
        XCTAssertNoThrow(try attempt.validate(returnedState: "request-state", at: now.addingTimeInterval(299)))
        for state in [nil, "", "different-request"] {
            XCTAssertThrowsError(try attempt.validate(returnedState: state, at: now)) {
                XCTAssertEqual($0 as? BackendError, .invalidAppleCredential)
            }
        }
        for age in [-1.0, 300.0, 301.0] {
            XCTAssertThrowsError(try attempt.validate(returnedState: "request-state", at: now.addingTimeInterval(age))) {
                XCTAssertEqual($0 as? BackendError, .operationExpired)
            }
        }
    }

    func testLogoutWhileAppleExchangeIsInFlightCannotResurrectSession() async throws {
        let gate = AppleExchangeGate()
        let store = TestSessionStore()
        let http = AppleTestHTTP { _ in
            await gate.pause()
            return appleResponse(200, #"{"userId":7,"accessToken":"late-access","refreshToken":"late-refresh"}"#)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let identity = identity()
        let login = Task { try await client.signIn(identity) }
        await gate.waitUntilPaused()
        try await client.signOut()
        await gate.release()
        do { _ = try await login.value; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .sessionChanged) }
        let saved = try await store.load()
        XCTAssertNil(saved)
    }

    private func identity() -> AppleIdentity {
        AppleIdentity(userIdentifier: "apple-sub", identityToken: "apple-id-token", authorizationCode: "one-time-code",
                      rawNonce: String(repeating: "a", count: 64), name: "Pet Owner")
    }
}

private func appleResponse(_ status: Int, _ body: String = "{}") -> BackendHTTPResponse {
    BackendHTTPResponse(statusCode: status, data: Data(body.utf8))
}

private actor AppleTestHTTP: BackendHTTPTransport {
    var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) async throws -> BackendHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> BackendHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

private actor AppleExchangeGate {
    var continuation: CheckedContinuation<Void, Never>?
    var ready: CheckedContinuation<Void, Never>?
    var paused = false
    func pause() async {
        paused = true; ready?.resume(); ready = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilPaused() async {
        if !paused { await withCheckedContinuation { ready = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}
