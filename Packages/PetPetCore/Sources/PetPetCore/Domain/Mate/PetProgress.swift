import Foundation

public enum TrainableStatistic: String, CaseIterable, Sendable {
    case attack, defense, health
}

public enum PetProgressError: Error, Equatable {
    case unknownFood, noFood, noStatPoints, invalidRecord, outdatedDay, numericOverflow
    case unsupportedVersion(Int)
}

public struct StepRewardClaim: Codable, Equatable, Sendable {
    public internal(set) var milkUnits: Int64
    public internal(set) var appleClaimed: Bool
}

public struct StepRewardGrant: Equatable, Sendable {
    public let milk: Int64
    public let apple: Int64
    public var isEmpty: Bool { milk == 0 && apple == 0 }
}

/// Pet, food consumption and reward cursors form one persistence transaction.
public struct PetProgress: Codable, Equatable, Sendable {
    public internal(set) var pet: PetProfile
    public internal(set) var inventory: [FoodInventoryItem]
    public internal(set) var rewardClaims: [String: StepRewardClaim]
    public internal(set) var touchCount: Int
    public internal(set) var lastActiveAt: Date?

    public static func newUser(at date: Date) -> PetProgress {
        PetProgress(
            pet: PetProfile(id: 1, level: 1, experience: 0, affection: 0, attack: 50,
                            defense: 0, health: 8, mood: .happy, lastFedAt: date, statPoints: 0),
            // Android's release new-user grant; debug-only apple seeds are excluded.
            inventory: [FoodInventoryItem(id: 1, foodID: 1, quantity: 3)],
            rewardClaims: [:], touchCount: 0, lastActiveAt: nil
        )
    }

    public func quantity(of foodID: Int64) -> Int64 {
        inventory.first { $0.foodID == foodID }?.quantity ?? 0
    }

    public var experienceRequired: Int64 { pet.level * 2 }

    public func pendingRewards(for record: DailyStepRecord) -> StepRewardGrant {
        let claim = rewardClaims[record.date]
        return StepRewardGrant(
            milk: max(0, Int64(max(0, record.stepCount) / 1_000) - (claim?.milkUnits ?? 0)),
            apple: claim?.appleClaimed == true ? 0 : 1
        )
    }
}

public enum PetProgressAction: Sendable {
    case feed(foodID: Int64)
    case allocate(TrainableStatistic)
    case touch
    case visit
    case refreshMood
    /// Call only after the day's step record has been saved successfully.
    case claimRewards(DailyStepRecord)
}

public struct PetProgressChange: Sendable {
    public let progress: PetProgress
    public let reward: StepRewardGrant?
}

public protocol PetProgressRepository: Sendable {
    func load() async throws -> PetProgress
    func perform(_ action: PetProgressAction) async throws -> PetProgressChange
}
