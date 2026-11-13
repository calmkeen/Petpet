import XCTest
import UIKit
import PetPetCore
@testable import PetPet

@MainActor final class PhoneAPIParityTests: XCTestCase {
    private let url = URL(string: "https://phone.example.test/")!
    func testBothKindsKeepServerValuesAndGlobalRanks() async throws {
        let f = try await context()
        let steps = f.account.makeRankingModel(.steps)
        steps.load(2); await steps.finishWork()
        XCTAssertEqual(steps.page, 2); XCTAssertEqual(steps.stepPage?.rankings.first?.rank, 6)
        XCTAssertEqual(steps.stepPage?.rankings.first?.totalStepCount, 123456)
        for game in MiniGame.allCases {
            let model = f.account.makeRankingModel(.game(game)); model.load(2); await model.finishWork()
            XCTAssertEqual(model.page, 2); XCTAssertEqual(model.gamePage?.entries.first?.rank, 6)
            XCTAssertEqual(model.gamePage?.entries.first?.score, game == .shooting ? 88 : 44)
            XCTAssertEqual(model.gamePage?.entries.first?.maxCombo, 22)
        }
    }
    func testFailedNextPageKeepsDataAndRetryWorks() async throws {
        let f = try await context(); let model = f.account.makeRankingModel(.steps)
        model.load(); await model.finishWork(); let first = model.stepPage
        await f.http.setFailPage(2)
        model.load(2); await model.finishWork()
        XCTAssertEqual(model.stepPage, first); XCTAssertNotNil(model.error); XCTAssertFalse(model.busy)
        await f.http.setFailPage(nil)
        model.load(2); await model.finishWork(); XCTAssertEqual(model.page, 2); XCTAssertNil(model.error)
    }
    func testLogoutDiscardsLatePageAndStopsBusyState() async throws {
        let f = try await context(); let model = f.account.makeRankingModel(.steps)
        let entered = expectation(description: "Delayed page entered"); await f.http.holdNext(entered)
        let work = Task { model.load(2); await model.finishWork() }
        await fulfillment(of: [entered], timeout: 3)
        await f.account.signOut(); await f.http.release(); await work.value
        XCTAssertNil(model.stepPage); XCTAssertNil(model.accountID); XCTAssertFalse(model.busy)
    }
    func testLogoutDiscardsLatePictureUpload() async throws {
        let f = try await context(); let image = try fixture()
        let entered = expectation(description: "Delayed picture entered"); await f.http.holdNext(entered)
        let work = Task { await f.account.updatePicture(image) }
        await fulfillment(of: [entered], timeout: 3)
        await f.account.signOut(); await f.http.release(); await work.value
        XCTAssertNil(f.account.profileDetails); XCTAssertNil(f.account.session)
        XCTAssertFalse(f.account.isUpdatingPicture); XCTAssertNil(f.account.pictureMessage)
    }
    func testRelayedProfileUpdatesOnlyTheMatchingAccount() async throws {
        let f = try await context()
        let details = AccountProfileDetails(nickname: "Tester", pictureURL: URL(string: "https://image.example.test/relayed.jpg"))
        f.account.acceptProfile(details, accountID: "other")
        XCTAssertNil(f.account.profileDetails)
        f.account.acceptProfile(details, accountID: "7")
        XCTAssertEqual(f.account.profileDetails, details)
        await f.account.signOut(); XCTAssertNil(f.account.profileDetails)
    }
    func testSuccessfulProfileRetryClearsPreviousError() async throws {
        let f = try await context()
        await f.http.failProfile(true); await f.account.refreshProfile()
        XCTAssertNotNil(f.account.pictureMessage); XCTAssertFalse(f.account.isRefreshingProfile)
        await f.http.failProfile(false); await f.account.refreshProfile()
        XCTAssertNil(f.account.pictureMessage); XCTAssertEqual(f.account.profileDetails?.nickname, "Tester")
    }
    func testCloudSessionInvalidationClearsDisplayedProfileImmediately() async throws {
        let f = try await context()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = PhoneCloudCoordinator(backend: f.backend, transport: PhoneParityCloud(),
            receipts: FileCloudReceiptStore(fileURL: root.appendingPathComponent("receipts.json")), directory: root, environment: .development)
        let account = AccountViewModel(backend: f.backend, cloud: cloud)
        await account.start(); await account.refreshProfile()
        XCTAssertNotNil(account.profileDetails)
        try await f.backend.signOut(); await cloud.synchronizeAccount()
        XCTAssertNil(account.session); XCTAssertNil(account.profileDetails)
        XCTAssertNil(account.pictureMessage); XCTAssertFalse(account.isRefreshingProfile)
    }
    func testPictureRestoresAcrossModelAndBackendRestartAndInvalidInputKeepsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneParityStore(nil)
        func client() throws -> BackendClient { try BackendClient(baseURL: LocalDevelopmentBackend.baseURL, transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server")), store: store) }
        let first = AccountViewModel(backend: try client()); await first.signInForDevelopment()
        await first.updatePicture(try fixture()); let saved = try XCTUnwrap(first.profileDetails)
        XCTAssertNotNil(saved.pictureURL); XCTAssertNotNil(saved.preview); XCTAssertFalse(first.isUpdatingPicture)
        let restarted = AccountViewModel(backend: try client()); await restarted.start(); await restarted.refreshProfile()
        XCTAssertEqual(restarted.profileDetails, saved)
        await restarted.updatePicture(Data("corrupt".utf8))
        XCTAssertEqual(restarted.profileDetails, saved); XCTAssertNotNil(restarted.pictureMessage)
        await restarted.signOut(); XCTAssertNil(restarted.profileDetails)
    }
    private func context() async throws -> (account: AccountViewModel, http: PhoneParityHTTP, backend: BackendClient) {
        let http = PhoneParityHTTP()
        let session = BackendSession(accountID: "7", serverOrigin: url.absoluteString, accessToken: "test-access", refreshToken: nil, email: nil, name: nil, nickname: "Tester")
        let backend = try BackendClient(baseURL: url, transport: http, store: PhoneParityStore(session))
        let account = AccountViewModel(backend: backend)
        await account.start(); return (account, http, backend)
    }
    private func fixture() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        return try XCTUnwrap(renderer.image { c in UIColor.systemBlue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) }.pngData())
    }
}
private actor PhoneParityStore: BackendSessionStore {
    var value: BackendSession?
    init(_ value: BackendSession?) { self.value = value }
    func load() -> BackendSession? { value }
    func save(_ session: BackendSession) { value = session }
    func clear() { value = nil }
}
private actor PhoneParityHTTP: BackendHTTPTransport {
    var failedPage: Int?
    var entered: XCTestExpectation?
    var continuation: CheckedContinuation<Void,Never>?
    var profileFails = false
    func failProfile(_ value: Bool) { profileFails = value }
    func setFailPage(_ value: Int?) { failedPage = value }
    func holdNext(_ value: XCTestExpectation) { entered = value }
    func release() { continuation?.resume(); continuation = nil }
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        if let signal = entered { entered = nil; await withCheckedContinuation { continuation = $0; signal.fulfill() } }
        let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1")!
        if failedPage == page { return BackendHTTPResponse(statusCode: 500) }
        let body: String
        if request.url!.path.hasSuffix("users/me") {
            if profileFails { return BackendHTTPResponse(statusCode: 503) }
            body = #"{"nickname":"Tester","pictureUrl":"https://image.example.test/avatar.jpg"}"#
        }
        else if request.httpMethod == "PATCH" { body = #"{"pictureUrl":"https://image.example.test/avatar.jpg"}"# }
        else if request.url!.path.contains("stepcounts/ranking") { body = "{\"page\":\(page),\"size\":5,\"totalUsers\":12,\"rankings\":[{\"rank\":\((page-1)*5+1),\"userId\":8,\"nickname\":\"친구\",\"totalStepCount\":123456}]}" }
        else { body = #"{"ranks":[{"rank":6,"userId":8,"userName":"친구","score":88,"maxStep":44,"maxCombo":22}]}"# }
        return BackendHTTPResponse(statusCode: 200, data: Data(body.utf8))
    }
}
@MainActor private final class PhoneParityCloud: CloudTransport {
    var connection = SnapshotConnection(isActivated: false, isPaired: false, isCounterpartInstalled: false, isReachable: false)
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    func enqueueCloudControl(_ data: Data) {}
    func enqueueCloudFile(_ url: URL) throws { throw BackendError.watchUnavailable }
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
}
