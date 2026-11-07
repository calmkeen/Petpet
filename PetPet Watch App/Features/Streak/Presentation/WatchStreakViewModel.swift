import Combine
import Foundation
import PetPetCore

@MainActor
final class WatchStreakViewModel: ObservableObject {
    @Published private(set) var summary = StepStreak(records: [])
    @Published private(set) var month = StepMonth(containing: Date())
    @Published private(set) var selectedDay = Calendar(identifier: .gregorian).component(.day, from: Date())
    @Published private(set) var error: String?
    private let history: any StepHistoryRepository
    private let home: WatchHomeViewModel
    private var subscription: AnyCancellable?
    private var scheduled: Task<Void, Never>?
    private var generation = 0
    private var viewers = 0

    init(history: any StepHistoryRepository, home: WatchHomeViewModel) {
        self.history = history; self.home = home
        subscription = home.$state
            .removeDuplicates { $0.date == $1.date && $0.stepCount == $1.stepCount && $0.hasStorageError == $1.hasStorageError }
            .sink { [weak self] _ in self?.schedule() }
    }
    func appear() async { viewers += 1; await refresh() }
    func disappear() { viewers = max(0, viewers - 1); if viewers == 0 { scheduled?.cancel() } }
    func refresh() async {
        generation += 1; let token = generation
        do {
            await home.flush()
            guard !home.state.hasStorageError else { throw BackendError.storage }
            let records = try await history.allRecords()
            guard token == generation, !Task.isCancelled else { return }
            let wasCurrent = month.datePrefix == String(summary.today.prefix(7))
            summary = StepStreak(records: records)
            if wasCurrent, month.datePrefix != String(summary.today.prefix(7)) { select(StepMonth(containing: Date())) }
            error = nil
        } catch { if token == generation { self.error = "걸음 기록을 불러오지 못했어요. 다시 시도해 주세요." } }
    }
    func select(_ value: StepMonth) {
        month = value
        selectedDay = value == StepMonth(containing: Date()) ? Calendar(identifier: .gregorian).component(.day, from: Date()) : 1
    }
    func moveMonth(_ offset: Int) { if let value = month.adding(offset) { select(value) } }
    func selectDay(_ day: Int) { selectedDay = min(max(day, 1), month.dayCount) }
    var selectedCount: Int { summary.counts[month.dateKey(day: selectedDay)] ?? 0 }
    var years: ClosedRange<Int> {
        let current = Calendar(identifier: .gregorian).component(.year, from: Date())
        let stored = summary.counts.keys.compactMap { Int($0.prefix(4)) }
        return max(1, min(stored.min() ?? current, current - 5))...min(9999, max(stored.max() ?? current, current + 5))
    }
    private func schedule() {
        guard viewers > 0 else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await self?.refresh()
        }
    }
}
