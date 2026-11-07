import Combine
import Foundation
import PetPetCore
import PetPetConnectivity

@MainActor
final class WatchSyncController: ObservableObject {
    private let transport: WatchConnectivityTransport
    private let publisher: WatchSnapshotPublisher
    private let home: WatchHomeViewModel
    private var subscriptions = Set<AnyCancellable>()
    private var scheduled: Task<Void, Never>?

    init(home: WatchHomeViewModel, pet: PetProgressViewModel,
         history: any StepHistoryRepository, progress: any PetProgressRepository, outboxURL: URL,
         transport: WatchConnectivityTransport) {
        self.home = home
        self.transport = transport
        let publisher = WatchSnapshotPublisher(
            history: history, progress: progress,
            outbox: FileWatchSnapshotOutbox(fileURL: outboxURL), transport: transport,
            beforeReading: {
                await home.flush()
                guard !home.state.hasStorageError else { throw StepHistoryStoreError.invalidRecord }
            }
        )
        self.publisher = publisher
        transport.onSnapshotRequest = { [weak publisher] in
            guard let publisher else { throw SnapshotSyncError.counterpartUnavailable }
            return try WatchSnapshotCodec.encode(await publisher.publish())
        }
        transport.onConnectionChange = { [weak self] status in
            if status.isActivated { self?.schedule() }
        }
        home.$state
            .filter { !$0.isLoading && !$0.hasStorageError }
            .map { DailyStepRecord(date: $0.date, stepCount: $0.stepCount) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.schedule() }
            .store(in: &subscriptions)
        pet.$progress.compactMap { $0 }
            .removeDuplicates { $0.pet == $1.pet && $0.inventory == $1.inventory }
            .sink { [weak self] _ in self?.schedule() }
            .store(in: &subscriptions)
        home.onRecordsReady = { [weak self] in self?.schedule() }
        transport.activate()
    }

    private func schedule() {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self else { return }
            self.scheduled = nil
            do {
                try await self.publisher.publish()
                self.home.setSyncError(nil)
            } catch {
                self.home.setSyncError("아이폰 동기화를 완료하지 못했어요. 다음 연결 때 다시 시도해요.")
            }
        }
    }
}
