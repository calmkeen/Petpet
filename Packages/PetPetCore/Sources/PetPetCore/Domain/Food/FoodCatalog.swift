import Foundation

/// StepMate FoodTypeEnum, including its stable food/statistic identifiers.
public enum FoodCatalog {
    public static let all: [FoodDefinition] = [
        FoodDefinition(id: 1, name: "우유", description: "경험치 +1", improvement: 1,
                       statistic: .experience, imageName: "milk_normal1"),
        FoodDefinition(id: 2, name: "사과", description: "경험치 +3", improvement: 3,
                       statistic: .experience, imageName: "apple_normal1"),
        FoodDefinition(id: 3, name: "고기", description: "경험치 +5", improvement: 5,
                       statistic: .experience, imageName: "meat_normal1")
    ]

    public static func food(id: Int64) -> FoodDefinition? {
        all.first { $0.id == id }
    }
}
