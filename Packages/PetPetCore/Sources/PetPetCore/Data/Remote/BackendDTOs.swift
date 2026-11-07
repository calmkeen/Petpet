import Foundation

struct BackendAuthResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var userID: String?
    var email: String?
    var name: String?
    var nickname: String?
    var selectedMateID: Int64?
    var isNewUser: Bool

    private enum CodingKeys: String, CodingKey {
        case accessToken, access_token, refreshToken, refresh_token, userId, user_id
        case email, name, nickname, selectedMateId, selected_mate_id, isNewUser, newUser, isNewMember
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
            ?? c.decodeIfPresent(String.self, forKey: .access_token)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? c.decodeIfPresent(String.self, forKey: .refresh_token)
        userID = (try? c.decode(String.self, forKey: .userId))
            ?? (try? c.decode(Int64.self, forKey: .userId)).map(String.init)
            ?? (try? c.decode(String.self, forKey: .user_id))
            ?? (try? c.decode(Int64.self, forKey: .user_id)).map(String.init)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        selectedMateID = try c.decodeIfPresent(Int64.self, forKey: .selectedMateId)
            ?? c.decodeIfPresent(Int64.self, forKey: .selected_mate_id)
        isNewUser = try c.decodeIfPresent(Bool.self, forKey: .isNewUser)
            ?? c.decodeIfPresent(Bool.self, forKey: .newUser)
            ?? c.decodeIfPresent(Bool.self, forKey: .isNewMember) ?? false
    }
}

public struct ServerBackupRequest: Codable, Equatable, Sendable {
    public let userMateId: Int64
    public let stepCounts: [ServerStepCount]
    public let level: Int64
    public let experience: Int64
    public let affection: Int64
    public let attack: Int64
    public let defense: Int64
    public let health: Int64
    public let status: String
    public let lastFedAt: String?

    public init(pet: PetProfile, steps: [DailyStepRecord], timeZone: TimeZone) throws {
        try ServerRestoreState.validate(pet: pet, steps: steps)
        userMateId = pet.id
        stepCounts = steps.sorted { $0.date < $1.date }.map { ServerStepCount(date: $0.date, stepCount: Int64($0.stepCount)) }
        level = pet.level; experience = pet.experience; affection = pet.affection
        attack = pet.attack; defense = pet.defense; health = pet.health
        status = pet.mood.rawValue
        lastFedAt = pet.lastFedAt.map { ServerDateTime.string($0, timeZone: timeZone) }
    }
}

public struct ServerStepCount: Codable, Equatable, Sendable {
    public let date: String
    public let stepCount: Int64
    public init(date: String, stepCount: Int64) { self.date = date; self.stepCount = stepCount }
}

struct ServerPetResponse: Decodable {
    let userId: Int64
    let userMateId: Int64
    let mateId: Int64
    let level: Int64
    let experience: Int64
    let affection: Int64
    let attack: Int64
    let defense: Int64
    let health: Int64
    let status: PetMood
    let lastFedAt: String?
}

struct ServerStepsResponse: Decodable {
    let userId: Int64
    let stepCounts: [ServerStepCount]
}

/// The server does not return inventory, reward cursors or unspent stat points.
/// Restore therefore merges these fields with the watch's local aggregate.
public struct ServerRestoreState: Codable, Equatable, Sendable {
    public let accountID: String
    public let pet: PetProfile
    public let steps: [DailyStepRecord]

    public init(accountID: String, pet: PetProfile, steps: [DailyStepRecord]) throws {
        try Self.validate(pet: pet, steps: steps)
        self.accountID = accountID; self.pet = pet; self.steps = steps
    }

    public static func validate(pet: PetProfile, steps: [DailyStepRecord]) throws {
        guard pet.id == 1 else { throw BackendError.unsupportedMate }
        guard pet.level > 0, pet.level <= Int64.max / 2,
              pet.experience >= 0, pet.experience < pet.level * 2,
              [pet.affection, pet.attack, pet.defense, pet.health, pet.statPoints].allSatisfy({ $0 >= 0 }),
              steps.count <= 100_000,
              steps.allSatisfy({ StepDateKey.isValid($0.date) && $0.stepCount >= 0 }),
              Set(steps.map(\.date)).count == steps.count else { throw BackendError.invalidResponse }
    }
}

public enum ServerDateTime {
    public static func string(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = formatter(timeZone: timeZone)
        return formatter.string(from: date)
    }

    public static func date(_ text: String, timeZone: TimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let formatter = formatter(timeZone: timeZone)
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.isLenient = false
        return formatter
    }
}
