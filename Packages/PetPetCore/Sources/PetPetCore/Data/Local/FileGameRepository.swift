import Foundation

/// Migration and every restore/backup acknowledgement commit one aggregate.
/// Legacy files remain untouched as the pre-migration recovery copy.
public actor FileGameRepository: StepHistoryRepository, PetProgressRepository {
    private struct Game: Codable {
        var progress: PetProgress
        var records: [String: Int]
        var lastBackupDate: String?
        var lastBackupAt: Date?
    }
    private struct Archive: Codable {
        var version = 1
        var storeID: UUID
        var ownerID: String?
        var game: Game
        var parked: [String: Game] = [:]
        var pending: [String: WatchBackupExport] = [:]
        var appliedBackups: Set<UUID> = []
        var appliedRestores: Set<UUID> = []
        var restoreUndo: Game?
        var exportSequence: Int64 = 0
    }
    private let directory: URL
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var cached: Archive?
    private var loading: Task<Archive, Error>?
    private var dirtySteps: [String: Int] = [:]
    #if DEBUG
    private var developmentSeedDirectory: URL?

    /// Copies active progress once; account bindings and receipts start fresh.
    public init(developmentDirectory: URL, seedDirectory: URL,
                now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent) {
        directory = developmentDirectory; self.now = now; self.calendar = calendar
        developmentSeedDirectory = seedDirectory
    }
    #endif

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent) {
        self.directory = directory; self.now = now; self.calendar = calendar
    }

    public func load() async throws -> PetProgress {
        try await ensureLoaded()
        return cached!.game.progress
    }
    public func perform(_ action: PetProgressAction) async throws -> PetProgressChange {
        if case .claimRewards = action { throw BackendError.authenticationRequired }
        try await ensureLoaded()
        var next = cached!
        let reward = try PetProgressRules.apply(action, to: &next.game.progress, at: now(), calendar: calendar)
        try commit(next)
        return PetProgressChange(progress: cached!.game.progress, reward: reward)
    }
    public func record(for date: String) async throws -> DailyStepRecord? {
        try await ensureLoaded()
        let existing = cached!.game.records[date]
        let dirty = dirtySteps[date]
        guard existing != nil || dirty != nil else { return nil }
        return DailyStepRecord(date: date, stepCount: max(existing ?? 0, dirty ?? 0))
    }
    public func allRecords() async throws -> [DailyStepRecord] {
        try await ensureLoaded()
        return mergedRecords().map { DailyStepRecord(date: $0.key, stepCount: $0.value) }.sorted { $0.date > $1.date }
    }
    public func save(_ record: DailyStepRecord) async throws {
        guard StepDateKey.isValid(record.date), record.stepCount >= 0 else { throw StepHistoryStoreError.invalidRecord }
        try await ensureLoaded()
        let total = max(cached!.game.records[record.date] ?? 0, dirtySteps[record.date] ?? 0, record.stepCount)
        guard cached!.game.records[record.date] != total || !dirtySteps.isEmpty else { return }
        dirtySteps[record.date] = total
        try commit(cached!)
    }

    public func challenge() async throws -> WatchRestoreChallenge {
        try await ensureLoaded()
        return WatchRestoreChallenge(storeID: cached!.storeID, ownerID: cached!.ownerID, pet: cached!.game.progress.pet)
    }

    public func prepareBackup(operationID: UUID, accountID: String) async throws -> WatchBackupExport {
        guard !accountID.isEmpty else { throw BackendError.authenticationRequired }
        try await ensureLoaded()
        var next = cached!
        guard next.ownerID == nil || next.ownerID == accountID else { throw BackendError.accountMismatch }
        if let pending = next.pending[operationID.uuidString] { return pending }
        guard next.pending.count < 32 else { throw BackendError.operationExpired }
        guard next.exportSequence < Int64.max else { throw BackendError.invalidResponse }
        next.exportSequence += 1
        next.ownerID = accountID
        for (date, count) in dirtySteps { next.game.records[date] = max(next.game.records[date] ?? 0, count) }
        let capturedAt = now()
        let day = StepDay(containing: capturedAt, calendar: calendar).date
        if next.game.records[day] == nil { next.game.records[day] = 0 }
        var steps = next.game.records.filter { entry in
            next.game.lastBackupDate.map { entry.key >= $0 } ?? true
        }
            .map { DailyStepRecord(date: $0.key, stepCount: $0.value) }
        // Include the current day even after a device clock/date rollback.
        if !steps.contains(where: { $0.date == day }) {
            steps.append(DailyStepRecord(date: day, stepCount: next.game.records[day] ?? 0))
        }
        let export = WatchBackupExport(operationID: operationID, storeID: next.storeID, sequence: next.exportSequence, accountID: accountID,
                                       capturedAt: capturedAt, timeZoneIdentifier: calendar.timeZone.identifier,
                                       backupDay: day, pet: next.game.progress.pet, steps: steps.sorted { $0.date < $1.date })
        _ = try export.request()
        next.pending[operationID.uuidString] = export
        try commit(next)
        return export
    }

    @discardableResult
    public func confirmBackup(_ receipt: CloudBackupReceipt) async throws -> PetProgress {
        try await ensureLoaded()
        var next = cached!
        guard receipt.storeID == next.storeID else { throw BackendError.accountMismatch }
        if next.appliedBackups.contains(receipt.operationID) { return next.game.progress }
        guard let export = next.pending[receipt.operationID.uuidString], export.accountID == receipt.accountID,
              export.sequence == receipt.sequence else {
            throw BackendError.operationExpired
        }
        let active = next.ownerID == receipt.accountID
        var game: Game
        if active { game = next.game }
        else if let parked = next.parked[receipt.accountID] { game = parked }
        else { throw BackendError.accountMismatch }
        let record = export.steps.first { $0.date == export.backupDay } ?? DailyStepRecord(date: export.backupDay, stepCount: 0)
        // A queued receipt can arrive after midnight. Reward only the day and
        // count in the acknowledged export, using its original time zone.
        var originalCalendar = Calendar(identifier: .gregorian)
        originalCalendar.timeZone = TimeZone(identifier: export.timeZoneIdentifier) ?? calendar.timeZone
        _ = try PetProgressRules.apply(.claimRewards(record), to: &game.progress,
                                      at: export.capturedAt, calendar: originalCalendar)
        game.lastBackupDate = max(game.lastBackupDate ?? "", export.steps.map(\.date).max() ?? export.backupDay)
        game.lastBackupAt = receipt.completedAt
        if active { next.game = game } else { next.parked[receipt.accountID] = game }
        next.pending.removeValue(forKey: receipt.operationID.uuidString)
        next.appliedBackups.insert(receipt.operationID)
        try commit(next)
        return cached!.game.progress
    }

    @discardableResult
    public func restore(_ command: WatchRestoreImport) async throws -> PetProgress {
        try ServerRestoreState.validate(pet: command.state.pet, steps: command.state.steps)
        guard !command.state.accountID.isEmpty else { throw BackendError.accountMismatch }
        try await ensureLoaded()
        var next = cached!
        guard command.target.storeID == next.storeID else { throw BackendError.accountMismatch }
        if next.appliedRestores.contains(command.operationID) { return next.game.progress }
        guard command.target.ownerID == next.ownerID, command.target.pet == next.game.progress.pet else {
            throw BackendError.localStateChanged
        }
        for (date, count) in dirtySteps { next.game.records[date] = max(next.game.records[date] ?? 0, count) }
        let previous = next.game
        let sameOwner = next.ownerID == nil || next.ownerID == command.state.accountID
        if !sameOwner {
            if let oldOwner = next.ownerID { next.parked[oldOwner] = previous }
            if let parked = next.parked.removeValue(forKey: command.state.accountID) {
                next.game = parked
            } else {
                var progress = PetProgress.newUser(at: now())
                progress.inventory = [] // restoring another account never farms starter food
                next.game = Game(progress: progress, records: [:])
            }
        }
        next.restoreUndo = previous
        next.ownerID = command.state.accountID
        let points = next.game.progress.pet.statPoints
        next.game.progress.pet = command.state.pet
        next.game.progress.pet.statPoints = points
        for record in command.state.steps {
            next.game.records[record.date] = max(next.game.records[record.date] ?? 0, record.stepCount)
        }
        next.appliedRestores.insert(command.operationID)
        try commit(next, includeDirtySteps: sameOwner)
        return cached!.game.progress
    }

    public func lastBackupAt() async throws -> Date? {
        try await ensureLoaded()
        return cached!.game.lastBackupAt
    }

    public func cancelBackup(operationID: UUID) async throws {
        try await ensureLoaded()
        var next = cached!
        if next.pending.removeValue(forKey: operationID.uuidString) != nil { try commit(next) }
    }

    private func mergedRecords() -> [String: Int] {
        var records = cached!.game.records
        for (date, count) in dirtySteps { records[date] = max(records[date] ?? 0, count) }
        return records
    }

    private func commit(_ archive: Archive, includeDirtySteps: Bool = true) throws {
        var next = archive
        if includeDirtySteps {
            for (date, count) in dirtySteps { next.game.records[date] = max(next.game.records[date] ?? 0, count) }
        }
        try Self.validate(next)
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("game-state-v1.json"), options: .atomic)
        cached = next
        dirtySteps.removeAll()
    }

    private func ensureLoaded() async throws {
        if cached != nil { return }
        if let loading {
            let result = try await loading.value
            if cached == nil { cached = result }
            return
        }
        #if DEBUG
        let seedDirectory = developmentSeedDirectory
        #endif
        let task = Task { [directory, now, calendar] in
            let file = directory.appendingPathComponent("game-state-v1.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                try Self.validate(archive)
                return archive
            }
            #if DEBUG
            if let source = seedDirectory {
                guard source.standardizedFileURL != directory.standardizedFileURL else { throw BackendError.configurationMissing }
                let sourceFile = source.appendingPathComponent("game-state-v1.json")
                if FileManager.default.fileExists(atPath: sourceFile.path) {
                    let old = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: sourceFile))
                    try Self.validate(old)
                    let copy = Archive(storeID: UUID(), game: Game(progress: old.game.progress, records: old.game.records))
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try JSONEncoder().encode(copy).write(to: file, options: .atomic)
                    return copy
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for name in ["step-history-v1.json", "pet-progress-v1.json"] {
                    let original = source.appendingPathComponent(name)
                    let destination = directory.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: original.path), !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: original, to: destination)
                    }
                }
            }
            #endif
            let oldSteps = FileStepHistoryRepository(fileURL: directory.appendingPathComponent("step-history-v1.json"))
            let oldPet = FilePetProgressRepository(fileURL: directory.appendingPathComponent("pet-progress-v1.json"), now: now, calendar: calendar)
            let records = try await oldSteps.allRecords()
            let progress = try await oldPet.load()
            let archive = Archive(storeID: UUID(), game: Game(progress: progress,
                records: Dictionary(uniqueKeysWithValues: records.map { ($0.date, $0.stepCount) })))
            try Self.validate(archive)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: file, options: .atomic)
            return archive
        }
        loading = task
        do {
            let archive = try await task.value
            if cached == nil { cached = archive }
            loading = nil
        } catch { loading = nil; throw error }
    }

    private static func validate(_ archive: Archive) throws {
        guard archive.version == 1 else { throw PetProgressError.unsupportedVersion(archive.version) }
        for game in [archive.game] + Array(archive.parked.values) {
            try FilePetProgressRepository.validate(game.progress)
            guard game.records.allSatisfy({ StepDateKey.isValid($0.key) && $0.value >= 0 }) else {
                throw StepHistoryStoreError.invalidRecord
            }
        }
    }
}
