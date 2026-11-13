import XCTest
@testable import PetPetCore
import ImageIO
import UniformTypeIdentifiers

final class CommunityAPITests: XCTestCase {
    private var origin: URL { URL(string: "https://api.example.test/")! }
    private func session() -> BackendSession { BackendSession(accountID: "7", serverOrigin: origin.absoluteString, accessToken: "access", refreshToken: "refresh", email: nil, name: nil, nickname: "여우") }
    func testStepRankingUsesRequiredPageSizeAndInt64Total() async throws {
        let http = CommunityHTTP { request in
            XCTAssertEqual(request.url?.path, "/api/v1/stepcounts/ranking")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
                [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "size", value: "5")])
            return BackendHTTPResponse(statusCode: 200, data: Data(#"{"page":2,"size":5,"totalUsers":11,"rankings":[{"rank":6,"userId":9,"nickname":"친구","totalStepCount":9223372036854775806}]}"#.utf8))
        }
        let client = try BackendClient(baseURL: origin, transport: http, store: TestSessionStore(session: session()))
        let page = try await client.stepRanking(RankingPageRequest(page: 2), accountID: "7")
        XCTAssertEqual(page.rankings.first?.totalStepCount, Int64.max - 1); XCTAssertTrue(page.hasNext)
    }
    func testGameRangeUsesBothAndroidPathsAndKeepsGlobalRanks() async throws {
        let http = CommunityHTTP { request in
            XCTAssertTrue(["/api/v1/shooting-game/rank/range", "/api/v1/star-stair-game/rank/range"].contains(request.url!.path))
            XCTAssertEqual(request.httpMethod, "GET")
            return BackendHTTPResponse(statusCode: 200, data: Data(#"{"ranks":[{"rank":6,"userId":9,"userName":"친구","score":12,"maxStep":34,"maxCombo":8}]}"#.utf8))
        }
        let client = try BackendClient(baseURL: origin, transport: http, store: TestSessionStore(session: session()))
        for game in MiniGame.allCases {
            let result = try await client.gameRankingPage(game, page: RankingPageRequest(page: 2), accountID: "7")
            XCTAssertEqual(result.entries.first?.rank, 6); XCTAssertEqual(result.entries.first?.score, game == .shooting ? 12 : 34)
            XCTAssertFalse(result.hasNext)
        }
    }
    func testInvalidPagesNeverReachTransport() async throws {
        let http = CommunityHTTP { _ in XCTFail("Invalid page sent"); throw BackendError.network }
        let client = try BackendClient(baseURL: origin, transport: http, store: TestSessionStore(session: session()))
        for page in [RankingPageRequest(page: 0), RankingPageRequest(page: 10001), RankingPageRequest(size: 0), RankingPageRequest(size: 11)] {
            do { _ = try await client.stepRanking(page, accountID: "7"); XCTFail() } catch {}
            do { _ = try await client.gameRankingPage(.shooting, page: page, accountID: "7"); XCTFail() } catch {}
        }
    }
    func testWrongPageAndDuplicateRowsAreRejected() async throws {
        for body in [#"{"page":2,"size":5,"totalUsers":0,"rankings":[]}"#,
                     #"{"page":1,"size":5,"totalUsers":2,"rankings":[{"rank":1,"userId":9,"nickname":"a","totalStepCount":1},{"rank":1,"userId":9,"nickname":"a","totalStepCount":1}]}"#] {
            let client = try BackendClient(baseURL: origin, transport: CommunityHTTP { _ in BackendHTTPResponse(statusCode: 200, data: Data(body.utf8)) }, store: TestSessionStore(session: session()))
            do { _ = try await client.stepRanking(RankingPageRequest(), accountID: "7"); XCTFail() }
            catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        }
    }
    func testMalformedNewAPIRepliesUseUserFacingBackendError() async throws {
        let client = try BackendClient(baseURL: origin, transport: CommunityHTTP { _ in BackendHTTPResponse(statusCode: 200, data: Data("{}".utf8)) }, store: TestSessionStore(session: session()))
        do { _ = try await client.stepRanking(RankingPageRequest(), accountID: "7"); XCTFail() } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        do { _ = try await client.gameRankingPage(.shooting, page: RankingPageRequest(), accountID: "7"); XCTFail() } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        do { _ = try await client.updatePicture(fixture(), accountID: "7"); XCTFail() } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
    }
    func testMultipartRefreshPreservesExactBodyAndImageField() async throws {
        let image = try fixture()
        let http = AvatarRefreshHTTP()
        let client = try BackendClient(baseURL: origin, transport: http, store: TestSessionStore(session: session()))
        let profile = try await client.updatePicture(image, accountID: "7")
        XCTAssertEqual(profile.pictureURL?.absoluteString, "https://images.example.test/new.jpg"); XCTAssertEqual(profile.preview, image)
        let requests = await http.uploads; XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        let parsed = try RepresentativeImage.fromMultipart(requests[0].httpBody!, contentType: requests[0].value(forHTTPHeaderField: "Content-Type")!)
        XCTAssertEqual(parsed, image)
    }
    func testStaleProfileReadCannotUndoNewPicture() async throws {
        let http = HeldProfileHTTP()
        let client = try BackendClient(baseURL: origin, transport: http, store: TestSessionStore(session: session()))
        let task = Task { try await client.profileDetails(accountID: "7") }
        for _ in 0..<200 { if await http.held { break }; try await Task.sleep(for: .milliseconds(5)) }
        _ = try await client.updatePicture(fixture(), accountID: "7")
        await http.release()
        let result = try await task.value
        XCTAssertEqual(result.pictureURL?.absoluteString, "https://images.example.test/new.jpg")
    }
    func testImageNormalizationBoundsAndMultipartValidation() throws {
        let image = try fixture()
        XCTAssertLessThanOrEqual(image.data.count, 32_000); XCTAssertEqual(image.mimeType, "image/jpeg")
        let body = try image.multipart(boundary: "PetPet-test")
        XCTAssertEqual(try RepresentativeImage.fromMultipart(body, contentType: "multipart/form-data; boundary=PetPet-test"), image)
        XCTAssertThrowsError(try RepresentativeImage.fromMultipart(body, contentType: "application/json"))
        XCTAssertThrowsError(try RepresentativeImage(data: Data("not an image".utf8)))
        XCTAssertThrowsError(try RepresentativeImage(data: Data(repeating: 0, count: 32001)))
        XCTAssertThrowsError(try RepresentativeImage.thumbnail(from: Data("corrupt".utf8)))
        XCTAssertThrowsError(try AccountProfileDetails.imageURL("http://unsafe.test/a.jpg"))
    }
    func testEncodedImageCannotBypassTransportSizeLimit() throws {
        let data = try JSONEncoder().encode(["data": Data(repeating: 1, count: 32001)])
        XCTAssertThrowsError(try JSONDecoder().decode(RepresentativeImage.self, from: data))
        let malformed = Data("--b\r\nContent-Disposition: form-data; name=\"image\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n--b--\r\n".utf8)
        XCTAssertThrowsError(try RepresentativeImage.fromMultipart(malformed, contentType: "multipart/form-data; boundary=b"))
    }
    #if DEBUG
    @MainActor func testStandaloneMockAllPagesPictureAndRestartWithoutPhone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TestSessionStore()
        func backend() throws -> BackendClient { try BackendClient(baseURL: LocalDevelopmentBackend.baseURL, transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server")), store: store) }
        let client = try backend()
        let service = WatchStandaloneService(backend: client, game: FileGameRepository(directory: root), receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts")), modeURL: root.appendingPathComponent("mode"), environment: .development)
        try await service.start(); try await service.signInForDevelopment()
        let phone = RejectCommunityPhone()
        let wire = WatchFeatureClient(transport: WatchFeatureRouter(direct: service, companion: phone), environment: .development)
        let id = try XCTUnwrap(service.state.account?.id)
        var users = Set<Int64>()
        for page in 1...5 {
            guard case let .stepPage(value) = try await wire.request(.stepPage(RankingPageRequest(page: page)), accountID: id) else { return XCTFail() }
            XCTAssertEqual(value.page, page)
            users.formUnion(value.rankings.map(\.userId)); XCTAssertEqual(value.hasNext, page < 5)
        }
        XCTAssertEqual(users.count, 23)
        for game in MiniGame.allCases {
            var all = Set<Int64>()
            for page in 1...4 {
                guard case let .gamePage(value) = try await wire.request(.gamePage(game, RankingPageRequest(page: page)), accountID: id) else { return XCTFail() }
                all.formUnion(value.entries.compactMap(\.userID)); XCTAssertEqual(value.hasNext, page < 4)
            }
            XCTAssertEqual(all.count, 18)
        }
        let image = try fixture()
        guard case let .profile(updated) = try await wire.request(.updatePicture(image), accountID: id) else { return XCTFail() }
        let restarted = try backend()
        let profile = try await restarted.profileDetails(accountID: id)
        XCTAssertEqual(profile.pictureURL, updated.pictureURL); XCTAssertEqual(profile.preview, image); XCTAssertEqual(phone.calls, 0)
    }
    @MainActor func testCompanionMockUsesSameNewFeatureContracts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL, transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server")), store: TestSessionStore())
        let session = try await backend.signInForDevelopment()
        let transport = CommunityLoopback(); let host = PhoneFeatureCoordinator(backend: backend, transport: transport, environment: .development)
        defer { host.accountChanged() }
        var deliveredProfile: AccountProfileDetails?
        host.onProfileChange = { id, profile in XCTAssertEqual(id, session.accountID); deliveredProfile = profile }
        let client = WatchFeatureClient(transport: transport, environment: .development)
        guard case let .stepPage(page) = try await client.request(.stepPage(RankingPageRequest(page: 2)), accountID: session.accountID) else { return XCTFail() }
        XCTAssertEqual(page.page, 2)
        guard case let .profile(profile) = try await client.request(.updatePicture(fixture()), accountID: session.accountID) else { return XCTFail() }
        XCTAssertNotNil(profile.preview); XCTAssertEqual(deliveredProfile, profile)
        do { _ = try await client.request(.profile, accountID: "other"); XCTFail() } catch { XCTAssertEqual(error as? BackendError, .authenticationRequired) }
    }
    #endif
    private func fixture() throws -> RepresentativeImage {
        let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = NSMutableData(); let target = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(target, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(target))
        return try RepresentativeImage.thumbnail(from: data as Data)
    }
}
private actor CommunityHTTP: BackendHTTPTransport {
    let handler: @Sendable (URLRequest) throws -> BackendHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) throws -> BackendHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse { try handler(request) }
}
private actor AvatarRefreshHTTP: BackendHTTPTransport {
    var uploads: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        if request.url!.path.hasSuffix("/refresh") { return BackendHTTPResponse(statusCode: 200, data: Data(#"{"userId":7,"accessToken":"new","refreshToken":"next"}"#.utf8)) }
        XCTAssertEqual(request.url?.path, "/api/v1/users/me/picture"); XCTAssertEqual(request.httpMethod, "PATCH")
        uploads.append(request)
        return BackendHTTPResponse(statusCode: uploads.count == 1 ? 401 : 200, data: Data(#"{"pictureUrl":"https://images.example.test/new.jpg"}"#.utf8))
    }
}
private actor HeldProfileHTTP: BackendHTTPTransport {
    var held = false
    var waiter: CheckedContinuation<Void,Never>?
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        if request.httpMethod == "GET" { await withCheckedContinuation { held = true; waiter = $0 }; return BackendHTTPResponse(statusCode: 200, data: Data(#"{"nickname":"여우","pictureUrl":"https://images.example.test/old.jpg"}"#.utf8)) }
        return BackendHTTPResponse(statusCode: 200, data: Data(#"{"pictureUrl":"https://images.example.test/new.jpg"}"#.utf8))
    }
    func release() { waiter?.resume(); waiter = nil }
}
@MainActor private final class RejectCommunityPhone: CompanionFeatureTransport {
    var calls = 0
    var onFeatureRequest: ((Data) async throws -> Data)?
    func requestFeature(_ data: Data) async throws -> Data { calls += 1; throw BackendError.watchUnavailable }
}
@MainActor private final class CommunityLoopback: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    func requestFeature(_ data: Data) async throws -> Data { try await onFeatureRequest!(data) }
}
