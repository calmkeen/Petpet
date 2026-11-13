#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An in-process HTTP substitute. It has no network client or production fallback.
public actor LocalDevelopmentBackend: BackendHTTPTransport, BackendChatTransport {
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
        var gameScores: [String: GameScore]?
        var image: RepresentativeImage?
        var pictureUrl: String?
    }
    private let fileURL: URL
    private var cached: Archive?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func send(_ request: URLRequest) async throws -> BackendHTTPResponse {
        guard let url = request.url, url.scheme == Self.baseURL.scheme, url.host == Self.baseURL.host,
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              url.query == nil || (request.httpMethod == "GET" && (url.path == "/api/v1/users/nickname/check" || url.path == "/api/v1/stepcounts/ranking" || url.path.hasSuffix("/rank/range"))) else {
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
        if url.path.contains("/rank/") { return try gameRank(request) }
        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/api/v1/users/me"):
            var profile: [String: Any] = ["nickname": currentNickname]
            if let url = cached!.pictureUrl { profile["pictureUrl"] = url }
            return try json(profile)
        case ("PATCH", "/api/v1/users/me/picture"):
            guard let body = request.httpBody, body.count <= RepresentativeImage.maximumBytes + 1024,
                  let image = try? RepresentativeImage.fromMultipart(body, contentType: request.value(forHTTPHeaderField: "Content-Type") ?? "") else { return response(400) }
            var next = cached!; next.image = image
            let url = Self.baseURL.appendingPathComponent("avatars/\(UUID().uuidString).jpg").absoluteString
            next.pictureUrl = url; try write(next)
            return try json(["pictureUrl": url])
        case ("GET", "/api/v1/stepcounts/ranking"):
            guard let page = try? rankingPage(url) else { return response(400) }
            var rows: [(Int64, String, Int64)] = (1...22).map { (900_001_000 + Int64($0), "걷기친구\($0)", Int64(250_000 - $0 * 5000)) }
            let total = try cached!.records.values.reduce(Int64(0)) { sum, count in
                let (value, overflow) = sum.addingReportingOverflow(Int64(count))
                guard !overflow else { throw BackendError.invalidResponse }; return value
            }
            rows.append((Self.accountID, currentNickname, total))
            rows.sort { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }
            let slice = rows.dropFirst((page.page - 1) * page.size).prefix(page.size)
            return try json(["page": page.page, "size": page.size, "totalUsers": rows.count,
                "rankings": slice.map { row in ["rank": 1 + rows.filter { $0.2 > row.2 }.count, "userId": row.0, "nickname": row.1, "totalStepCount": row.2] as [String: Any] }])
        case ("POST", "/api/v1/ai/chat/stream"):
            return response(200)
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

    public func stream(_ request: URLRequest, onEvent: @escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        let result = try await send(request)
        guard result.statusCode == 200 else { throw BackendError.http(result.statusCode) }
        guard request.url?.path == "/api/v1/ai/chat/stream",
              let body = try? JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data()),
              let question = body["question"] else { throw BackendError.invalidResponse }
        try ChatProgress.validate(question: question)
        try await onEvent(ChatStreamEvent(name: "metadata", data: "{}"))
        try await onEvent(ChatStreamEvent(name: "context", data: "{}"))
        let answer = "[개발용 모의 응답] ‘\(question)’ 질문을 받았어요. 함께 산책하고 펫에게 먹이를 주며 즐거운 하루를 보내요! 실제 AI 서버에 전송하지 않았어요."
        for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
            try Task.checkCancellation()
            guard request.value(forHTTPHeaderField: "Authorization") == cached?.accessToken.map({ "Bearer \($0)" }) else { throw BackendError.sessionChanged }
            try await Task.sleep(for: .milliseconds(35))
            let data = try JSONEncoder().encode(["token": String(word) + " "])
            try await onEvent(ChatStreamEvent(name: "token", data: String(decoding: data, as: UTF8.self)))
        }
        try await onEvent(ChatStreamEvent(name: "done", data: "{}"))
    }

    private func gameRank(_ request: URLRequest) throws -> BackendHTTPResponse {
        guard let path = request.url?.path,
              let game = MiniGame.allCases.first(where: { path.hasPrefix("/api/v1/\($0.serverPath)/rank/") }) else { return response(404) }
        let operation = path.split(separator: "/").last
        var submitted: GameScore?
        if request.httpMethod == "POST" {
            guard let body = try? JSONDecoder().decode([String: Int].self, from: request.httpBody ?? Data()),
                  let score = body[game == .shooting ? "score" : "maxStep"] else { return response(400) }
            let value = GameScore(game: game, score: score, maxCombo: body["maxCombo"] ?? 0)
            do { try value.validate() } catch { return response(400) }
            submitted = value
        }
        if operation == "score", let score = submitted {
            var next = cached!
            var scores = next.gameScores ?? [:]
            let old = scores[game.rawValue]
            let improves = old == nil || score.score > old!.score || (game == .starStair && score.score == old!.score && score.maxCombo > old!.maxCombo)
            if improves { scores[game.rawValue] = score; next.gameScores = scores; try write(next) }
            return try json(["userId": Self.accountID, "updated": improves])
        }
        var entries: [(Int64, String, Int, Int)] = [(900_000_101,"연습여우",30,20),(900_000_102,"산책친구",15,10),(900_000_103,"초보펫",5,3)]
        entries += (1...15).map { (900_000_200 + Int64($0), "게임친구\($0)", 0, 0) }
        if let best = cached?.gameScores?[game.rawValue] { entries.append((Self.accountID,currentNickname,best.score,best.maxCombo)) }
        entries.sort { $0.2 == $1.2 ? ($0.3 == $1.3 ? $0.0 < $1.0 : $0.3 > $1.3) : $0.2 > $1.2 }
        if (operation == "top10" || operation == "range"), request.httpMethod == "GET" {
            guard let url = request.url, let page = try? (operation == "range" ? rankingPage(url) : RankingPageRequest(page: 1, size: 10)) else { return response(400) }
            let slice = entries.dropFirst((page.page - 1) * page.size).prefix(page.size)
            return try json(["ranks": slice.map { row -> [String: Any] in
                let rank = 1 + entries.filter { $0.2 > row.2 || (game == .starStair && $0.2 == row.2 && $0.3 > row.3) }.count
                var item: [String: Any] = ["rank":rank,"userId":row.0,"userName":row.1]
                if game == .shooting { item["score"] = row.2 } else { item["maxStep"] = row.2; item["maxCombo"] = row.3 }
                return item
            }])
        }
        if operation == "position", let score = submitted {
            let rank = 1 + entries.filter { $0.0 != Self.accountID && ($0.2 > score.score || (game == .starStair && $0.2 == score.score && $0.3 > score.maxCombo)) }.count
            return try json(["userId":Self.accountID,"rank":rank])
        }
        return response(404)
    }

    public func representativeImage() throws -> RepresentativeImage? {
        try load(); try cached!.image?.validate(); return cached!.image
    }
    private func rankingPage(_ url: URL) throws -> RankingPageRequest {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ ["page", "size"].contains($0.name) }),
              let page = Int(items.first { $0.name == "page" }?.value ?? "1"),
              let size = Int(items.first { $0.name == "size" }?.value ?? "10") else { throw BackendError.invalidResponse }
        let value = RankingPageRequest(page: page, size: size); try value.validate(); return value
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
            try value.image?.validate()
            _ = try AccountProfileDetails.imageURL(value.pictureUrl)
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
