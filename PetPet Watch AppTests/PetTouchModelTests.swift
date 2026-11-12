import XCTest
import PetPetCore
@testable import PetPet_Watch_App

@MainActor
final class PetTouchModelTests: XCTestCase {
    func testSavedTouchesPublishCountAndAffectionAndSurviveReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileGameRepository(directory: directory)
        let model = PetProgressViewModel(repository: repository, history: repository)
        await model.reload()
        for count in 1...50 {
            let saved = await model.touch()
            XCTAssertTrue(saved)
            XCTAssertEqual(model.progress?.touchCount, count % 50)
            XCTAssertEqual(model.progress?.pet.affection, count == 50 ? 1 : 0)
            XCTAssertEqual(model.message, count == 50 ? "애정도 +1!" : "쓰다듬기 \(count)/50")
        }
        let restored = try await FileGameRepository(directory: directory).load()
        XCTAssertEqual(restored.touchCount, 0)
        XCTAssertEqual(restored.pet.affection, 1)
    }

    func testFailedSaveDoesNotPublishCountOrSuccess() async {
        let repository = FailedTouchRepository()
        let model = PetProgressViewModel(repository: repository, history: PreviewStepHistoryRepository())
        await model.reload()
        let before = model.progress
        let saved = await model.touch()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.progress, before)
        XCTAssertNil(model.message)
        XCTAssertNotNil(model.errorMessage)
    }

    func testExistingAffectionDoesNotAnnounceANewRewardBeforeFirstLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileGameRepository(directory: directory)
        for _ in 0..<50 { _ = try await repository.perform(.touch) }
        let model = PetProgressViewModel(repository: repository, history: repository)
        let saved = await model.touch()
        XCTAssertTrue(saved)
        XCTAssertEqual(model.progress?.pet.affection, 1)
        XCTAssertEqual(model.progress?.touchCount, 1)
        XCTAssertEqual(model.message, "쓰다듬기 1/50")
    }

    func testGreetingReadinessMatchesTheAnimationGate() async {
        let model = CharacterActivityViewModel()
        let steps = DailyStepState(date: "2026-11-12", stepCount: 0, isLoading: false)
        XCTAssertFalse(model.canTouch)
        model.setActive(true, steps: steps)
        XCTAssertTrue(model.canTouch)
        XCTAssertTrue(model.handleTouch())
        XCTAssertFalse(model.canTouch)
        XCTAssertFalse(model.handleTouch())
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in model.canTouch }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(result, .completed)
        model.stop()
        XCTAssertFalse(model.canTouch)
    }
}

private actor FailedTouchRepository: PetProgressRepository {
    func load() async throws -> PetProgress { .newUser(at: Date()) }
    func perform(_ action: PetProgressAction) async throws -> PetProgressChange {
        throw CocoaError(.fileWriteNoPermission)
    }
}
