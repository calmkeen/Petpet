import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The iPhone is the sole owner of server credentials. Parallel requests share
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
            selectedMateID: auth.selectedMateID ?? 1, isNewUser: auth.isNewUser
        )
        try await persist(result, epoch: token)
        try checkEpoch(token)
        cached = result; loaded = true
        return result
    }

    public func signOut() async throws {
        epoch += 1
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        cached = nil; loaded = true
        try await persist(nil, epoch: epoch)
    }

    public func saveBackup(_ request: ServerBackupRequest, accountID: String) async throws {
        _ = try await authorized(path: "api/v1/backup", method: "POST",
                                 data: JSONEncoder().encode(request), accountID: accountID)
    }

    public func restore(accountID: String, timeZone: TimeZone = .current) async throws -> ServerRestoreState {
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        guard current.selectedMateID == 1 else { throw BackendError.unsupportedMate }
        let token = epoch
        async let petData = authorized(path: "api/v1/usermates/\(current.selectedMateID)", method: "GET", accountID: accountID)
        async let stepsData = authorized(path: "api/v1/stepcounts/me", method: "GET", accountID: accountID)
        let (petResponse, stepsResponse) = try await (petData, stepsData)
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

    private func authorized(path: String, method: String, data: Data? = nil, accountID: String) async throws -> Data {
        guard let current = try await session(), current.accountID == accountID else { throw BackendError.authenticationRequired }
        let token = epoch
        var response = try await send(path: path, method: method, data: data, bearer: current.accessToken)
        try checkEpoch(token)
        if response.statusCode == 401 || response.statusCode == 403 {
            let renewed = try await refresh(rejectedToken: current.accessToken, epoch: token)
            try checkEpoch(token)
            response = try await send(path: path, method: method, data: data, bearer: renewed.accessToken)
            try checkEpoch(token)
            if response.statusCode == 401 || response.statusCode == 403 {
                try await signOut()
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
            try await signOut(); throw BackendError.authenticationRequired
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
                                  isNewUser: current.isNewUser)
            try self.checkEpoch(token)
            try await self.persist(result, epoch: token)
            try self.checkEpoch(token)
            self.cached = result
            return result
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
                if error as? BackendError == .authenticationRequired { try await signOut() }
            }
            throw error
        }
    }

    private func send(path: String, body: [String: String]) async throws -> BackendHTTPResponse {
        try await send(path: path, method: "POST", data: JSONEncoder().encode(body))
    }

    private func send(path: String, method: String, data: Data?, bearer: String? = nil) async throws -> BackendHTTPResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await transport.send(request)
    }

    private func checkEpoch(_ value: Int) throws {
        guard value == epoch else { throw BackendError.sessionChanged }
    }

    private func persist(_ session: BackendSession?, epoch token: Int) async throws {
        let previous = storageTail
        let task = Task { [store] in
            _ = try? await previous?.value
            try self.checkEpoch(token)
            if let session { try await store.save(session) }
            else { try await store.clear() }
        }
        storageTail = task
        try await task.value
        try checkEpoch(token)
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
