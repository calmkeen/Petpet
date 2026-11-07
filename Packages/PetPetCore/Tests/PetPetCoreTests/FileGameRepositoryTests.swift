import XCTest
@testable import PetPetCore

final class FileGameRepositoryTests: XCTestCase {
    private let day = "2026-11-07"
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    func testMigrationPreservesHistoryPetFoodPointsAndTouchCount() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let petURL = directory.appendingPathComponent("pet-progress-v1.json")
        let stepsURL = directory.appendingPathComponent("step-history-v1.json")
        let oldPet = FilePetProgressRepository(fileURL: petURL)
        let oldSteps = FileStepHistoryRepository(fileURL: stepsURL)
        _ = try await oldPet.perform(.feed(foodID: 1))
        _ = try await oldPet.perform(.feed(foodID: 1))
        for _ in 0..<49 { _ = try await oldPet.perform(.touch) }
        try await oldSteps.save(DailyStepRecord(date: day, stepCount: 4321))
        let petBefore = try await oldPet.load()
        let original = try Data(contentsOf: petURL)
        let game = repository(directory)
        let migrated = try await game.load()
        let steps = try await game.record(for: day)
        XCTAssertEqual(migrated, petBefore)
        XCTAssertEqual(steps?.stepCount, 4321)
        XCTAssertEqual(try Data(contentsOf: petURL), original)
        let reload = try await repository(directory).load()
        XCTAssertEqual(reload, migrated)
    }

    func testServerRestorePreservesFoodPointsRewardLedgerAndLargestSteps() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        _ = try await game.perform(.feed(foodID: 1))
        _ = try await game.perform(.feed(foodID: 1))
        try await game.save(DailyStepRecord(date: day, stepCount: 3000))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "A")
        _ = try await game.confirmBackup(CloudBackupReceipt(export: export, completedAt: now))
        let before = try await game.load()
        let challenge = try await game.challenge()
        let restored = try await game.restore(WatchRestoreImport(target: challenge, state: remote(account: "A", steps: 2000)))
        XCTAssertEqual(restored.pet.level, 4)
        XCTAssertEqual(restored.pet.statPoints, before.pet.statPoints)
        XCTAssertEqual(restored.inventory, before.inventory)
        XCTAssertEqual(restored.rewardClaims, before.rewardClaims)
        let record = try await game.record(for: day)
        XCTAssertEqual(record?.stepCount, 3000)
    }

    func testRestoreRejectsChangedPetBeforeAnyMutation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        let challenge = try await game.challenge()
        _ = try await game.perform(.feed(foodID: 1))
        let before = try await game.load()
        do { _ = try await game.restore(WatchRestoreImport(target: challenge, state: remote(account: "A"))); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .localStateChanged) }
        let after = try await game.load()
        XCTAssertEqual(after, before)
    }

    func testRestoreAndReceiptsAreIdempotentAcrossRestart() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        let command = try await WatchRestoreImport(target: game.challenge(), state: remote(account: "A"))
        _ = try await game.restore(command)
        _ = try await game.perform(.touch)
        let before = try await game.load()
        let restored = try await repository(directory).restore(command)
        XCTAssertEqual(restored, before)
    }

    func testRewardsOnlyAfterAcknowledgementAndDuplicateReceiptCannotPayTwice() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        try await game.save(DailyStepRecord(date: day, stepCount: 2500))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "A")
        let pending = try await game.load()
        XCTAssertEqual(pending.quantity(of: 1), 3)
        XCTAssertEqual(pending.quantity(of: 2), 0)
        let receipt = CloudBackupReceipt(export: export, completedAt: now)
        let paid = try await game.confirmBackup(receipt)
        XCTAssertEqual(paid.quantity(of: 1), 5)
        XCTAssertEqual(paid.quantity(of: 2), 1)
        let duplicate = try await repository(directory).confirmBackup(receipt)
        XCTAssertEqual(duplicate, paid)
        let another = try await game.prepareBackup(operationID: UUID(), accountID: "A")
        let repeated = try await game.confirmBackup(CloudBackupReceipt(export: another, completedAt: now))
        XCTAssertEqual(repeated, paid)
    }

    func testDelayedReceiptPaysOriginalDayWithoutSpendingTomorrowsReward() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        try await game.save(DailyStepRecord(date: day, stepCount: 2000))
        let export = try await game.prepareBackup(operationID: UUID(), accountID: "A")
        let tomorrow = now.addingTimeInterval(86400)
        let nextDay = repository(directory, at: tomorrow)
        let progress = try await nextDay.confirmBackup(CloudBackupReceipt(export: export, completedAt: tomorrow))
        XCTAssertEqual(progress.rewardClaims[day]?.milkUnits, 2)
        XCTAssertNil(progress.rewardClaims["2026-11-08"])
    }

    func testAccountSwitchArchivesPreviousGameAndNeverUploadsItAsAnotherUser() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        try await game.save(DailyStepRecord(date: day, stepCount: 9000))
        let pendingA = try await game.prepareBackup(operationID: UUID(), accountID: "A")
        do { _ = try await game.prepareBackup(operationID: UUID(), accountID: "B"); XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .accountMismatch) }
        let target = try await game.challenge()
        let b = try await game.restore(WatchRestoreImport(target: target, state: remote(account: "B", steps: 100)))
        XCTAssertTrue(b.inventory.isEmpty)
        let bSteps = try await game.record(for: day)
        XCTAssertEqual(bSteps?.stepCount, 100)
        // An old successful receipt updates parked A, never B's food inventory.
        _ = try await game.confirmBackup(CloudBackupReceipt(export: pendingA, completedAt: now))
        let current = try await game.load()
        XCTAssertTrue(current.inventory.isEmpty)
        let back = try await game.restore(WatchRestoreImport(target: game.challenge(), state: remote(account: "A", steps: 1000)))
        XCTAssertEqual(back.quantity(of: 1), 12)
        let aSteps = try await game.record(for: day)
        XCTAssertEqual(aSteps?.stepCount, 9000)
    }

    func testFailedRestoreCannotPartiallyReplacePetOrStepsAndDirtyStepsRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = repository(directory)
        let before = try await game.load()
        let challenge = try await game.challenge()
        let saved = try Data(contentsOf: directory.appendingPathComponent("game-state-v1.json"))
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do { _ = try await game.restore(WatchRestoreImport(target: challenge, state: remote(account: "A"))); XCTFail() } catch {}
        let unchanged = try await game.load()
        XCTAssertEqual(unchanged, before)
        do { try await game.save(DailyStepRecord(date: day, stepCount: 3210)); XCTFail() } catch {}
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try saved.write(to: directory.appendingPathComponent("game-state-v1.json"))
        _ = try await game.perform(.feed(foodID: 1))
        let retry = repository(directory)
        let recovered = try await retry.record(for: day)
        XCTAssertEqual(recovered?.stepCount, 3210)
        let profile = try await retry.load()
        XCTAssertEqual(profile.quantity(of: 1), 2)
    }

    private func remote(account: String, steps: Int = 1000) throws -> ServerRestoreState {
        var pet = PetProgress.newUser(at: now).pet
        pet.level = 4; pet.experience = 1; pet.attack = 52
        return try ServerRestoreState(accountID: account, pet: pet, steps: [DailyStepRecord(date: day, stepCount: steps)])
    }
    private func repository(_ directory: URL, at date: Date? = nil) -> FileGameRepository {
        let instant = date ?? now
        return FileGameRepository(directory: directory, now: { instant }, calendar: calendar)
    }
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
