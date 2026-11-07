import Foundation

/// Numeric values match StepMate's StatType identifiers.
public enum PetStatistic: Int64, Codable, Sendable {
    case attack = 1
    case defense = 2
    case health = 3
    case experience = 4
    case affection = 5
    case statPoints = 6
}

public struct FoodDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var description: String
    public var improvement: Int64
    public var statistic: PetStatistic
    public var imageName: String

    public init(
        id: Int64, name: String, description: String, improvement: Int64,
        statistic: PetStatistic, imageName: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.improvement = improvement
        self.statistic = statistic
        self.imageName = imageName
    }
}

public struct FoodInventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var foodID: Int64
    public var quantity: Int64

    public init(id: Int64, foodID: Int64, quantity: Int64) {
        self.id = id
        self.foodID = foodID
        self.quantity = quantity
    }
}
