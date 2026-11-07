import Foundation

public enum MiniGame: String, Codable, CaseIterable, Sendable {
    case shooting, starStair
    public var title: String { self == .shooting ? "지구를 지켜라" : "별계단 훈련" }
    public var serverPath: String { self == .shooting ? "shooting-game" : "star-stair-game" }
}
public struct GameScore: Codable, Equatable, Sendable {
    public let game: MiniGame
    public let score: Int
    public let maxCombo: Int
    public init(game: MiniGame, score: Int, maxCombo: Int = 0) { self.game = game; self.score = score; self.maxCombo = maxCombo }
    public func validate() throws {
        guard score >= 0, maxCombo >= 0, score <= 1_000_000_000, maxCombo <= score || game == .shooting else { throw BackendError.invalidResponse }
    }
    public var requestBody: [String: Int] { game == .shooting ? ["score": score] : ["maxStep": score, "maxCombo": maxCombo] }
}
public struct GameRankEntry: Codable, Equatable, Sendable {
    public let rank: Int
    public let userID: Int64?
    public let name: String
    public let score: Int
    public let maxCombo: Int
    public init(rank: Int, userID: Int64?, name: String, score: Int, maxCombo: Int = 0) {
        self.rank = rank; self.userID = userID; self.name = name; self.score = score; self.maxCombo = maxCombo
    }
}
public struct GameRanking: Codable, Equatable, Sendable {
    public let game: MiniGame
    public let position: Int?
    public let entries: [GameRankEntry]
    public init(game: MiniGame, position: Int? = nil, entries: [GameRankEntry]) { self.game = game; self.position = position; self.entries = entries }
}
