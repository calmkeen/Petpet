import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Each authenticated host owns its credentials locally. Parallel requests share
/// refresh work; logout/account changes invalidate every in-flight result.
public actor BackendClient {
    private let baseURL: URL
    private let transport: any BackendHTTPTransport
    private let store: any BackendSessionStore
    private var cached: BackendSession?
    private var loaded = false
    private var epoch = 0
    private var refreshTask: Task<BackendSession, Error>?
    private var refreshID: UUID?
    private var storageTail: Task<Void, Error>?
    private var nicknameTail: Task<String, Error>?
    private var nicknameRevision = 0
    private var pictureRevision = 0
    private var pictureUpdate: (epoch: Int, accountID: String, url: URL, image: RepresentativeImage)?
    private var sessionInvalidationHandler: (@Sendable () async -> Void)?

    public init(baseURL: URL, transport: any BackendHTTPTransport = URLSessionBackendTransport(),
                store: any BackendSessionStore) throws {
        guard baseURL.scheme == "https", baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else { throw BackendError.invalidServerURL }
        self.baseURL = baseURL; self.transport = transport; self.store = store
    }

    public func session() async throws -> BackendSession? {
        if !loaded {
            let token = epoch
            let saved = try await store.load()
            if token == epoch, !loaded {
                cached = saved?.serverOrigin == baseURL.absoluteString ? saved : nil
                loaded = true
            }
        }
        return cached
    }

    public func setSessionInvalidationHandler(_ handler: (@Sendable () async -> Void)?) {
        sessionInvalidationHandler = handler
    }

    private func invalidateSession() async throws {
        defer {
            if cached == nil, let handler = sessionInvalidationHandler {
                // Notify outside the credential write; observers may read the session again.
                Task { await handler() }
            }
        }
        try await signOut()
    }

    @discardableResult
    public func signIn(_ identity: GoogleIdentity) async throws -> BackendSession {
        guard !identity.subject.isEmpty, !identity.idToken.isEmpty else { throw BackendError.invalidResponse }
        epoch += 1
        let token = epoch
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        cached = nil; loaded = true
        try await persist(nil, epoch: token)
        let response = try await send(path: "api/v1/google", body: ["idToken": identity.idToken])
        try checkEpoch(token)
        try requireSuccess(response)
        let auth = try decodeAuth(response.data)
        guard let access = auth.accessToken?.nonBlank else { throw BackendError.invalidResponse }
        let result = BackendSession(
            accountID: auth.userID?.nonBlank ?? "google:\(identity.subject)",
            serverOrigin: baseURL.absoluteString, accessToken: access,
            refreshToken: auth.refreshToken?.nonBlank, email: auth.email ?? identity.email,
            name: auth.name ?? identity.name, nickname: auth.nickname,
            selectedMateID: auth.selectedMateID ?? 1, isNewUser: auth.isNewUser,
            identityProvider: .google, providerSubject: identity.subject
        )
        try await persist(result, epoch: token)
        try checkEpoch(token)
        loaded = true
        return result
    }

    @discardableResult
    public func signIn(_ identity: AppleIdentity) async throws -> BackendSession {
        guard identity.userIdentifier.nonBlank != nil, identity.identityToken.nonBlank != nil,
              identity.authorizationCode.nonBlank != nil, identity.rawNonce.count >= 32 else {
            throw BackendError.invalidAppleCredential
        }
        epoch += 1
        let token = epoch
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        cached = nil; loaded = true
        try await persist(nil, epoch: token)
        let response = try await send(path: "api/v1/auth/apple", method: "POST",
                                      data: JSONEncoder().encode(AppleLoginRequest(identity)))
        try checkEpoch(token)
        if [404, 405, 501].contains(response.statusCode) { throw BackendError.appleLoginUnavailable }
        try requireSuccess(response)
        let auth = try decodeAuth(response.data)
        // Only the backend's internal user ID owns backup/restore data.
        guard let accountID = auth.userID?.nonBlank,
              let access = auth.accessToken?.nonBlank,
              let refresh = auth.refreshToken?.nonBlank else { throw BackendError.invalidResponse }
        let result = BackendSession(accountID: accountID, serverOrigin: baseURL.absoluteString,
                                    accessToken: access, refreshToken: refresh, email: auth.email,
                                    name: auth.name ?? identity.name, nickname: auth.nickname,
                                    selectedMateID: auth.selectedMateID ?? 1, isNewUser: auth.isNewUser,
                                    identityProvider: .apple, providerSubject: identity.userIdentifier)
        try await persist(result, epoch: token)
        try checkEpoch(token)
        loaded = true
        return result
    }

    public func signOut() async throws {
        epoch += 1
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        cached = nil; loaded = true
        try await persist(nil, epoch: epoch)
    }

    #if DEBUG
    @discardableResult
    public func signInForDevelopment() async throws -> BackendSession {
        // No URLSession or production client is allowed to use this route.
        guard baseURL == LocalDevelopmentBackend.baseURL, transport is LocalDevelopmentBackend else {
            throw BackendError.configurationMissing
        }
        epoch += 1
        let token = epoch
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        cached = nil; loaded = true
        try await persist(nil, epoch: token)
        let response = try await send(path: "debug/login", method: "POST", data: nil)
        try checkEpoch(token)
        try requireSuccess(response)
        let auth = try decodeAuth(response.data)
        guard let id = auth.userID?.nonBlank, let access = auth.accessToken?.nonBlank,
              let refresh = auth.refreshToken?.nonBlank else { throw BackendError.invalidResponse }
        let session = BackendSession(accountID: id, serverOrigin: baseURL.absoluteString,
                                     accessToken: access, refreshToken: refresh, email: nil,
                                     name: auth.name, nickname: auth.nickname)
        try await persist(session, epoch: token)
        try checkEpoch(token)
        return session
    }
    #endif

    public func saveBackup(_ request: ServerBackupRequest, accountID: String) async throws {
        _ = try await authorized(path: "api/v1/backup", method: "POST",
                                 data: JSONEncoder().encode(request), accountID: accountID)
    }

    public func profileNickname(accountID: String) async throws -> String? {
        try await profileDetails(accountID: accountID).nickname
    }
    public func profileDetails(accountID: String) async throws -> AccountProfileDetails {
        _ = try await session()
        let token = epoch
        let revision = nicknameRevision
        let imageRevision = pictureRevision
        let data = try await authorized(path: "api/v1/users/me", method: "GET", accountID: accountID)
        let profile: AccountProfileResponse
        do { profile = try JSONDecoder().decode(AccountProfileResponse.self, from: data) }
        catch { throw BackendError.invalidResponse }
        var nickname = profile.nickname
        if revision != nicknameRevision {
            _ = try? await storageTail?.value
            try checkEpoch(token)
            nickname = cached?.nickname
        } else if let nickname { try await persistNickname(nickname, accountID: accountID, epoch: token) }
        var url = try AccountProfileDetails.imageURL(profile.pictureUrl)
        var preview: RepresentativeImage?
        if let saved = pictureUpdate, saved.epoch == token, saved.accountID == accountID,
           imageRevision != pictureRevision || saved.url == url { url = saved.url; preview = saved.image }
        #if DEBUG
        if let local = transport as? LocalDevelopmentBackend, baseURL == LocalDevelopmentBackend.baseURL {
            preview = try await local.representativeImage()
        }
        #endif
        try checkEpoch(token)
        return AccountProfileDetails(nickname: nickname, pictureURL: url, preview: preview)
    }

    public func updatePicture(_ image: RepresentativeImage, accountID: String) async throws -> AccountProfileDetails {
        try image.validate()
        let token = epoch
        let boundary = "PetPet-" + UUID().uuidString
        let body = try image.multipart(boundary: boundary)
        let data = try await authorized(path: "api/v1/users/me/picture", method: "PATCH", data: body,
            accountID: accountID, contentType: "multipart/form-data; boundary=\(boundary)")
        struct Reply: Decodable { let pictureUrl: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let url = try AccountProfileDetails.imageURL(reply.pictureUrl) else { throw BackendError.invalidResponse }
        try checkEpoch(token)
        pictureRevision += 1; pictureUpdate = (token, accountID, url, image)
        return AccountProfileDetails(nickname: cached?.nickname, pictureURL: url, preview: image)
    }

    public func stepRanking(_ page: RankingPageRequest, accountID: String) async throws -> StepRankingPage {
        try page.validate()
        let data = try await authorized(path: "api/v1/stepcounts/ranking", method: "GET", accountID: accountID, query: page.query)
        let value = try JSONDecoder().decode(StepRankingPage.self, from: data)
        guard value.page == page.page, value.size == page.size, value.totalUsers >= 0, value.rankings.count <= page.size,
              value.rankings.allSatisfy({ $0.rank > 0 && $0.userId > 0 && $0.totalStepCount >= 0 && $0.nickname.utf8.count <= 2048 }),
              Set(value.rankings.map(\.userId)).count == value.rankings.count else { throw BackendError.invalidResponse }
        return value
    }
    public func gameRankingPage(_ game: MiniGame, page: RankingPageRequest, accountID: String) async throws -> GameRankingPage {
        try page.validate()
        let data = try await authorized(path: "api/v1/\(game.serverPath)/rank/range", method: "GET", accountID: accountID, query: page.query)
        struct Row: Decodable { let rank: Int; let userId: Int64; let userName: String; let score: Int?; let maxStep: Int?; let maxCombo: Int? }
        struct Reply: Decodable { let ranks: [Row] }
        let rows = try JSONDecoder().decode(Reply.self, from: data).ranks
        guard rows.count <= page.size else { throw BackendError.invalidResponse }
        let entries = try rows.map { row -> GameRankEntry in
            guard let score = game == .shooting ? row.score : row.maxStep,
                  score >= 0, row.rank > 0, row.userId > 0, (row.maxCombo ?? 0) >= 0,
                  row.userName.utf8.count <= 2048 else { throw BackendError.invalidResponse }
            return GameRankEntry(rank: row.rank, userID: row.userId, name: row.userName, score: score, maxCombo: row.maxCombo ?? 0)
        }
        return GameRankingPage(game: game, request: page, entries: entries)
    }

    public func stepHistory(accountID: String) async throws -> [DailyStepRecord] {
        let data = try await authorized(path: "api/v1/stepcounts/me", method: "GET", accountID: accountID)
        let response: ServerStepsResponse
        do { response = try JSONDecoder().decode(ServerStepsResponse.self, from: data) }
        catch { throw BackendError.invalidResponse }
        guard Int64(accountID).map({ $0 == response.userId }) ?? true else { throw BackendError.accountMismatch }
        let records = try response.stepCounts.map { record -> DailyStepRecord in
            guard let count = Int(exactly: record.stepCount) else { throw BackendError.invalidResponse }
            return DailyStepRecord(date: record.date, stepCount: count)
        }
        try ServerRestoreState.validate(pet: PetProgress.newUser(at: Date()).pet, steps: records)
        return records
    }

    /// Read the same backed-up pet that Android mobile displays, without restoring the watch.
    public func petProfile(accountID: String, timeZone: TimeZone = .current) async throws -> PetProfile {
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        guard current.selectedMateID == 1 else { throw BackendError.unsupportedMate }
        let data = try await authorized(path: "api/v1/usermates/\(current.selectedMateID)", method: "GET", accountID: accountID)
        let value: ServerPetResponse
        do { value = try JSONDecoder().decode(ServerPetResponse.self, from: data) }
        catch { throw BackendError.invalidResponse }
        guard Int64(accountID).map({ $0 == value.userId }) ?? true else { throw BackendError.accountMismatch }
        let lastFed: Date?
        if let text = value.lastFedAt, !text.isEmpty {
            guard let parsed = ServerDateTime.date(text, timeZone: timeZone) else { throw BackendError.invalidResponse }
            lastFed = parsed
        } else { lastFed = nil }
        let pet = PetProfile(id: value.mateId, level: value.level, experience: value.experience,
                             affection: value.affection, attack: value.attack, defense: value.defense,
                             health: value.health, mood: value.status, lastFedAt: lastFed, statPoints: 0)
        try ServerRestoreState.validate(pet: pet, steps: [])
        return pet
    }

    public func checkNickname(_ value: String, accountID: String) async throws -> Bool {
        try NicknameRules.validate(value)
        let data = try await authorized(path: "api/v1/users/nickname/check", method: "GET", accountID: accountID,
                                        query: [URLQueryItem(name: "nickname", value: value)])
        let response = try nicknameResponse(data)
        guard response.nickname.utf8.elementsEqual(value.utf8) else { throw BackendError.invalidResponse }
        return !response.duplicated
    }

    public func updateNickname(_ value: String, accountID: String) async throws -> String {
        try NicknameRules.validate(value)
        guard try await session()?.accountID == accountID else { throw BackendError.authenticationRequired }
        let token = epoch
        let previous = nicknameTail
        let task = Task {
            _ = try? await previous?.value
            try self.checkEpoch(token)
            let data: Data
            do {
                data = try await self.authorized(path: "api/v1/users/nickname", method: "PATCH",
                    data: JSONEncoder().encode(["nickname": value]), accountID: accountID)
            } catch BackendError.http(409) { throw BackendError.nicknameUnavailable }
            let response = try self.nicknameResponse(data)
            guard !response.duplicated else { throw BackendError.nicknameUnavailable }
            guard response.nickname.utf8.elementsEqual(value.utf8) else { throw BackendError.invalidResponse }
            try NicknameRules.validate(response.nickname)
            self.nicknameRevision += 1
            try await self.persistNickname(response.nickname, accountID: accountID, epoch: token)
            return response.nickname
        }
        nicknameTail = task
        return try await task.value
    }

    public func restore(accountID: String, timeZone: TimeZone = .current) async throws -> ServerRestoreState {
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        guard current.selectedMateID == 1 else { throw BackendError.unsupportedMate }
        let token = epoch
        async let petData = authorized(path: "api/v1/usermates/\(current.selectedMateID)", method: "GET", accountID: accountID)
        async let stepsData = authorized(path: "api/v1/stepcounts/me", method: "GET", accountID: accountID)
        let petResponse: Data
        let stepsResponse: Data
        do { (petResponse, stepsResponse) = try await (petData, stepsData) }
        catch BackendError.http(404) { throw BackendError.noBackup }
        try checkEpoch(token)
        let pet = try JSONDecoder().decode(ServerPetResponse.self, from: petResponse)
        let steps = try JSONDecoder().decode(ServerStepsResponse.self, from: stepsResponse)
        guard pet.userId == steps.userId,
              Int64(accountID).map({ $0 == pet.userId }) ?? true else { throw BackendError.accountMismatch }
        let lastFed: Date?
        if let text = pet.lastFedAt, !text.isEmpty {
            guard let date = ServerDateTime.date(text, timeZone: timeZone) else { throw BackendError.invalidResponse }
            lastFed = date
        } else { lastFed = nil }
        let profile = PetProfile(id: pet.mateId, level: pet.level, experience: pet.experience,
                                 affection: pet.affection, attack: pet.attack, defense: pet.defense,
                                 health: pet.health, mood: pet.status, lastFedAt: lastFed, statPoints: 0)
        let records = try steps.stepCounts.map { item -> DailyStepRecord in
            guard let count = Int(exactly: item.stepCount) else { throw BackendError.invalidResponse }
            return DailyStepRecord(date: item.date, stepCount: count)
        }
        return try ServerRestoreState(accountID: accountID, pet: profile, steps: records)
    }

    public func ranking(_ game: MiniGame, submitting score: GameScore? = nil, accountID: String) async throws -> GameRanking {
        let path = "api/v1/\(game.serverPath)/rank/"
        let token = epoch
        var position: Int?
        if let score {
            guard score.game == game else { throw BackendError.invalidResponse }
            try score.validate()
            let body = try JSONEncoder().encode(score.requestBody)
            _ = try await authorized(path: path + "score", method: "POST", data: body, accountID: accountID)
            let data = try await authorized(path: path + "position", method: "POST", data: body, accountID: accountID)
            struct Position: Decodable { let rank: Int; let userId: Int64 }
            guard let value = try? JSONDecoder().decode(Position.self, from: data), value.rank > 0,
                  Int64(accountID).map({ $0 == value.userId }) ?? true else { throw BackendError.invalidResponse }
            position = value.rank
        }
        let data = try await authorized(path: path + "top10", method: "GET", accountID: accountID)
        struct Row: Decodable { let rank: Int?; let userId: Int64?; let userName: String?; let score: Int?; let maxStep: Int?; let maxCombo: Int? }
        struct Rows: Decodable { let ranks: [Row] }
        guard let rows = try? JSONDecoder().decode(Rows.self, from: data), rows.ranks.count <= 10 else { throw BackendError.invalidResponse }
        let entries = try rows.ranks.enumerated().map { index, row -> GameRankEntry in
            let score = (game == .shooting ? row.score : row.maxStep) ?? 0
            guard score >= 0, (row.maxCombo ?? 0) >= 0, (row.rank ?? index + 1) > 0 else { throw BackendError.invalidResponse }
            return GameRankEntry(rank: row.rank ?? index + 1, userID: row.userId, name: String((row.userName ?? "이름 없음").prefix(255)), score: score, maxCombo: row.maxCombo ?? 0)
        }
        try checkEpoch(token)
        return GameRanking(game: game, position: position, entries: entries)
    }

    public func streamChat(question: String, accountID: String,
                           onEvent: @escaping @Sendable (ChatStreamEvent) async throws -> Void) async throws {
        try ChatProgress.validate(question: question)
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        guard let streaming = transport as? any BackendChatTransport else { throw BackendError.configurationMissing }
        let token = epoch
        var access = current.accessToken
        for attempt in 0...1 {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/ai/chat/stream"))
            request.httpMethod = "POST"; request.timeoutInterval = 120
            request.httpBody = try JSONEncoder().encode(["question": question])
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            do {
                try await streaming.stream(request) { event in
                    try await self.checkEpoch(token)
                    try Task.checkCancellation()
                    try await onEvent(event)
                }
                try checkEpoch(token)
                return
            } catch let BackendError.http(code) where code == 401 || code == 403 {
                try checkEpoch(token)
                guard attempt == 0 else { try await invalidateSession(); throw BackendError.authenticationRequired }
                access = try await refresh(rejectedToken: access, epoch: token).accessToken
            }
        }
    }

    private func authorized(path: String, method: String, data: Data? = nil, accountID: String,
                            query: [URLQueryItem] = [], contentType: String = "application/json") async throws -> Data {
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        let token = epoch
        var response = try await send(path: path, method: method, data: data, bearer: current.accessToken, query: query, contentType: contentType)
        try checkEpoch(token)
        if response.statusCode == 401 || response.statusCode == 403 {
            let renewed = try await refresh(rejectedToken: current.accessToken, epoch: token)
            try checkEpoch(token)
            response = try await send(path: path, method: method, data: data, bearer: renewed.accessToken, query: query, contentType: contentType)
            try checkEpoch(token)
            if response.statusCode == 401 || response.statusCode == 403 {
                try await invalidateSession()
                throw BackendError.authenticationRequired
            }
        }
        try requireSuccess(response)
        return response.data
    }

    private func refresh(rejectedToken: String, epoch token: Int) async throws -> BackendSession {
        try checkEpoch(token)
        guard let current = cached else { throw BackendError.authenticationRequired }
        if current.accessToken != rejectedToken { return current }
        if let refreshTask {
            let result = try await refreshTask.value
            try checkEpoch(token)
            return result
        }
        guard let refreshToken = current.refreshToken?.nonBlank else {
            try await invalidateSession(); throw BackendError.authenticationRequired
        }
        let identifier = UUID()
        refreshID = identifier
        let task = Task { [transport, baseURL] in
            var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refreshToken": refreshToken])
            var response = try await transport.send(request)
            if response.statusCode == 404 || response.statusCode == 405 {
                request.url = baseURL.appendingPathComponent("api/v1/refresh")
                response = try await transport.send(request)
            }
            if response.statusCode == 401 || response.statusCode == 403 { throw BackendError.authenticationRequired }
            guard (200..<300).contains(response.statusCode) else { throw BackendError.http(response.statusCode) }
            let auth = try JSONDecoder().decode(BackendAuthResponse.self, from: response.data)
            guard let access = auth.accessToken?.nonBlank else { throw BackendError.invalidResponse }
            if let identity = auth.userID?.nonBlank, identity != current.accountID,
               !current.accountID.hasPrefix("google:") { throw BackendError.accountMismatch }
            let result = BackendSession(accountID: current.accountID, serverOrigin: current.serverOrigin,
                                  accessToken: access, refreshToken: auth.refreshToken?.nonBlank ?? current.refreshToken,
                                  email: auth.email ?? current.email, name: auth.name ?? current.name,
                                  nickname: auth.nickname ?? current.nickname, selectedMateID: current.selectedMateID,
                                  isNewUser: current.isNewUser, identityProvider: current.identityProvider,
                                  providerSubject: current.providerSubject)
            try self.checkEpoch(token)
            try await self.persist(result, epoch: token, preservingNickname: true)
            try self.checkEpoch(token)
            return self.cached ?? result
        }
        refreshTask = task
        do {
            let result = try await task.value
            try checkEpoch(token)
            if refreshID == identifier { refreshTask = nil; refreshID = nil }
            return result
        } catch {
            if token == epoch {
                if refreshID == identifier { refreshTask = nil; refreshID = nil }
                if error as? BackendError == .authenticationRequired { try await invalidateSession() }
            }
            throw error
        }
    }

    private func send(path: String, body: [String: String]) async throws -> BackendHTTPResponse {
        try await send(path: path, method: "POST", data: JSONEncoder().encode(body))
    }

    private func send(path: String, method: String, data: Data?, bearer: String? = nil,
                      query: [URLQueryItem] = [], contentType: String = "application/json") async throws -> BackendHTTPResponse {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidServerURL
        }
        if !query.isEmpty {
            components.queryItems = query
            // Servlet query decoders treat a bare '+' as a space, while
            // URLComponents follows RFC 3986. Preserve literal nickname '+'.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw BackendError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await transport.send(request)
    }

    private func checkEpoch(_ value: Int) throws {
        guard value == epoch else { throw BackendError.sessionChanged }
    }

    private func persist(_ session: BackendSession?, epoch token: Int, preservingNickname: Bool = false) async throws {
        let previous = storageTail
        let task = Task { [store] in
            _ = try? await previous?.value
            try self.checkEpoch(token)
            var next = session
            if preservingNickname, let nickname = self.cached?.nickname { next = next?.replacingNickname(nickname) }
            if let next { try await store.save(next) }
            else { try await store.clear() }
            try self.checkEpoch(token)
            self.cached = next
        }
        storageTail = task
        try await task.value
        try checkEpoch(token)
    }

    private func persistNickname(_ nickname: String, accountID: String, epoch token: Int) async throws {
        let previous = storageTail
        let task = Task { [store] in
            _ = try? await previous?.value
            try self.checkEpoch(token)
            guard let latest = self.cached, latest.accountID == accountID else { throw BackendError.sessionChanged }
            let updated = latest.replacingNickname(nickname)
            try await store.save(updated)
            try self.checkEpoch(token)
            self.cached = updated
        }
        storageTail = task
        try await task.value
        try checkEpoch(token)
    }

    private func nicknameResponse(_ data: Data) throws -> NicknameResponse {
        do { return try JSONDecoder().decode(NicknameResponse.self, from: data) }
        catch { throw BackendError.invalidResponse }
    }
    private func requireSuccess(_ response: BackendHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else { throw BackendError.http(response.statusCode) }
    }
    private func decodeAuth(_ data: Data) throws -> BackendAuthResponse {
        do { return try JSONDecoder().decode(BackendAuthResponse.self, from: data) }
        catch { throw BackendError.invalidResponse }
    }
}

private extension String {
    var nonBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
