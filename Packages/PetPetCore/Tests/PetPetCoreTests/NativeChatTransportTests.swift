import Foundation
import XCTest
@testable import PetPetCore

final class NativeChatTransportTests: XCTestCase {
    func testByteFramerHandlesBOMLoneCRAndFinalRecordWithoutNewline() throws {
        var parser = ChatSSEByteParser(), events: [ChatStreamEvent] = []
        for byte in "\u{feff}event: token\rdata: 한글\r\revent: done\rdata: {}".utf8 {
            if let event = try parser.byte(byte) { events.append(event) }
        }
        if let event = try parser.finish() { events.append(event) }
        XCTAssertEqual(events.map(\.name),["token","done"]); XCTAssertEqual(events.first?.data,"한글")
    }
    func testByteFramerRejectsMalformedUTF8AndOversizedUnterminatedLines() throws {
        var parser = ChatSSEByteParser()
        _ = try parser.byte(0xff)
        XCTAssertThrowsError(try parser.byte(10))
        var oversized = ChatSSEByteParser()
        for _ in 0..<32_000 { _ = try oversized.byte(65) }
        XCTAssertThrowsError(try oversized.byte(65))
    }
    func testNativeURLSessionPreservesSSEBoundariesAndSplitUnicode() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedChatProtocol.self]
        let session = URLSession(configuration:configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionBackendTransport(session:session)
        let collector = NativeEventCollector()
        try await transport.stream(URLRequest(url:URL(string:"https://stream.example.test/events")!)) { await collector.receive($0) }
        let events = await collector.events
        XCTAssertEqual(events.map(\.name),["metadata","token","token","done"])
        XCTAssertEqual(events.filter { $0.name == "token" }.map(\.displayText).joined(),"안녕 🦊")
    }
    func testNativeTransportRejectsNonSSEEvenWithSuccessfulHTTPStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedChatProtocol.self]
        let session = URLSession(configuration:configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionBackendTransport(session:session)
        do {
            try await transport.stream(URLRequest(url:URL(string:"https://stream.example.test/wrong-type")!)) { _ in XCTFail() }
            XCTFail()
        } catch { XCTAssertEqual(error as? BackendError,.invalidResponse) }
    }
}
private actor NativeEventCollector {
    var events: [ChatStreamEvent] = []
    func receive(_ event:ChatStreamEvent) { events.append(event) }
}
private final class ChunkedChatProtocol: URLProtocol {
    override class func canInit(with request:URLRequest) -> Bool { request.url?.host == "stream.example.test" }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        let type = request.url!.path == "/wrong-type" ? "application/json" : "text/event-stream; charset=utf-8"
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":type])!,cacheStoragePolicy:.notAllowed)
        let body = ": ping\r\nevent: metadata\r\ndata: {}\r\n\r\nevent: token\r\ndata: {\"token\":\"안녕\"}\r\n\r\nevent: token\ndata: {\"content\":\" 🦊\"}\n\nevent: done\ndata: {}\n\n"
        // One-byte chunks deliberately split UTF-8 scalars and CRLF pairs.
        for byte in body.utf8 { client?.urlProtocol(self,didLoad:Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
