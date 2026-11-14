import Foundation

public enum StairDirection: String, Codable, Sendable { case left, right
    public var opposite: Self { self == .left ? .right : .left }
    public var delta: Int { self == .left ? -1 : 1 }
}
public enum MiniGameStatus: String, Codable, Sendable { case ready, playing, finished }
/// One transient feedback event per accepted input or expired round.
/// Keeping this separate from status text also covers the final lost life.
public enum StarStairFeedback: Equatable, Sendable {
    case correct(StairDirection), wrong, timeout
}
public struct StarStair: Equatable, Sendable, Identifiable {
    public let id: Int
    public let lane: Int
    public let direction: StairDirection?
}
public struct StarStairGame: Sendable {
    public private(set) var status: MiniGameStatus = .ready
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var life = 3
    public private(set) var stairs: [StarStair] = []
    public private(set) var remaining = 1.5
    public private(set) var feedback = ""
    public var nextDirection: StairDirection { stairs.first { $0.id == score + 1 }?.direction ?? .right }
    public var currentLane: Int { stairs.first { $0.id == score }?.lane ?? 0 }
    public var timeLimit: Double { Self.timeLimit(score: score) }
    private var random: GameRandom
    private var lastDirection: StairDirection?
    private var sameCount = 0

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { random = GameRandom(seed: seed) }
    public static func timeLimit(score: Int) -> Double {
        switch score { case ..<20: 1.5; case ..<50: 1.2; case ..<100: 1; case ..<200: 0.8; default: 0.65 }
    }
    public mutating func start() {
        status = .playing; score = 0; combo = 0; maxCombo = 0; life = 3
        stairs = [StarStair(id: 0, lane: 0, direction: nil)]
        remaining = 1.5; feedback = ""; lastDirection = nil; sameCount = 0; fill()
    }
    @discardableResult
    public mutating func input(_ direction: StairDirection) -> StarStairFeedback? {
        guard status == .playing else { return nil }
        guard direction == nextDirection else { fail("방향을 확인해 주세요"); return .wrong }
        let oldLimit = timeLimit
        score += 1; combo += 1; maxCombo = max(maxCombo, combo)
        remaining = timeLimit; feedback = timeLimit < oldLimit ? "SPEED UP!" : "좋아요!"
        fill()
        return .correct(direction)
    }
    @discardableResult
    public mutating func advance(seconds: Double) -> StarStairFeedback? {
        guard status == .playing, seconds.isFinite, seconds > 0 else { return nil }
        remaining = max(0, remaining - seconds)
        if remaining <= 0 { fail("시간 초과"); return .timeout }
        return nil
    }
    public mutating func finish() { status = .finished; life = 0; remaining = 0 }
    private mutating func fail(_ text: String) {
        life = max(0, life - 1); combo = 0; feedback = text
        if life == 0 { finish() } else { remaining = timeLimit }
    }
    private mutating func fill() {
        stairs.removeAll { $0.id < score - 4 }
        while let last = stairs.last, last.id < score + 4 {
            let direction: StairDirection = sameCount >= 4 ? (lastDirection?.opposite ?? .right) : (random.unit() < 0.5 ? .left : .right)
            sameCount = direction == lastDirection ? sameCount + 1 : 1
            lastDirection = direction
            stairs.append(StarStair(id: last.id + 1, lane: last.lane + direction.delta, direction: direction))
        }
    }
}
