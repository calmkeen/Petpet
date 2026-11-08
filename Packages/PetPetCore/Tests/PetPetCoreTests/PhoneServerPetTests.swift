import XCTest
@testable import PetPetCore

final class PhoneServerPetTests: XCTestCase {
    private let base = URL(string: "https://phone.example.test/")!
    private let petJSON = #"{"userId":7,"userMateId":42,"mateId":1,"level":3,"experience":1,"affection":2,"attack":52,"defense":4,"health":9,"status":"HAPPY","lastFedAt":"2026-11-08T12:30:00"}"#

    func testPhoneReadsBackedUpPetWithoutFetchingOrRestoringSteps() async throws {
        let body = petJSON
        let http = PhoneAuditHTTP { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/usermates/1")
            return BackendHTTPResponse(statusCode: 200, data: Data(body.utf8))
        }
        let backend = try BackendClient(baseURL: base, transport: http, store: TestSessionStore(session: session()))
        let pet = try await backend.petProfile(accountID: "7", timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(pet.id, 1)
        XCTAssertEqual(pet.level, 3)
        XCTAssertEqual(pet.experience, 1)
        XCTAssertEqual(pet.health, 9)
        XCTAssertNotNil(pet.lastFedAt)
        XCTAssertEqual(pet.statPoints, 0) // The server does not back up unspent points.
    }

    func testPhoneRejectsAnotherAccountsPetAndInvalidProgress() async throws {
        for (body, expected) in [
            (petJSON.replacingOccurrences(of: "\"userId\":7", with: "\"userId\":8"), BackendError.accountMismatch),
            (petJSON.replacingOccurrences(of: "\"level\":3", with: "\"level\":9223372036854775807"), .invalidResponse),
            (petJSON.replacingOccurrences(of: "2026-11-08T12:30:00", with: "invalid"), .invalidResponse)
        ] {
            let http = PhoneAuditHTTP { _ in BackendHTTPResponse(statusCode: 200, data: Data(body.utf8)) }
            let backend = try BackendClient(baseURL: base, transport: http, store: TestSessionStore(session: session()))
            do { _ = try await backend.petProfile(accountID: "7"); XCTFail("Invalid server profile was accepted") }
            catch { XCTAssertEqual(error as? BackendError, expected) }
        }
    }

    func testPetCacheSurvivesRestartAndNeverReturnsAnotherAccountsData() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("server-pet.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pet = PetProgress.newUser(at: Date()).pet
        let saved = try await FileAccountPetCache(fileURL: url).save(pet, accountID: "7", at: Date(timeIntervalSince1970: 100))
        let cache = FileAccountPetCache(fileURL: url)
        let same = try await cache.load(accountID: "7")
        let other = try await cache.load(accountID: "8")
        XCTAssertEqual(same, saved)
        XCTAssertNil(other)
        var invalid = pet; invalid.level = Int64.max
        do { try await cache.save(invalid, accountID: "7", at: Date()); XCTFail() } catch {}
        let unchanged = try await cache.load(accountID: "7")
        XCTAssertEqual(unchanged, saved)
    }

    func testAnyAuthenticatedPhoneRequestNotifiesSessionExpiryOnce() async throws {
        let probe = PhoneInvalidationProbe()
        let http = PhoneAuditHTTP { _ in BackendHTTPResponse(statusCode: 401) }
        let backend = try BackendClient(baseURL: base, transport: http, store: TestSessionStore(session: session()))
        await backend.setSessionInvalidationHandler { await probe.record() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await backend.stepHistory(accountID: "7") }
            group.addTask { _ = try? await backend.petProfile(accountID: "7") }
            await group.waitForAll()
        }
        for _ in 0..<500 { if await probe.count > 0 { break }; await Task.yield() }
        let count = await probe.count
        let current = try await backend.session()
        XCTAssertEqual(count, 1)
        XCTAssertNil(current)
    }

    func testTemporaryServerFailureDoesNotAnnounceSessionRevocation() async throws {
        let probe = PhoneInvalidationProbe()
        let http = PhoneAuditHTTP { _ in BackendHTTPResponse(statusCode: 500) }
        let backend = try BackendClient(baseURL: base, transport: http, store: TestSessionStore(session: session()))
        await backend.setSessionInvalidationHandler { await probe.record() }
        _ = try? await backend.stepHistory(accountID: "7")
        let count = await probe.count
        let current = try await backend.session()
        XCTAssertEqual(count, 0)
        XCTAssertNotNil(current)
    }

    private func session() -> BackendSession {
        BackendSession(accountID: "7", serverOrigin: base.absoluteString, accessToken: "test-access", refreshToken: "test-refresh", email: nil, name: nil, nickname: "Tester")
    }
}

private actor PhoneAuditHTTP: BackendHTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> BackendHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> BackendHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse { try await handler(request) }
}

private actor PhoneInvalidationProbe {
    private(set) var count = 0
    func record() { count += 1 }
}
