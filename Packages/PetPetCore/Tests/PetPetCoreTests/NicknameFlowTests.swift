import XCTest
@testable import PetPetCore

@MainActor
final class NicknameFlowTests: XCTestCase {
    func testEditorIgnoresOldAvailabilityResponseAndOnlySubmitsCheckedValue() async throws {
        let gate = NicknameFlowGate()
        var submitted: [String] = []
        let editor = NicknameEditor(currentNickname: "원래이름", debounce: .zero, check: { value in
            if value == "첫이름" { await gate.pause(); return false }
            return true
        }, update: { submitted.append($0); return $0 })
        editor.setInput("첫이름")
        await gate.waitForPause()
        editor.setInput("새이름")
        await editor.finishCheck()
        await gate.release()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(editor.state.input, "새이름")
        XCTAssertEqual(editor.state.status, .available)
        await editor.submit()
        XCTAssertEqual(submitted, ["새이름"])
        XCTAssertEqual(editor.state.currentNickname, "새이름")
    }
    func testEditorInvalidOrUnchangedInputDoesNotRequestNetwork() async {
        var checks = 0
        let editor = NicknameEditor(currentNickname: "원래이름", debounce: .zero, check: { _ in checks += 1; return true }, update: { $0 })
        for input in ["", "  ", "가", "원래이름"] {
            editor.setInput(input)
            await editor.finishCheck()
            await editor.submit()
            XCTAssertFalse(editor.state.canSubmit)
        }
        XCTAssertEqual(checks, 0)
    }
    func testEditorNetworkErrorIsDifferentFromDuplicateAndCanRetry() async {
        var attempt = 0
        let editor = NicknameEditor(currentNickname: "현재이름", debounce: .zero, check: { _ in
            attempt += 1
            if attempt == 1 { throw BackendError.network }
            return true
        }, update: { _ in throw BackendError.nicknameUnavailable })
        editor.setInput("새이름")
        await editor.finishCheck()
        XCTAssertEqual(editor.state.status, .failed)
        editor.retry(); await editor.finishCheck()
        XCTAssertEqual(editor.state.status, .available)
        await editor.submit()
        XCTAssertEqual(editor.state.status, .unavailable)
        XCTAssertEqual(editor.state.currentNickname, "현재이름")
    }
    #if DEBUG
    func testWatchRelayChecksAndChangesNicknameThroughPhoneWithoutCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = try BackendClient(baseURL: LocalDevelopmentBackend.baseURL,
            transport: LocalDevelopmentBackend(fileURL: root.appendingPathComponent("server")), store: TestSessionStore())
        let session = try await backend.signInForDevelopment()
        let transport = ProfileLoopbackTransport()
        let phone = PhoneProfileCoordinator(backend: backend, transport: transport, environment: .development)
        let watch = WatchNicknameRelay(transport: transport, environment: .development)
        watch.setAccount(CloudAccount(id: session.accountID, displayName: "이름"))
        let unavailable = try await watch.check("사용중닉네임")
        XCTAssertFalse(unavailable)
        let available = try await watch.check("워치별명")
        XCTAssertTrue(available)
        let updated = try await watch.update("워치별명")
        XCTAssertEqual(updated, "워치별명")
        try await phone.refresh(accountID: session.accountID)
        let current = try await backend.session()
        XCTAssertEqual(current?.nickname, "워치별명")
        for request in transport.requests {
            let text = String(decoding: request, as: UTF8.self)
            XCTAssertFalse(text.contains(session.accessToken))
            XCTAssertFalse(text.contains(session.refreshToken!))
        }
    }
    #endif
    func testWatchRelayRejectsWrongReplyIDAndWrongEnvironment() async throws {
        let transport = ProfileLoopbackTransport()
        let relay = WatchNicknameRelay(transport: transport, environment: .development)
        relay.setAccount(CloudAccount(id: "7", displayName: "테스트"))
        transport.onProfileRequest = { data in
            let request = try CloudWire.decodeProfileRequest(data, environment: .development)
            let wrong = NicknameRequest(accountID: request.accountID, action: request.action, nickname: request.nickname)
            return try CloudWire.encodeProfileReply(NicknameReply(request: wrong, result: .availability(true)), environment: .development)
        }
        do { _ = try await relay.check("새이름"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        transport.onProfileRequest = { data in
            let request = try CloudWire.decodeProfileRequest(data, environment: .development)
            return try CloudWire.encodeProfileReply(NicknameReply(request: request, result: .availability(true)), environment: .production)
        }
        do { _ = try await relay.check("새이름"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .environmentMismatch) }
    }
    func testWatchRelayDoesNotQueueMutationWhenPhoneUnreachable() async throws {
        let transport = ProfileLoopbackTransport()
        transport.connection.isReachable = false
        let relay = WatchNicknameRelay(transport: transport, environment: .development)
        relay.setAccount(CloudAccount(id: "7", displayName: "테스트"))
        do { _ = try await relay.update("새이름"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .watchUnavailable) }
        XCTAssertTrue(transport.queuedControls.isEmpty)
    }
    func testAccountChangeWhileWatchRequestInFlightRejectsOldReply() async throws {
        let gate = NicknameFlowGate()
        let transport = ProfileLoopbackTransport()
        let relay = WatchNicknameRelay(transport: transport, environment: .development)
        relay.setAccount(CloudAccount(id: "7", displayName: "테스트"))
        transport.onProfileRequest = { data in
            let request = try CloudWire.decodeProfileRequest(data, environment: .development)
            await gate.pause()
            return try CloudWire.encodeProfileReply(NicknameReply(request: request, result: .updated(request.nickname)), environment: .development)
        }
        let task = Task { try await relay.update("새이름") }
        await gate.waitForPause()
        relay.setAccount(nil)
        relay.setAccount(CloudAccount(id: "7", displayName: "새 세션"))
        await gate.release()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .sessionChanged) }
    }
}

@MainActor
private final class ProfileLoopbackTransport: CloudTransport {
    var connection = SnapshotConnection(isActivated: true, isPaired: true, isCounterpartInstalled: true, isReachable: true)
    var onCloudControl: ((Data) -> Void)?
    var onCloudFile: ((URL) -> Void)?
    var onCloudChallenge: (() async throws -> Data)?
    var onCloudTransferError: ((String?) -> Void)?
    var onProfileRequest: ((Data) async throws -> Data)?
    var requests: [Data] = []
    var queuedControls: [Data] = []
    func enqueueCloudControl(_ data: Data) throws { queuedControls.append(data) }
    func enqueueCloudFile(_ url: URL) throws {}
    func requestCloudChallenge() async throws -> Data { throw BackendError.watchUnavailable }
    func requestProfile(_ data: Data) async throws -> Data {
        guard connection.isReachable, let onProfileRequest else { throw BackendError.watchUnavailable }
        requests.append(data)
        return try await onProfileRequest(data)
    }
}

private actor NicknameFlowGate {
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        paused = true; waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForPause() async {
        if !paused { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() { continuation?.resume(); continuation = nil }
}
