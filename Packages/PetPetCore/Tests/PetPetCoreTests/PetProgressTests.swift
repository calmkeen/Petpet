import XCTest
@testable import PetPetCore

final class PetProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_052_800) // 2026-11-07 UTC
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testReleaseStarterAndCatalogMatchAndroid() {
        let value = PetProgress.newUser(at: now)
        XCTAssertEqual(value.pet.level, 1)
        XCTAssertEqual(value.pet.attack, 50)
        XCTAssertEqual(value.pet.defense, 0)
        XCTAssertEqual(value.pet.health, 8)
        XCTAssertEqual(value.quantity(of: 1), 3)
        XCTAssertEqual(value.quantity(of: 2), 0)
        XCTAssertEqual(FoodCatalog.all.map(\.improvement), [1, 3, 5])
    }

    func testFeedingCarriesExperienceAndAwardsTwoPointsPerLevel() throws {
        var value = PetProgress.newUser(at: now)
        value.inventory = [FoodInventoryItem(id: 3, foodID: 3, quantity: 2)]
        try apply(.feed(foodID: 3), to: &value)
        XCTAssertEqual(value.pet.level, 2)
        XCTAssertEqual(value.pet.experience, 3) // 5 - 2
        XCTAssertEqual(value.pet.statPoints, 2)
        try apply(.feed(foodID: 3), to: &value)
        XCTAssertEqual(value.pet.level, 3)
        XCTAssertEqual(value.pet.experience, 4) // 3 + 5 - 4
        XCTAssertEqual(value.pet.statPoints, 4)
        XCTAssertTrue(value.inventory.isEmpty)
        XCTAssertThrowsError(try apply(.feed(foodID: 3), to: &value)) {
            XCTAssertEqual($0 as? PetProgressError, .noFood)
        }
    }

    func testExactThresholdAndMultipleLevelUps() throws {
        var value = PetProgress.newUser(at: now)
        value.pet.experience = 1
        value.inventory = [FoodInventoryItem(id: 3, foodID: 3, quantity: 1)]
        try apply(.feed(foodID: 3), to: &value)
        XCTAssertEqual(value.pet.level, 3)
        XCTAssertEqual(value.pet.experience, 0)
        XCTAssertEqual(value.pet.statPoints, 4)
    }

    func testFeedingResetsMoodAndFeedingTime() throws {
        var value = PetProgress.newUser(at: now.addingTimeInterval(-100_000))
        try apply(.refreshMood, to: &value)
        XCTAssertEqual(value.pet.mood, .hungry)
        try apply(.feed(foodID: 1), to: &value)
        XCTAssertEqual(value.pet.mood, .happy)
        XCTAssertEqual(value.pet.lastFedAt, now)
    }

    func testStatAllocationConsumesOnePointForEachSelectedStat() throws {
        var value = PetProgress.newUser(at: now)
        value.pet.statPoints = 3
        for statistic in TrainableStatistic.allCases { try apply(.allocate(statistic), to: &value) }
        XCTAssertEqual(value.pet.attack, 51)
        XCTAssertEqual(value.pet.defense, 1)
        XCTAssertEqual(value.pet.health, 9)
        XCTAssertEqual(value.pet.statPoints, 0)
        let before = value
        XCTAssertThrowsError(try apply(.allocate(.attack), to: &value)) {
            XCTAssertEqual($0 as? PetProgressError, .noStatPoints)
        }
        XCTAssertEqual(value, before)
    }

    func testTouchAffectionEveryFiftyTaps() throws {
        var value = PetProgress.newUser(at: now)
        for _ in 0..<49 { try apply(.touch, to: &value) }
        XCTAssertEqual(value.pet.affection, 0)
        try apply(.touch, to: &value)
        XCTAssertEqual(value.pet.affection, 1)
        XCTAssertEqual(value.touchCount, 0)
    }

    func testMoodAtTwentyFourHoursAndClockRollback() throws {
        var value = PetProgress.newUser(at: now)
        try apply(.visit, to: &value, at: now.addingTimeInterval(-1))
        XCTAssertEqual(value.pet.mood, .happy)
        try apply(.refreshMood, to: &value, at: now.addingTimeInterval(86_399))
        XCTAssertEqual(value.pet.mood, .happy)
        try apply(.visit, to: &value, at: now.addingTimeInterval(86_400))
        XCTAssertEqual(value.pet.mood, .hungry) // hunger takes priority over inactivity
        value.pet.lastFedAt = now.addingTimeInterval(86_401)
        try apply(.visit, to: &value, at: now.addingTimeInterval(172_800))
        XCTAssertEqual(value.pet.mood, .sad)
    }

    func testRewardThresholdsDailyAppleAndReducedCountsDoNotReplay() throws {
        var value = PetProgress.newUser(at: now)
        XCTAssertEqual(try claim(999, to: &value), StepRewardGrant(milk: 0, apple: 1))
        XCTAssertEqual(try claim(1_000, to: &value), StepRewardGrant(milk: 1, apple: 0))
        XCTAssertEqual(try claim(3_999, to: &value), StepRewardGrant(milk: 2, apple: 0))
        XCTAssertTrue(try XCTUnwrap(claim(500, to: &value)).isEmpty)
        XCTAssertTrue(try XCTUnwrap(claim(3_999, to: &value)).isEmpty)
        XCTAssertEqual(try claim(4_000, to: &value), StepRewardGrant(milk: 1, apple: 0))
        XCTAssertEqual(value.quantity(of: 1), 7)
        XCTAssertEqual(value.quantity(of: 2), 1)
    }

    func testNewDayAndReturningToPreviouslyClaimedDate() throws {
        var value = PetProgress.newUser(at: now)
        _ = try claim(2_000, to: &value)
        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertEqual(try claim(1_000, to: &value, at: tomorrow), StepRewardGrant(milk: 1, apple: 1))
        XCTAssertTrue(try XCTUnwrap(claim(2_000, to: &value)).isEmpty)
        XCTAssertEqual(value.quantity(of: 1), 6)
        XCTAssertEqual(value.quantity(of: 2), 2)
    }

    func testOldDayAndNegativeRecordsRejected() throws {
        var value = PetProgress.newUser(at: now)
        XCTAssertThrowsError(try apply(.claimRewards(DailyStepRecord(date: "2000-01-01", stepCount: 1000)), to: &value)) {
            XCTAssertEqual($0 as? PetProgressError, .outdatedDay)
        }
        XCTAssertThrowsError(try claim(-1, to: &value)) {
            XCTAssertEqual($0 as? PetProgressError, .invalidRecord)
        }
    }

    @discardableResult
    private func apply(_ action: PetProgressAction, to value: inout PetProgress, at date: Date? = nil) throws -> StepRewardGrant? {
        try PetProgressRules.apply(action, to: &value, at: date ?? now, calendar: calendar)
    }

    private func claim(_ count: Int, to value: inout PetProgress, at date: Date? = nil) throws -> StepRewardGrant? {
        let instant = date ?? now
        return try apply(.claimRewards(DailyStepRecord(
            date: StepDay(containing: instant, calendar: calendar).date, stepCount: count
        )), to: &value, at: instant)
    }
}
