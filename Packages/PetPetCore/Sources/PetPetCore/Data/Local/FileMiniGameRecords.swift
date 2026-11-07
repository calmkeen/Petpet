import Foundation

public actor FileMiniGameRecords {
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func best(_ game: MiniGame) throws -> GameScore {
        try load()[game.rawValue] ?? GameScore(game: game, score: 0)
    }
    @discardableResult public func record(_ score: GameScore) throws -> GameScore {
        try score.validate()
        var values = try load()
        let old = values[score.game.rawValue]
        let best = GameScore(game: score.game, score: max(old?.score ?? 0, score.score), maxCombo: max(old?.maxCombo ?? 0, score.maxCombo))
        values[score.game.rawValue] = best
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: fileURL, options: .atomic)
        } catch { throw BackendError.storage }
        return best
    }
    private func load() throws -> [String: GameScore] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let result = try JSONDecoder().decode([String: GameScore].self, from: Data(contentsOf: fileURL))
            for (key, value) in result { guard key == value.game.rawValue else { throw BackendError.storage }; try value.validate() }
            return result
        } catch { throw BackendError.storage }
    }
}
