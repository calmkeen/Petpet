import XCTest
@testable import PetPetCore

final class StreakAndNicknameTests: XCTestCase {
    func testAndroidPhoneUsesLastSavedDateWhileWatchUsesToday() {
        let saved = records([("2026-11-04", 1), ("2026-11-03", 2), ("2026-11-08", 100)])
        let date = iso("2026-11-07T12:00:00Z")
        XCTAssertEqual(StepStreak(records: saved, date: date, timeZone: .gmt).currentDays, 0)
        let phone = StepStreak(records: saved, date: date, timeZone: .gmt, anchor: .latestRecord)
        XCTAssertEqual(phone.currentDays, 2)
        XCTAssertEqual(phone.anchorDate, "2026-11-04")
        let zero = StepStreak(records: saved + records([("2026-11-07", 0)]), date: date, timeZone: .gmt, anchor: .latestRecord)
        XCTAssertEqual(zero.currentDays, 0)
    }
    func testStreakCountsOneStepAndCrossesYearBoundary() {
        let date = iso("2027-01-02T12:00:00Z")
        let result = StepStreak(records: records([("2027-01-02", 1), ("2027-01-01", 10_000), ("2026-12-31", 2)]), date: date, timeZone: .gmt)
        XCTAssertEqual(result.currentDays, 3)
        XCTAssertEqual(result.today, "2027-01-02")
    }
    func testZeroOrMissingTodayBreaksStreakAndFutureRecordsNeverExtendIt() {
        for today in [[], records([("2026-11-07", 0)])] {
            let result = StepStreak(records: today + records([("2026-11-06", 100), ("2026-11-08", 9000)]), date: iso("2026-11-07T12:00:00Z"), timeZone: .gmt)
            XCTAssertEqual(result.currentDays, 0)
        }
        let gap = StepStreak(records: records([("2026-11-07", 1), ("2026-11-06", 0), ("2026-11-05", 100)]), date: iso("2026-11-07T12:00:00Z"), timeZone: .gmt)
        XCTAssertEqual(gap.currentDays, 1)
    }
    func testStreakUsesLocalDateAndCalendarDaysAcrossDST() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let result = StepStreak(records: records([("2026-03-09", 1), ("2026-03-08", 1), ("2026-03-07", 1)]), date: iso("2026-03-10T01:00:00Z"), timeZone: zone)
        XCTAssertEqual(result.today, "2026-03-09")
        XCTAssertEqual(result.currentDays, 3)
    }
    func testHeatmapBandsMatchAndroidThresholds() {
        let samples: [(Int, StepIntensity)] = [(0,.none),(1,.light),(2999,.light),(3000,.medium),(5999,.medium),(6000,.strong),(9999,.strong),(10000,.goal),(100000,.goal)]
        for (steps, intensity) in samples { XCTAssertEqual(StepIntensity(steps: steps), intensity) }
    }
    func testMonthLeapYearsSundayLayoutAndNavigation() {
        XCTAssertEqual(StepMonth(year: 2026, month: 11)?.leadingEmptyDays, 0)
        XCTAssertEqual(StepMonth(year: 2026, month: 8)?.leadingEmptyDays, 6)
        XCTAssertEqual(StepMonth(year: 2000, month: 2)?.dayCount, 29)
        XCTAssertEqual(StepMonth(year: 1900, month: 2)?.dayCount, 28)
        XCTAssertEqual(StepMonth(year: 2026, month: 12)?.adding(1), StepMonth(year: 2027, month: 1))
        XCTAssertNil(StepMonth(year: 1, month: 1)?.adding(-1))
        XCTAssertNil(StepMonth(year: 9999, month: 12)?.adding(1))
        XCTAssertNil(StepMonth(year: 2026, month: 13))
    }
    func testDuplicateRecordsUseMaximumAndInvalidCountsDoNotInventAStreak() {
        let result = StepStreak(records: records([("2026-11-07", 10), ("2026-11-07", 0), ("invalid", 100), ("2026-11-06", -1)]), date: iso("2026-11-07T12:00:00Z"), timeZone: .gmt)
        XCTAssertEqual(result.currentDays, 1)
        XCTAssertEqual(result.counts["2026-11-07"], 10)
        XCTAssertNil(result.counts["invalid"])
    }
    func testNicknameLengthMatchesKotlinUTF16AndPreservesInput() {
        XCTAssertThrowsError(try NicknameRules.validate("가"))
        XCTAssertThrowsError(try NicknameRules.validate("  "))
        XCTAssertNoThrow(try NicknameRules.validate("🐾"))
        XCTAssertNoThrow(try NicknameRules.validate(" 가"))
        XCTAssertThrowsError(try NicknameRules.validate(String(repeating: "가", count: 256)))
    }
    func testNicknameCheckEscapesQueryAndRenamePersistsServerEcho() async throws {
        let value = "한&글 +?#"
        let store = TestSessionStore(session: session())
        let http = NicknameTestHTTP { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/api/v1/users/nickname/check")
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(items, [URLQueryItem(name: "nickname", value: value)])
                XCTAssertTrue(request.url!.absoluteString.contains("%2B"))
            } else {
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/api/v1/users/nickname")
                XCTAssertEqual(try JSONDecoder().decode([String:String].self, from: request.httpBody!), ["nickname":value])
            }
            return try nicknameResponse(value, duplicated: false)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let available = try await client.checkNickname(value, accountID: "7")
        XCTAssertTrue(available)
        let updated = try await client.updateNickname(value, accountID: "7")
        XCTAssertEqual(updated, value)
        let saved = try await store.load()
        XCTAssertEqual(saved?.nickname, value)
        XCTAssertEqual(saved?.accessToken, "access")
        XCTAssertEqual(saved?.providerSubject, "apple-user")
    }
    func testDuplicateOnSubmitDoesNotOverwriteLocalNickname() async throws {
        let store = TestSessionStore(session: session())
        let client = try BackendClient(baseURL: base, transport: NicknameTestHTTP { _ in try nicknameResponse("다른이름", duplicated: true) }, store: store)
        do { _ = try await client.updateNickname("다른이름", accountID: "7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .nicknameUnavailable) }
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.nickname, "기존이름")
    }
    func testInvalidNicknameNeverReachesServer() async throws {
        let http = NicknameTestHTTP { _ in XCTFail(); throw BackendError.network }
        let client = try BackendClient(baseURL: base, transport: http, store: TestSessionStore(session: session()))
        do { _ = try await client.checkNickname("가", accountID: "7"); XCTFail() } catch {}
        do { _ = try await client.updateNickname("  ", accountID: "7"); XCTFail() } catch {}
    }
    func testAccountStepCacheCannotShowAnotherAccountsHistory() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = FileAccountStepCache(fileURL: file)
        let saved = records([("2026-11-07", 1234)])
        try await cache.save(saved, accountID: "A")
        let other = try await cache.load(accountID: "B")
        let original = try await cache.load(accountID: "A")
        XCTAssertTrue(other.isEmpty)
        XCTAssertEqual(original, saved)
    }
    func testStaleProfileReadCannotUndoSuccessfulRename() async throws {
        let gate = ProfileStorageGate()
        let store = TestSessionStore(session: session())
        let http = NicknameTestHTTP { request in
            if request.httpMethod == "GET" {
                await gate.pause()
                return BackendHTTPResponse(statusCode: 200, data: Data(#"{"nickname":"이전이름"}"#.utf8))
            }
            return try nicknameResponse("새이름", duplicated: false)
        }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let read = Task { try await client.profileNickname(accountID: "7") }
        await gate.waitForPause()
        _ = try await client.updateNickname("새이름", accountID: "7")
        await gate.release()
        let returned = try await read.value
        let saved = try await store.load()
        XCTAssertEqual(returned, "새이름")
        XCTAssertEqual(saved?.nickname, "새이름")
    }
    func testRenameAndTokenRefreshNeverOverwriteEachOthersFields() async throws {
        for refreshFirst in [false, true] {
            let gate = ProfileStorageGate()
            let requestStarted = ProfileTestSignal()
            let store = ProfileBlockingStore(initial: session(), gate: gate, refreshFirst: refreshFirst)
            let http = NicknameTestHTTP { request in
                if request.url?.path == "/api/v1/auth/refresh" {
                    if !refreshFirst { await requestStarted.mark() }
                    return BackendHTTPResponse(statusCode: 200, data: Data(#"{"accessToken":"new-access","refreshToken":"rotated","nickname":"옛이름"}"#.utf8))
                }
                if request.url?.path == "/api/v1/users/nickname" {
                    if refreshFirst { await requestStarted.mark() }
                    return try nicknameResponse("새이름", duplicated: false)
                }
                return BackendHTTPResponse(statusCode: request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? 200 : 401, data: Data("{}".utf8))
            }
            let client = try BackendClient(baseURL: base, transport: http, store: store)
            let request = try ServerBackupRequest(pet: PetProgress.newUser(at: Date()).pet,
                steps: [DailyStepRecord(date: "2026-11-07", stepCount: 1)], timeZone: .gmt)
            if refreshFirst {
                let backup = Task { try await client.saveBackup(request, accountID: "7") }
                await gate.waitForPause()
                let rename = Task { try await client.updateNickname("새이름", accountID: "7") }
                await requestStarted.wait()
                await gate.release()
                _ = try await rename.value; try await backup.value
            } else {
                let rename = Task { try await client.updateNickname("새이름", accountID: "7") }
                await gate.waitForPause()
                let backup = Task { try await client.saveBackup(request, accountID: "7") }
                await requestStarted.wait()
                await gate.release()
                _ = try await rename.value; try await backup.value
            }
            let saved = try await store.load()
            XCTAssertEqual(saved?.nickname, "새이름")
            XCTAssertEqual(saved?.accessToken, "new-access")
            XCTAssertEqual(saved?.refreshToken, "rotated")
        }
    }
    func testLogoutDuringNicknameUpdateDoesNotRestoreSession() async throws {
        let gate = ProfileStorageGate()
        let store = TestSessionStore(session: session())
        let http = NicknameTestHTTP { _ in await gate.pause(); return try nicknameResponse("새이름", duplicated: false) }
        let client = try BackendClient(baseURL: base, transport: http, store: store)
        let change = Task { try await client.updateNickname("새이름", accountID: "7") }
        await gate.waitForPause()
        try await client.signOut()
        await gate.release()
        do { _ = try await change.value; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .sessionChanged) }
        let saved = try await store.load()
        XCTAssertNil(saved)
    }
    #if DEBUG
    func testMockNicknamePersistsAcrossRestartAndRefreshLogin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("server")
        let store = TestSessionStore()
        let client = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL, transport: LocalDevelopmentBackend(fileURL: file), store: store)
        let first = try await client.signInForDevelopment()
        let taken = try await client.checkNickname("사용중닉네임", accountID: first.accountID)
        XCTAssertFalse(taken)
        _ = try await client.updateNickname("워치친구", accountID: first.accountID)
        let restarted = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL, transport: LocalDevelopmentBackend(fileURL: file), store: store)
        let profile = try await restarted.profileNickname(accountID: first.accountID)
        XCTAssertEqual(profile, "워치친구")
        try await restarted.signOut()
        let login = try await restarted.signInForDevelopment()
        XCTAssertEqual(login.nickname, "워치친구")
    }
    func testMockProfileRoutesRequireAuthentication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server"))
        for (path, method) in [("api/v1/users/me","GET"),("api/v1/users/nickname/check?nickname=ab","GET"),("api/v1/users/nickname","PATCH")] {
            var request = URLRequest(url: URL(string: path, relativeTo: LocalDevelopmentBackend.baseURL)!)
            request.httpMethod = method
            let response = try await server.send(request)
            XCTAssertEqual(response.statusCode, 401)
        }
    }
    #endif

    private var base: URL { URL(string: "https://api.example.test/")! }
    private func session() -> BackendSession {
        BackendSession(accountID: "7", serverOrigin: base.absoluteString, accessToken: "access", refreshToken: "refresh",
                       email: nil, name: nil, nickname: "기존이름", identityProvider: .apple, providerSubject: "apple-user")
    }
    private func records(_ pairs: [(String,Int)]) -> [DailyStepRecord] { pairs.map { DailyStepRecord(date: $0.0, stepCount: $0.1) } }
    private func iso(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}

private func nicknameResponse(_ nickname: String, duplicated: Bool) throws -> BackendHTTPResponse {
    BackendHTTPResponse(statusCode: 200, data: try JSONSerialization.data(withJSONObject: ["nickname":nickname,"duplicated":duplicated]))
}
private actor NicknameTestHTTP: BackendHTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> BackendHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> BackendHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse { try await handler(request) }
}

private actor ProfileStorageGate {
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        paused = true; waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForPause() async { if !paused { await withCheckedContinuation { waiters.append($0) } } }
    func release() { continuation?.resume(); continuation = nil }
}
private actor ProfileTestSignal {
    var marked = false
    var continuation: CheckedContinuation<Void, Never>?
    func mark() { marked = true; continuation?.resume(); continuation = nil }
    func wait() async { if !marked { await withCheckedContinuation { continuation = $0 } } }
}
private actor ProfileBlockingStore: BackendSessionStore {
    var value: BackendSession?
    let gate: ProfileStorageGate
    let refreshFirst: Bool
    var blocked = false
    init(initial: BackendSession, gate: ProfileStorageGate, refreshFirst: Bool) { value = initial; self.gate = gate; self.refreshFirst = refreshFirst }
    func load() throws -> BackendSession? { value }
    func clear() throws { value = nil }
    func save(_ session: BackendSession) async throws {
        if !blocked, refreshFirst ? session.accessToken == "new-access" : session.nickname == "새이름" {
            blocked = true; await gate.pause()
        }
        value = session
    }
}
