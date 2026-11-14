import XCTest
@testable import PetPetCore

/// Prepared for the separate runtime review; normal feature work builds only.
final class PetCustomizationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testSelectionSurvivesReopeningWithoutChangingGameData() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gameURL = root.appendingPathComponent("game-state-v1.json")
        let gameData = try JSONEncoder().encode(PetProgress.newUser(at: now))
        try gameData.write(to: gameURL)
        let url = root.appendingPathComponent("appearance.json")
        let store = FilePetCustomizationRepository(fileURL: url)
        let initial = try await store.load(); XCTAssertEqual(initial, .default)
        let selected = PetCustomization(characterID: "snow-fox", backgroundID: "night")
        try await store.save(selected)
        let reopened = try await FilePetCustomizationRepository(fileURL: url).load()
        XCTAssertEqual(reopened, selected)
        XCTAssertEqual(try Data(contentsOf: gameURL), gameData)
    }
    func testFutureIDsArePreservedWhileRenderingKnownDefaults() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("appearance.json")
        let selection = PetCustomization(characterID: "future-rabbit", backgroundID: "future-forest")
        try await FilePetCustomizationRepository(fileURL: url).save(selection)
        let reopened = try await FilePetCustomizationRepository(fileURL: url).load()
        XCTAssertEqual(reopened, selection)
        XCTAssertEqual(reopened.character.id, PetCustomization.default.characterID)
        XCTAssertEqual(reopened.background(at: now), PetCustomization.default.background(at: now))
    }
    func testDamagedAndNewerDocumentsCannotBeOverwritten() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("appearance.json")
        for text in ["broken", #"{"version":99,"selection":{"characterID":"snow-fox","backgroundID":"night"}}"#] {
            let original = Data(text.utf8); try original.write(to: url)
            let store = FilePetCustomizationRepository(fileURL: url)
            do { try await store.save(.default); XCTFail("Must preserve unreadable/newer preferences") }
            catch {}
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
    func testInvalidIDsCannotEnterStorageOrSnapshots() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("appearance.json")
        for id in ["", "../fox", String(repeating: "a", count: 65)] {
            let selection = PetCustomization(characterID: id, backgroundID: "night")
            do { try await FilePetCustomizationRepository(fileURL: url).save(selection); XCTFail("Invalid ID") }
            catch {}
            XCTAssertThrowsError(try WatchSnapshotCodec.encode(snapshot(selection)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    func testLegacyAndFutureSnapshotsPreserveGameProjection() throws {
        let legacy = try WatchSnapshotCodec.decode(WatchSnapshotCodec.encode(snapshot(nil)))
        XCTAssertNil(legacy.customization); XCTAssertEqual(legacy.resolvedCustomization, .default)
        let selection = PetCustomization(characterID: "future-rabbit", backgroundID: "night")
        let updated = try WatchSnapshotCodec.decode(WatchSnapshotCodec.encode(snapshot(selection)))
        XCTAssertEqual(updated.customization, selection)
        XCTAssertEqual(updated.pet, legacy.pet); XCTAssertEqual(updated.inventory, legacy.inventory)
    }
    @MainActor
    func testCosmeticReadFailureStillPublishesGameAndLastKnownSelection() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let game = FileGameRepository(directory: root)
        let progress = try await game.load()
        let outbox = FileWatchSnapshotOutbox(fileURL: root.appendingPathComponent("outbox.json"))
        let selection = PetCustomization(characterID: "snow-fox", backgroundID: "night")
        let old = try await outbox.prepare(steps: [], progress: progress, at: now, customization: selection)
        let appearanceURL = root.appendingPathComponent("appearance.json")
        try Data("broken".utf8).write(to: appearanceURL)
        let transport = CustomizationSnapshotWire()
        let publisher = WatchSnapshotPublisher(history: game, progress: game, outbox: outbox, transport: transport,
            now: { self.now }, customization: FilePetCustomizationRepository(fileURL: appearanceURL))
        let published = try await publisher.publish()
        XCTAssertEqual(published.pet, progress.pet); XCTAssertEqual(published.inventory, progress.inventory)
        XCTAssertEqual(published.customization, selection)
        XCTAssertEqual(published.sourceID, old.sourceID); XCTAssertEqual(published.revision, old.revision + 1)
        XCTAssertEqual(transport.sent.count, 1)
    }
    private func snapshot(_ customization: PetCustomization?) -> WatchSnapshot {
        let progress = PetProgress.newUser(at: now)
        return WatchSnapshot(sourceID: UUID(), revision: 1, generatedAt: now, steps: [], pet: progress.pet,
                             inventory: progress.inventory, customization: customization)
    }
}

@MainActor private final class CustomizationSnapshotWire: SnapshotTransport {
    var connection = SnapshotConnection(isActivated: true)
    var onConnectionChange: ((SnapshotConnection) -> Void)?
    var onSnapshot: ((Data, String) -> Void)?
    var onSnapshotRequest: (() async throws -> Data)?
    var sent: [Data] = []
    func activate() {}
    func publish(_ data: Data) { sent.append(data) }
    func requestLatest() async throws -> Data { throw SnapshotSyncError.notReachable }
}
