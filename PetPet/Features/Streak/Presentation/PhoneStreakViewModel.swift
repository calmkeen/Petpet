import Combine
import Foundation
import PetPetCore

@MainActor
final class PhoneStreakViewModel: ObservableObject {
    @Published private(set) var summary = StepStreak(records: [], anchor: .latestRecord)
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let backend: BackendClient?
    private let cache: FileAccountStepCache?
    private var accountID: String?
    private var generation = 0
    private var lastLoadedAt: TimeInterval?
    private var lastLoadedDay: String?
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    init(backend: BackendClient? = nil, cache: FileAccountStepCache? = nil,
         now: @escaping () -> Date = { Date() },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend; self.cache = cache; self.now = now; self.uptime = uptime
        summary = StepStreak(records: [], date: now(), anchor: .latestRecord)
    }

    func refresh(accountID: String?, force: Bool = false) async {
        if self.accountID != accountID {
            self.accountID = accountID; summary = StepStreak(records: [], date: now(), anchor: .latestRecord); error = nil; lastLoadedAt = nil; lastLoadedDay = nil
        }
        guard let accountID, let backend else { generation += 1; isLoading = false; return }
        refreshDate()
        if !force, lastLoadedDay == summary.today, let lastLoadedAt, uptime() - lastLoadedAt < 30 { return }
        generation += 1; let token = generation
        isLoading = true
        if let saved = try? await cache?.load(accountID: accountID), token == generation { summary = StepStreak(records: saved, date: now(), anchor: .latestRecord) }
        do {
            let records = try await backend.stepHistory(accountID: accountID)
            guard token == generation else { return }
            summary = StepStreak(records: records, date: now(), anchor: .latestRecord); error = nil; lastLoadedAt = uptime(); lastLoadedDay = summary.today
            do { try await cache?.save(records, accountID: accountID) }
            catch { if token == generation { self.error = "최신 기록을 불러왔지만 아이폰에 저장하지 못했어요." } }
        } catch {
            if token == generation { self.error = "백업 기록을 불러오지 못했어요. 마지막 기록을 표시해요." }
        }
        if token == generation { isLoading = false }
    }

    func refreshDate() {
        summary = StepStreak(records: summary.counts.map { DailyStepRecord(date: $0.key, stepCount: $0.value) }, date: now(), anchor: .latestRecord)
    }

    var weeks: [[String?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let end = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -364, to: end)!
        let weekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: start) - 1), to: start)!
        var cursor = weekStart
        var weeks: [[String?]] = []
        while cursor <= end {
            var week: [String?] = []
            for _ in 0..<7 {
                week.append(cursor >= start && cursor <= end ? StepDay(containing: cursor, calendar: calendar).date : nil)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            weeks.append(week)
        }
        return weeks
    }
}
