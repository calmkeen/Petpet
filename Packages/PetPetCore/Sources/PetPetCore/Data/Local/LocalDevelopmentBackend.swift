#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An in-process HTTP substitute. It has no network client or production fallback.
public actor LocalDevelopmentBackend: BackendHTTPTransport {
    public static let baseURL = URL(string: "https://debug.petpet.invalid/")!
    public static let accountID: Int64 = 900_000_001
    public static let reservedNicknames: Set<String> = ["사용중닉네임", "StepMate"]
    private struct Archive: Codable {
        var version = 1
        var accessToken: String?
        var refreshToken: String?
        var pet: ServerBackupRequest?
        var records: [String: Int] = [:]
        var nickname: String?
    }
    private let fileURL: URL
    private var cached: Archive?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        guard let url = request.url, url.scheme == Self.baseURL.scheme, url.host == Self.baseURL.host,
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              url.query == nil || (url.path == "/api/v1/users/nickname/check" && request.httpMethod == "GET") else {
            throw BackendError.configurationMissing
        }
        try load()
        switch (request.httpMethod ?? "GET", url.path) {
        case ("POST", "/debug/login"):
            return try issueSession()
        case ("POST", "/api/v1/auth/refresh"):
            let body = try? JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
            guard let refresh = cached!.refreshToken, body?["refreshToken"] == refresh else { return response(401) }
            return try issueSession()
        default:
            guard let token = cached!.accessToken,
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" else { return response(401) }
        }
        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/api/v1/users/me"):
            return try json(["nickname": currentNickname])
        case ("GET", "/api/v1/users/nickname/check"):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.count == 1, items.first?.name == "nickname", let nickname = items.first?.value else { return response(400) }
            do { try NicknameRules.validate(nickname) } catch { return response(400) }
            let duplicated = Self.reservedNicknames.contains(nickname) || nickname == currentNickname
            return try json(["duplicated": duplicated, "nickname": nickname, "message": duplicated ? "중복된 닉네임입니다." : "사용 가능한 닉네임입니다."])
        case ("PATCH", "/api/v1/users/nickname"):
            guard let body = try? JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data()),
                  let nickname = body["nickname"] else { return response(400) }
            do { try NicknameRules.validate(nickname) } catch { return response(400) }
            let duplicated = Self.reservedNicknames.contains(nickname)
            if !duplicated {
                var next = cached!; next.nickname = nickname
                try write(next)
            }
            return try json(["duplicated": duplicated, "nickname": nickname,
                             "message": duplicated ? "중복된 닉네임입니다." : "닉네임을 변경했습니다."])
        case ("POST", "/api/v1/backup"):
            let backup: ServerBackupRequest
            do {
                backup = try JSONDecoder().decode(ServerBackupRequest.self, from: request.httpBody ?? Data())
                try validate(backup)
            } catch { return response(400) }
            var next = cached!
            next.pet = backup
            for record in backup.stepCounts { next.records[record.date] = max(next.records[record.date] ?? 0, Int(record.stepCount)) }
            try write(next)
            return response(200)
        case ("GET", "/api/v1/usermates/1"):
            guard let pet = cached!.pet else { return response(404) }
            var body: [String: Any] = ["userId": Self.accountID, "userMateId": 1, "mateId": pet.userMateId,
                                      "level": pet.level, "experience": pet.experience, "affection": pet.affection,
                                      "attack": pet.attack, "defense": pet.defense, "health": pet.health, "status": pet.status]
            if let date = pet.lastFedAt { body["lastFedAt"] = date }
            return try json(body)
        case ("GET", "/api/v1/stepcounts/me"):
            guard cached!.pet != nil else { return response(404) }
            return try json(["userId": Self.accountID, "stepCounts": cached!.records.sorted { $0.key < $1.key }
                .map { ["date": $0.key, "stepCount": $0.value] as [String: Any] }])
        default: return response(404)
        }
    }

    private func issueSession() throws -> BackendHTTPResponse {
        var next = cached!
        next.accessToken = "debug-access-\(UUID().uuidString)"
        next.refreshToken = "debug-refresh-\(UUID().uuidString)"
        // Commit first, just as a server must finish its transaction before 200.
        try write(next)
        return try json(["userId": Self.accountID, "accessToken": next.accessToken!, "refreshToken": next.refreshToken!,
                         "name": "개발 테스트 계정", "nickname": currentNickname, "selectedMateId": 1])
    }

    private var currentNickname: String { cached?.nickname ?? "개발 테스트 계정" }

    private func validate(_ backup: ServerBackupRequest) throws {
        guard !backup.stepCounts.isEmpty, let mood = PetMood(rawValue: backup.status) else { throw BackendError.invalidResponse }
        let lastFedAt = backup.lastFedAt.flatMap { ServerDateTime.date($0, timeZone: .current) }
        guard backup.lastFedAt == nil || lastFedAt != nil else { throw BackendError.invalidResponse }
        let pet = PetProfile(id: backup.userMateId, level: backup.level, experience: backup.experience,
                             affection: backup.affection, attack: backup.attack, defense: backup.defense,
                             health: backup.health, mood: mood, lastFedAt: lastFedAt, statPoints: 0)
        let records = try backup.stepCounts.map { record -> DailyStepRecord in
            guard let count = Int(exactly: record.stepCount) else { throw BackendError.invalidResponse }
            return DailyStepRecord(date: record.date, stepCount: count)
        }
        try ServerRestoreState.validate(pet: pet, steps: records)
    }

    private func load() throws {
        guard cached == nil else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let value = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard value.version == 1, value.records.allSatisfy({ StepDateKey.isValid($0.key) && $0.value >= 0 }) else {
                throw BackendError.storage
            }
            if let pet = value.pet { try validate(pet) }
            cached = value
        } else { cached = Archive() }
    }

    private func write(_ next: Archive) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            cached = next
        } catch { throw BackendError.storage }
    }
    private func json(_ body: [String: Any]) throws -> BackendHTTPResponse {
        BackendHTTPResponse(statusCode: 200, data: try JSONSerialization.data(withJSONObject: body))
    }
    private func response(_ status: Int) -> BackendHTTPResponse {
        BackendHTTPResponse(statusCode: status, data: Data("{}".utf8))
    }
}
#endif
