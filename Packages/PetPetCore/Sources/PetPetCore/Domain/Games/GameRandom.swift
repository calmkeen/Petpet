import Foundation

/// Seeded randomness makes the game rules reproducible without a renderer.
public struct GameRandom: Sendable {
    private var state: UInt64
    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed }
    public mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992
    }
}
