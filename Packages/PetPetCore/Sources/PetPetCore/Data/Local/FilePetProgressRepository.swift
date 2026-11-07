import Foundation

/// One actor per container. A command commits the entire aggregate or changes
/// nothing, including in-memory state, when encoding/writing fails.
public actor FilePetProgressRepository: PetProgressRepository {
    private struct Archive: Codable {
        var version: Int
        var progress: PetProgress
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var cached: PetProgress?

    public init(
        fileURL: URL, now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar
    }

    public func load() throws -> PetProgress {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let progress = PetProgress.newUser(at: now())
            try persist(progress)
            return progress
        }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else { throw PetProgressError.unsupportedVersion(archive.version) }
        try Self.validate(archive.progress)
        cached = archive.progress
        return archive.progress
    }

    public func perform(_ action: PetProgressAction) throws -> PetProgressChange {
        let original = try load()
        var updated = original
        let reward = try PetProgressRules.apply(action, to: &updated, at: now(), calendar: calendar)
        if updated != original { try persist(updated) }
        return PetProgressChange(progress: updated, reward: reward)
    }

    private func persist(_ progress: PetProgress) throws {
        let data = try JSONEncoder().encode(Archive(version: 1, progress: progress))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        cached = progress
    }

    static func validate(_ progress: PetProgress) throws {
        let pet = progress.pet
        let quantitiesValid = progress.inventory.allSatisfy {
            $0.id == $0.foodID && FoodCatalog.food(id: $0.foodID) != nil && $0.quantity > 0
        }
        guard pet.id == 1, pet.level > 0, pet.level <= Int64.max / 2,
              pet.experience >= 0, pet.experience < pet.level * 2,
              [pet.affection, pet.attack, pet.defense, pet.health, pet.statPoints].allSatisfy({ $0 >= 0 }),
              (0..<50).contains(progress.touchCount), quantitiesValid,
              Set(progress.inventory.map(\.foodID)).count == progress.inventory.count,
              progress.rewardClaims.allSatisfy({
                  StepDateKey.isValid($0.key) && $0.value.milkUnits >= 0
              }) else { throw PetProgressError.invalidRecord }
    }
}
