import Foundation

/// Tokens stay on the phone. The watch polls bounded text snapshots while URLSession streams.
@MainActor public final class PhoneFeatureCoordinator {
    private struct ChatJob { let accountID: String; var progress: ChatProgress; var touchedAt: Date; let task: Task<Void, Never> }
    private let backend: BackendClient
    private let environment: CloudEnvironment
    private var jobs: [UUID: ChatJob] = [:]
    public init(backend: BackendClient, transport: any CompanionFeatureTransport, environment: CloudEnvironment) {
        self.backend = backend; self.environment = environment
        transport.onFeatureRequest = { [weak self] data in
            guard let self else { throw BackendError.watchUnavailable }
            return try await self.receive(data)
        }
    }
    public func accountChanged() { for job in jobs.values { job.task.cancel() }; jobs.removeAll() }
    private func receive(_ data: Data) async throws -> Data {
        guard data.count <= 60_000 else { throw BackendError.transferTooLarge }
        let request = try JSONDecoder().decode(CompanionFeatureRequest.self, from: data)
        guard request.environment == environment else { throw BackendError.environmentMismatch }
        var result: CompanionFeatureReply.Result
        do {
            guard try await backend.session()?.accountID == request.accountID else { throw BackendError.authenticationRequired }
            prune()
            switch request.action {
            case let .ranking(game): result = .ranking(try await backend.ranking(game, accountID: request.accountID))
            case let .submit(score): result = .ranking(try await backend.ranking(score.game, submitting: score, accountID: request.accountID))
            case let .startChat(id, question):
                try ChatProgress.validate(question: question)
                if let job = jobs[id] {
                    guard job.accountID == request.accountID else { throw BackendError.sessionChanged }
                    result = .accepted
                } else {
                    guard jobs.count < 4 else { throw BackendError.operationExpired }
                    let task = Task { [weak self, backend] in
                        do {
                            try await backend.streamChat(question: question, accountID: request.accountID) { [weak self] event in
                                try await self?.receive(event, jobID: id, accountID: request.accountID)
                            }
                            self?.end(id)
                        } catch is CancellationError { self?.fail(id, message: "응답을 중단했어요") }
                        catch { self?.fail(id, message: (error as? BackendError ?? .network).localizedDescription) }
                    }
                    jobs[id] = ChatJob(accountID: request.accountID, progress: ChatProgress(), touchedAt: Date(), task: task)
                    result = .accepted
                }
            case let .pollChat(id):
                guard var job = jobs[id], job.accountID == request.accountID else { throw BackendError.operationExpired }
                job.touchedAt = Date(); jobs[id] = job; result = .chat(job.progress)
            case let .cancelChat(id):
                if let job = jobs[id], job.accountID == request.accountID { job.task.cancel(); jobs.removeValue(forKey: id) }
                result = .accepted
            }
            guard try await backend.session()?.accountID == request.accountID else { throw BackendError.sessionChanged }
        } catch { result = .failure(ProfileFailure(error)) }
        let reply = try JSONEncoder().encode(CompanionFeatureReply(request: request, result: result))
        guard reply.count <= 60_000 else { throw BackendError.transferTooLarge }
        return reply
    }
    private func receive(_ event: ChatStreamEvent, jobID: UUID, accountID: String) async throws {
        guard try await backend.session()?.accountID == accountID, var job = jobs[jobID], job.accountID == accountID else { throw BackendError.sessionChanged }
        guard Date().timeIntervalSince(job.touchedAt) < 20 else { throw CancellationError() }
        try job.progress.receive(event); jobs[jobID] = job
    }
    private func end(_ id: UUID) { jobs[id]?.progress.end() }
    private func fail(_ id: UUID, message: String) { jobs[id]?.progress.fail(message) }
    private func prune() {
        for (id, job) in jobs where Date().timeIntervalSince(job.touchedAt) > 120 { job.task.cancel(); jobs.removeValue(forKey: id) }
    }
}
