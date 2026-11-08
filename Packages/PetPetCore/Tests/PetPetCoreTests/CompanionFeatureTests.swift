import XCTest
@testable import PetPetCore
import Foundation

final class CompanionFeatureTests: XCTestCase {
    @MainActor func testExpiredChatSessionNotifiesCompanionAccountUI() async throws {
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:RejectedChatHTTP(),store:TestSessionStore(session:featureSession()))
        let transport = FeatureLoopback()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        let notified = expectation(description:"Companion session was invalidated")
        phone.onSessionInvalidated = {
            let current = try? await backend.session()
            XCTAssertNil(current); notified.fulfill()
        }
        let watch = WatchFeatureClient(transport:transport,environment:.development)
        _ = try await watch.request(.startChat(UUID(),"질문"),accountID:"7")
        await fulfillment(of:[notified],timeout:2)
        phone.accountChanged()
    }
    @MainActor func testCompletedChatsDoNotBlockTheFifthQuestion() async throws {
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:ImmediateChatHTTP(),store:TestSessionStore(session:featureSession()))
        let transport = FeatureLoopback()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        defer { phone.accountChanged() }
        let watch = WatchFeatureClient(transport:transport,environment:.development)
        for _ in 0..<6 {
            let id = UUID()
            _ = try await watch.request(.startChat(id,"질문"),accountID:"7")
            var completed = false
            for _ in 0..<100 {
                if case let .chat(value) = try await watch.request(.pollChat(id),accountID:"7"), value.finished { completed = true; break }
                await Task.yield()
            }
            XCTAssertTrue(completed)
        }
    }
    @MainActor func testCancellationArrivingBeforeStartPreventsAnOrphanChat() async throws {
        let http = ImmediateChatHTTP()
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:http,store:TestSessionStore(session:featureSession()))
        let transport = FeatureLoopback()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        defer { phone.accountChanged() }
        let watch = WatchFeatureClient(transport:transport,environment:.development), id = UUID()
        _ = try await watch.request(.cancelChat(id),accountID:"7")
        do { _ = try await watch.request(.startChat(id,"취소된 질문"),accountID:"7"); XCTFail("Cancelled request was restarted") } catch { }
        let calls = await http.calls; XCTAssertEqual(calls,0)
    }
    @MainActor func testLateCancelledJobCannotFailAReplacementWithTheSameID() async throws {
        let oldGate = StreamEpochGate(), newGate = StreamEpochGate()
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:ReplacementChatHTTP(gates:[oldGate,newGate]),store:TestSessionStore(session:featureSession()))
        let transport = FeatureLoopback()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        let watch = WatchFeatureClient(transport:transport,environment:.development), id = UUID()
        _ = try await watch.request(.startChat(id,"이전 질문"),accountID:"7")
        while !(await oldGate.blocked) { await Task.yield() }
        phone.accountChanged()
        _ = try await watch.request(.startChat(id,"새 질문"),accountID:"7")
        while !(await newGate.blocked) { await Task.yield() }
        await oldGate.release()
        for _ in 0..<20 { await Task.yield() }
        if case let .chat(value) = try await watch.request(.pollChat(id),accountID:"7") {
            XCTAssertEqual(value.text,"새 질문"); XCTAssertFalse(value.finished); XCTAssertFalse(value.failed)
        } else { XCTFail() }
        phone.accountChanged(); await newGate.release()
    }
    func testRankingRequestsMatchBothAndroidPathsAndPayloads() async throws {
        let http = RankContractHTTP()
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:http,store:TestSessionStore(session:featureSession()))
        for game in MiniGame.allCases {
            let ranking = try await backend.ranking(game,submitting:GameScore(game:game,score:42,maxCombo:12),accountID:"7")
            XCTAssertEqual(ranking.position,2); XCTAssertEqual(ranking.entries.first?.score,99)
        }
        let paths = await http.paths
        XCTAssertEqual(paths,["/api/v1/shooting-game/rank/score","/api/v1/shooting-game/rank/position","/api/v1/shooting-game/rank/top10","/api/v1/star-stair-game/rank/score","/api/v1/star-stair-game/rank/position","/api/v1/star-stair-game/rank/top10"])
    }
    func testChatRefreshesRejectedTokenBeforeEmittingTokens() async throws {
        let http = StreamAuthHTTP()
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:http,store:TestSessionStore(session:featureSession()))
        let collector = ChatCollector()
        try await backend.streamChat(question:"질문",accountID:"7") { try await collector.receive($0) }
        let tokens = await http.bearers
        XCTAssertEqual(tokens,["Bearer access","Bearer renewed"])
        let result = await collector.state; XCTAssertEqual(result.text,"새 답변"); XCTAssertTrue(result.finished)
    }
    func testLogoutDiscardsLateStreamingTokens() async throws {
        let gate = StreamEpochGate()
        let http = StreamEpochHTTP(gate:gate)
        let backend = try BackendClient(baseURL:URL(string:"https://api.example.test/")!,transport:http,store:TestSessionStore(session:featureSession()))
        let collector = ChatCollector()
        let task = Task { try await backend.streamChat(question:"질문",accountID:"7") { try await collector.receive($0) } }
        while !(await gate.blocked) { await Task.yield() }
        try await backend.signOut(); await gate.release()
        do { try await task.value; XCTFail() } catch { XCTAssertEqual(error as? BackendError,.sessionChanged) }
        let result = await collector.state; XCTAssertEqual(result.text,"첫 응답")
    }
    @MainActor func testWatchRejectsReplyForDifferentRequest() async throws {
        let transport = FeatureLoopback()
        transport.onFeatureRequest = { data in
            let original = try JSONDecoder().decode(CompanionFeatureRequest.self,from:data)
            let wrong = CompanionFeatureRequest(accountID:original.accountID,environment:.development,action:original.action)
            return try JSONEncoder().encode(CompanionFeatureReply(request:wrong,result:.accepted))
        }
        let client = WatchFeatureClient(transport:transport,environment:.development)
        do { _ = try await client.request(.ranking(.shooting),accountID:"7"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError,.sessionChanged) }
    }
    func testSSECommentsJSONTokensMultilineAndTrailingRecord() throws {
        var parser = ChatSSEParser()
        XCTAssertNil(try parser.line(": keep-alive")); XCTAssertNil(try parser.line("event: token"))
        XCTAssertNil(try parser.line(#"data: {"token":"안녕 🦊"}"#))
        XCTAssertEqual(try parser.line("")?.displayText,"안녕 🦊")
        _ = try parser.line("data: 첫 줄"); _ = try parser.line("data: 둘째 줄")
        XCTAssertEqual(parser.finish(),ChatStreamEvent(name:"message",data:"첫 줄\n둘째 줄"))
        XCTAssertNil(parser.finish())
    }
    func testSSEBoundsAndQuestionValidation() throws {
        var parser = ChatSSEParser()
        XCTAssertThrowsError(try parser.line("data: "+String(repeating:"x",count:32001)))
        XCTAssertThrowsError(try ChatProgress.validate(question:"  \n"))
        XCTAssertThrowsError(try ChatProgress.validate(question:String(repeating:"가",count:2001)))
        XCTAssertNoThrow(try ChatProgress.validate(question:"오늘 산책할까?"))
    }
    func testChatStatusAndTerminalEvents() throws {
        var state = ChatProgress()
        try state.receive(ChatStreamEvent(name:"metadata",data:"{}")); XCTAssertFalse(state.finished)
        try state.receive(ChatStreamEvent(name:"token",data:#"{"content":"답변"}"#))
        XCTAssertEqual(state.text,"답변")
        try state.receive(ChatStreamEvent(name:"done",data:"{}")); XCTAssertTrue(state.finished)
        try state.receive(ChatStreamEvent(name:"token",data:"무시")); XCTAssertEqual(state.text,"답변")
        var failed = ChatProgress(); try failed.receive(ChatStreamEvent(name:"error",data:#"{"message":"응답 오류"}"#))
        XCTAssertTrue(failed.failed); XCTAssertEqual(failed.text,"응답 오류")
    }
    #if DEBUG
    func testMockRanksUseAndroidContractsAndPersistBestWithCurrentNickname() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let store = TestSessionStore()
        let backend = try BackendClient(baseURL:LocalDevelopmentBackend.baseURL,transport:LocalDevelopmentBackend(fileURL:file),store:store)
        let account = try await backend.signInForDevelopment()
        _ = try await backend.updateNickname("게임여우",accountID:account.accountID)
        for game in MiniGame.allCases {
            let ranking = try await backend.ranking(game,submitting:GameScore(game:game,score:50,maxCombo:20),accountID:account.accountID)
            XCTAssertEqual(ranking.position,1); XCTAssertEqual(ranking.entries.first?.name,"게임여우"); XCTAssertEqual(ranking.entries.first?.score,50)
            _ = try await backend.ranking(game,submitting:GameScore(game:game,score:1,maxCombo:1),accountID:account.accountID)
            let recreated = try BackendClient(baseURL:LocalDevelopmentBackend.baseURL,transport:LocalDevelopmentBackend(fileURL:file),store:store)
            let persisted = try await recreated.ranking(game,accountID:account.accountID)
            XCTAssertEqual(persisted.entries.first?.score,50)
        }
    }
    func testMockChatStreamsAndNeverFallsBackToProduction() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let backend = try BackendClient(baseURL:LocalDevelopmentBackend.baseURL,transport:LocalDevelopmentBackend(fileURL:file),store:TestSessionStore())
        let session = try await backend.signInForDevelopment()
        let collector = ChatCollector()
        try await backend.streamChat(question:"산책하자",accountID:session.accountID) { try await collector.receive($0) }
        let result = await collector.state
        XCTAssertTrue(result.finished); XCTAssertTrue(result.text.contains("개발용 모의 응답")); XCTAssertTrue(result.text.contains("산책하자"))
        do { try await backend.streamChat(question:"질문",accountID:"other") { _ in XCTFail() }; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError,.authenticationRequired) }
    }
    @MainActor func testWatchRelayValidatesEnvironmentAndAccountAndRoundTripsChat() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let backend = try BackendClient(baseURL:LocalDevelopmentBackend.baseURL,transport:LocalDevelopmentBackend(fileURL:file),store:TestSessionStore())
        let account = try await backend.signInForDevelopment()
        let transport = FeatureLoopback()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        let watch = WatchFeatureClient(transport:transport,environment:.development)
        guard case let .ranking(ranking) = try await watch.request(.submit(GameScore(game:.shooting,score:42)),accountID:account.accountID) else { return XCTFail() }
        XCTAssertEqual(ranking.position,1)
        let id = UUID()
        _ = try await watch.request(.startChat(id,"테스트"),accountID:account.accountID)
        var done = false
        for _ in 0..<100 {
            if case let .chat(value) = try await watch.request(.pollChat(id),accountID:account.accountID), value.finished { XCTAssertTrue(value.text.contains("테스트")); done = true; break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertTrue(done)
        let otherEnvironment = WatchFeatureClient(transport:transport,environment:.production)
        do { _ = try await otherEnvironment.request(.ranking(.shooting),accountID:account.accountID); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError,.environmentMismatch) }
        do { _ = try await watch.request(.pollChat(id),accountID:"other"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError,.authenticationRequired) }
        phone.accountChanged()
    }
    @MainActor func testCancelledChatCannotKeepProducingText() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let backend = try BackendClient(baseURL:LocalDevelopmentBackend.baseURL,transport:LocalDevelopmentBackend(fileURL:file),store:TestSessionStore())
        let account = try await backend.signInForDevelopment()
        let transport = FeatureLoopback(), id = UUID()
        let phone = PhoneFeatureCoordinator(backend:backend,transport:transport,environment:.development)
        let watch = WatchFeatureClient(transport:transport,environment:.development)
        _ = try await watch.request(.startChat(id,"취소"),accountID:account.accountID)
        _ = try await watch.request(.cancelChat(id),accountID:account.accountID)
        do { _ = try await watch.request(.pollChat(id),accountID:account.accountID); XCTFail() } catch {}
        phone.accountChanged()
    }
    #endif
}
private struct RejectedChatHTTP: BackendHTTPTransport, BackendChatTransport {
    func send(_ request:URLRequest) async throws -> BackendHTTPResponse { BackendHTTPResponse(statusCode:401) }
    func stream(_ request:URLRequest,onEvent:@escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws { throw BackendError.http(401) }
}
private actor ImmediateChatHTTP: BackendHTTPTransport, BackendChatTransport {
    var calls = 0
    func send(_ request:URLRequest) async throws -> BackendHTTPResponse { throw BackendError.network }
    func stream(_ request:URLRequest,onEvent:@escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        calls += 1
        try await onEvent(ChatStreamEvent(name:"token",data:"답변"))
        try await onEvent(ChatStreamEvent(name:"done",data:"{}"))
    }
}
private actor ReplacementChatHTTP: BackendHTTPTransport, BackendChatTransport {
    let gates: [StreamEpochGate]
    var calls = 0
    init(gates:[StreamEpochGate]) { self.gates = gates }
    func send(_ request:URLRequest) async throws -> BackendHTTPResponse { throw BackendError.network }
    func stream(_ request:URLRequest,onEvent:@escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        let index = calls; calls += 1
        let body = try JSONDecoder().decode([String:String].self,from:request.httpBody!)
        try await onEvent(ChatStreamEvent(name:"token",data:body["question"]!))
        await gates[index].wait()
        try await onEvent(ChatStreamEvent(name:"done",data:"{}"))
    }
}
private func featureSession() -> BackendSession {
    BackendSession(accountID:"7",serverOrigin:"https://api.example.test/",accessToken:"access",refreshToken:"refresh",email:nil,name:nil,nickname:"여우")
}
private actor RankContractHTTP: BackendHTTPTransport {
    var paths: [String] = []
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        let path = request.url!.path; paths.append(path)
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer access")
        let stair = path.contains("star-stair")
        if request.httpMethod == "POST" {
            let body = try JSONDecoder().decode([String:Int].self,from:request.httpBody!)
            XCTAssertEqual(body,stair ? ["maxStep":42,"maxCombo":12] : ["score":42])
        }
        let body: [String:Any]
        if path.hasSuffix("top10") { body = ["ranks":[["rank":1,"userId":8,"userName":"친구",stair ? "maxStep" : "score":99,"maxCombo":10]]] }
        else { body = ["userId":7,"rank":2] }
        return BackendHTTPResponse(statusCode:200,data:try JSONSerialization.data(withJSONObject:body))
    }
}
private actor StreamAuthHTTP: BackendHTTPTransport, BackendChatTransport {
    var bearers: [String] = []
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        XCTAssertEqual(request.url?.path,"/api/v1/auth/refresh")
        return BackendHTTPResponse(statusCode:200,data:Data(#"{"userId":7,"accessToken":"renewed","refreshToken":"next"}"#.utf8))
    }
    func stream(_ request: URLRequest,onEvent:@escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        bearers.append(request.value(forHTTPHeaderField:"Authorization") ?? "")
        XCTAssertEqual(request.url?.path,"/api/v1/ai/chat/stream")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Accept"),"text/event-stream")
        XCTAssertEqual(try JSONDecoder().decode([String:String].self,from:request.httpBody!),["question":"질문"])
        if bearers.count == 1 { throw BackendError.http(401) }
        try await onEvent(ChatStreamEvent(name:"token",data:"새 답변")); try await onEvent(ChatStreamEvent(name:"done",data:"{}"))
    }
}
private actor StreamEpochGate {
    var blocked = false
    private var continuation: CheckedContinuation<Void,Never>?
    func wait() async { await withCheckedContinuation { blocked = true; continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private struct StreamEpochHTTP: BackendHTTPTransport, BackendChatTransport {
    let gate: StreamEpochGate
    func send(_ request: URLRequest) async throws -> BackendHTTPResponse { throw BackendError.network }
    func stream(_ request: URLRequest,onEvent:@escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        try await onEvent(ChatStreamEvent(name:"token",data:"첫 응답")); await gate.wait()
        try await onEvent(ChatStreamEvent(name:"token",data:"버려야 하는 응답"))
    }
}
private actor ChatCollector {
    var state = ChatProgress()
    func receive(_ value: ChatStreamEvent) throws { try state.receive(value) }
}
@MainActor private final class FeatureLoopback: CompanionFeatureTransport {
    var onFeatureRequest: ((Data) async throws -> Data)?
    func requestFeature(_ data: Data) async throws -> Data {
        guard let onFeatureRequest else { throw BackendError.watchUnavailable }
        return try await onFeatureRequest(data)
    }
}
