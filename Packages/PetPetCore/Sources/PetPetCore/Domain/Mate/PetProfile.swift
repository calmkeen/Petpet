import Foundation

public enum PetMood: String, Codable, Sendable {
    case happy = "HAPPY"
    case sad = "SAD"
    case hungry = "HUNGRY"
}

/// Shared pet state, based on Android's UserMateEntity.
/// Remote DTOs and platform persistence entities map to this type separately.
public struct PetProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var level: Int64
    public var experience: Int64
    public var affection: Int64
    public var attack: Int64
    public var defense: Int64
    public var health: Int64
    public var mood: PetMood
    public var lastFedAt: Date?
    public var statPoints: Int64

    public init(
        id: Int64, level: Int64, experience: Int64, affection: Int64,
        attack: Int64, defense: Int64, health: Int64, mood: PetMood,
        lastFedAt: Date?, statPoints: Int64
    ) {
        self.id = id
        self.level = level
        self.experience = experience
        self.affection = affection
        self.attack = attack
        self.defense = defense
        self.health = health
        self.mood = mood
        self.lastFedAt = lastFedAt
        self.statPoints = statPoints
    }
}
