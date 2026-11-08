import Foundation

public struct ChatStreamEvent: Equatable, Sendable {
    public let name: String
    public let data: String
    public init(name: String, data: String) { self.name = name; self.data = data }
    public var displayText: String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { return data }
        for key in ["token", "content", "message"] { if let text = object[key] as? String, !text.isEmpty { return text } }
        return data
    }
}
/// Parses SSE records, including comments, multi-line data and the final record without a blank line.
public struct ChatSSEParser: Sendable {
    private var name = "message"
    private var lines: [String] = []
    private var bytes = 0
    public init() {}
    public mutating func line(_ line: String) throws -> ChatStreamEvent? {
        guard line.utf8.count <= 32_000 else { throw BackendError.transferTooLarge }
        if line.isEmpty { return finish() }
        if line.hasPrefix("event:") { name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        else if line.hasPrefix("data:") {
            var text = String(line.dropFirst(5)); if text.hasPrefix(" ") { text.removeFirst() }
            bytes += text.utf8.count
            guard bytes <= 32_000 else { throw BackendError.transferTooLarge }
            lines.append(text)
        }
        return nil
    }
    public mutating func finish() -> ChatStreamEvent? {
        defer { name = "message"; lines = []; bytes = 0 }
        return lines.isEmpty ? nil : ChatStreamEvent(name: name, data: lines.joined(separator: "\n"))
    }
}

/// AsyncBytes.lines omits empty lines, which are meaningful SSE event separators.
/// Frame bytes directly so CRLF, LF, CR and split UTF-8 scalars are preserved.
public struct ChatSSEByteParser: Sendable {
    private var line = Data()
    private var parser = ChatSSEParser()
    private var followsCR = false
    private var firstLine = true
    public init() {}
    public mutating func byte(_ value: UInt8) throws -> ChatStreamEvent? {
        if value == 13 { followsCR = true; return try finishLine() }
        if value == 10 {
            if followsCR { followsCR = false; return nil }
            return try finishLine()
        }
        followsCR = false
        guard line.count < 32_000 else { throw BackendError.transferTooLarge }
        line.append(value)
        return nil
    }
    public mutating func finish() throws -> ChatStreamEvent? {
        if !line.isEmpty { _ = try finishLine() }
        return parser.finish()
    }
    private mutating func finishLine() throws -> ChatStreamEvent? {
        guard var text = String(data:line,encoding:.utf8) else { throw BackendError.invalidResponse }
        line.removeAll(keepingCapacity:true)
        if firstLine {
            firstLine = false
            if text.hasPrefix("\u{feff}") { text.removeFirst() }
        }
        return try parser.line(text)
    }
}
public struct ChatProgress: Codable, Equatable, Sendable {
    public var text = ""
    public var status = "AI 응답을 기다리고 있어요"
    public var finished = false
    public var failed = false
    public init() {}
    public mutating func receive(_ event: ChatStreamEvent) throws {
        guard !finished else { return }
        switch event.name {
        case "done": finished = true; status = "AI 응답 완료"
        case "error": failed = true; finished = true; status = "AI 응답 오류"; text = event.displayText
        case "metadata": status = "AI 응답 준비 중"
        case "context": status = "관련 정보를 확인하고 있어요"
        case "token": text += event.displayText
        default: text += (text.isEmpty ? "" : "\n") + event.displayText
        }
        guard text.utf8.count <= 24_000 else { throw BackendError.transferTooLarge }
    }
    public mutating func end() { if !finished { finished = true; status = "AI 응답 스트림 종료" } }
    public mutating func fail(_ message: String) { finished = true; failed = true; status = message }
    public static func validate(question: String) throws {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.count <= 2000, question.utf8.count <= 8_000 else { throw BackendError.invalidResponse }
    }
}
