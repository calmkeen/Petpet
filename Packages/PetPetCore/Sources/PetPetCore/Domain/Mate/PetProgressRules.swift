import Foundation

enum PetProgressRules {
    static func apply(
        _ action: PetProgressAction, to progress: inout PetProgress,
        at now: Date, calendar: Calendar
    ) throws -> StepRewardGrant? {
        switch action {
        case let .feed(foodID):
            guard let food = FoodCatalog.food(id: foodID) else { throw PetProgressError.unknownFood }
            guard let index = progress.inventory.firstIndex(where: { $0.foodID == foodID }),
                  progress.inventory[index].quantity > 0 else { throw PetProgressError.noFood }
            progress.inventory[index].quantity -= 1
            if progress.inventory[index].quantity == 0 { progress.inventory.remove(at: index) }
            try gainExperience(food.improvement, pet: &progress.pet)
            progress.pet.mood = .happy
            progress.pet.lastFedAt = now
        case let .allocate(statistic):
            guard progress.pet.statPoints > 0 else { throw PetProgressError.noStatPoints }
            progress.pet.statPoints -= 1
            switch statistic {
            case .attack: progress.pet.attack = try adding(progress.pet.attack, 1)
            case .defense: progress.pet.defense = try adding(progress.pet.defense, 1)
            case .health: progress.pet.health = try adding(progress.pet.health, 1)
            }
        case .touch:
            progress.touchCount += 1
            if progress.touchCount == 50 {
                progress.touchCount = 0
                progress.pet.affection = try adding(progress.pet.affection, 1)
            }
        case .visit:
            if let lastActive = progress.lastActiveAt, now.timeIntervalSince(lastActive) >= 86_400 {
                progress.pet.mood = .sad
            }
            refreshHunger(&progress.pet, at: now)
            progress.lastActiveAt = now
        case .refreshMood:
            refreshHunger(&progress.pet, at: now)
        case let .claimRewards(record):
            guard record.date == StepDay(containing: now, calendar: calendar).date else {
                throw PetProgressError.outdatedDay
            }
            guard record.stepCount >= 0 else { throw PetProgressError.invalidRecord }
            let grant = progress.pendingRewards(for: record)
            try addFood(id: 1, quantity: grant.milk, to: &progress)
            try addFood(id: 2, quantity: grant.apple, to: &progress)
            let units = Int64(record.stepCount / 1_000)
            progress.rewardClaims[record.date] = StepRewardClaim(
                milkUnits: max(units, progress.rewardClaims[record.date]?.milkUnits ?? 0),
                appleClaimed: true
            )
            return grant
        }
        return nil
    }

    private static func gainExperience(_ amount: Int64, pet: inout PetProfile) throws {
        pet.experience = try adding(pet.experience, amount)
        while pet.experience >= pet.level * 2 {
            pet.experience -= pet.level * 2
            pet.level = try adding(pet.level, 1)
            guard pet.level <= Int64.max / 2 else { throw PetProgressError.numericOverflow }
            pet.statPoints = try adding(pet.statPoints, 2)
        }
    }

    private static func addFood(id: Int64, quantity: Int64, to progress: inout PetProgress) throws {
        guard quantity > 0 else { return }
        if let index = progress.inventory.firstIndex(where: { $0.foodID == id }) {
            progress.inventory[index].quantity = try adding(progress.inventory[index].quantity, quantity)
        } else {
            progress.inventory.append(FoodInventoryItem(id: id, foodID: id, quantity: quantity))
            progress.inventory.sort { $0.foodID < $1.foodID }
        }
    }

    private static func refreshHunger(_ pet: inout PetProfile, at now: Date) {
        if let lastFed = pet.lastFedAt, now.timeIntervalSince(lastFed) >= 86_400 {
            pet.mood = .hungry
        }
    }

    private static func adding(_ value: Int64, _ amount: Int64) throws -> Int64 {
        let (result, overflow) = value.addingReportingOverflow(amount)
        guard !overflow else { throw PetProgressError.numericOverflow }
        return result
    }
}
