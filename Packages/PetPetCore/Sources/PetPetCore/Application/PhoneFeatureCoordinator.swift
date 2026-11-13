import Foundation

/// Streams on the credential-owning host. A local or companion transport polls
/// bounded snapshots; credentials never enter the request/reply envelopes.
@MainActor public final class PhoneFeatureCoordinator {
    public var onSessionInvalidated: (() async -> Void)?
    private struct ChatJob {
        let generation: UUID
        let accountID: String
        var progress: ChatProgress
        var touchedAt: Date
        var task: Task<Void, Never>?
    }
    private struct CancelledChat { let accountID: String; let date: Date }
    private let backend: BackendClient
    private let environment: CloudEnvironment
    private var jobs: [UUID: ChatJob] = [:]
    private var cancelled: [UUID: CancelledChat] = [:]
    public init(backend: BackendClient, transport: any CompanionFeatureTransport, environment: CloudEnvironment) {
        self.backend = backend; self.environment = environment
        transport.onFeatureRequest = { [weak self] data in
            guard let self else { throw BackendError.watchUnavailable }
            return try await self.receive(data)
        }
    }
    public func accountChanged() {
        for job in jobs.values { job.task?.cancel() }
        jobs.removeAll(); cancelled.removeAll()
    }
    private func receive(_ data: Data) async throws -> Data {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        guard request.environment == environment else { throw BackendError.environmentMismatch }
        var result: CompanionFeatureReply.Result
        do {
            guard try await backend.session()?.accountID == request.accountID else { throw BackendError.authenticationRequired }
            prune()
            switch request.action {
            case .profile: result = .profile(try await backend.profileDetails(accountID: request.accountID))
            case let .updatePicture(image): result = .profile(try await backend.updatePicture(image, accountID: request.accountID))
            case let .stepPage(page): result = .stepPage(try await backend.stepRanking(page, accountID: request.accountID))
            case let .gamePage(game, page): result = .gamePage(try await backend.gameRankingPage(game, page: page, accountID: request.accountID))
            case let .ranking(game): result = .ranking(try await backend.ranking(game, accountID: request.accountID))
            case let .submit(score): result = .ranking(try await backend.ranking(score.game, submitting: score, accountID: request.accountID))
            case let .startChat(id, question):
                try ChatProgress.validate(question: question)
                // sendMessage cancellation cannot retract an already sent start.
                guard cancelled[id]?.accountID != request.accountID else { throw BackendError.operationExpired }
                if let job = jobs[id] {
                    guard job.accountID == request.accountID else { throw BackendError.sessionChanged }
                    result = .accepted
                } else {
                    guard jobs.values.filter({ !$0.progress.finished }).count < 4 else { throw BackendError.operationExpired }
                    let generation = UUID()
                    let task = Task { [weak self, backend] in
                        do {
                            try await backend.streamChat(question: question, accountID: request.accountID) { [weak self] event in
                                try await self?.receive(event, jobID: id, generation: generation, accountID: request.accountID)
                            }
                            self?.end(id, generation: generation)
                        } catch is CancellationError { self?.fail(id, generation: generation, message: "응답을 중단했어요") }
                        catch {
                            self?.fail(id, generation: generation, message: (error as? BackendError ?? .network).localizedDescription)
                            await self?.notifySessionChange(expected: request.accountID)
                        }
                    }
                    jobs[id] = ChatJob(generation: generation, accountID: request.accountID, progress: ChatProgress(), touchedAt: Date(), task: task)
                    result = .accepted
                }
            case let .pollChat(id):
                guard var job = jobs[id], job.accountID == request.accountID else { throw BackendError.operationExpired }
                job.touchedAt = Date(); jobs[id] = job; result = .chat(job.progress)
            case let .cancelChat(id):
                if let job = jobs[id], job.accountID == request.accountID { job.task?.cancel(); jobs.removeValue(forKey: id) }
                cancelled[id] = CancelledChat(accountID: request.accountID, date: Date())
                result = .accepted
            }
            guard try await backend.session()?.accountID == request.accountID else { throw BackendError.sessionChanged }
        } catch {
            result = .failure(ProfileFailure(error))
            await notifySessionChange(expected: request.accountID)
        }
        let reply = try JSONEncoder().encode(CompanionFeatureReply(request: request, result: result))
        guard reply.count <= 60_000 else { throw BackendError.transferTooLarge }
        return reply
    }
    private func receive(_ event: ChatStreamEvent, jobID: UUID, generation: UUID, accountID: String) async throws {
        guard try await backend.session()?.accountID == accountID else { throw BackendError.sessionChanged }
        guard var job = jobs[jobID], job.accountID == accountID, job.generation == generation else { throw CancellationError() }
        guard Date().timeIntervalSince(job.touchedAt) < 20 else { throw CancellationError() }
        try job.progress.receive(event); jobs[jobID] = job
    }
    private func end(_ id: UUID, generation: UUID) {
        guard jobs[id]?.generation == generation else { return }
        jobs[id]?.progress.end(); jobs[id]?.task = nil
    }
    private func notifySessionChange(expected accountID: String) async {
        do {
            if try await backend.session()?.accountID != accountID { await onSessionInvalidated?() }
        } catch { /* A storage error does not prove the session was revoked. */ }
    }
    private func fail(_ id: UUID, generation: UUID, message: String) {
        guard jobs[id]?.generation == generation else { return }
        jobs[id]?.progress.fail(message); jobs[id]?.task = nil
    }
    private func prune() {
        let now = Date()
        for (id, job) in jobs where now.timeIntervalSince(job.touchedAt) > (job.progress.finished ? 120 : 20) {
            job.task?.cancel(); jobs.removeValue(forKey: id)
        }
        let completed = jobs.filter { $0.value.progress.finished }.sorted { $0.value.touchedAt < $1.value.touchedAt }
        for entry in completed.prefix(max(0,completed.count-8)) { jobs.removeValue(forKey:entry.key) }
        for (id, value) in cancelled where now.timeIntervalSince(value.date) > 120 { cancelled.removeValue(forKey:id) }
        for entry in cancelled.sorted(by:{ $0.value.date < $1.value.date }).prefix(max(0,cancelled.count-64)) {
            cancelled.removeValue(forKey:entry.key)
        }
    }
}
