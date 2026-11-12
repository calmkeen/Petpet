import Combine
import Foundation
import PetPetCore

@MainActor
final class PetProgressViewModel: ObservableObject {
    @Published private(set) var progress: PetProgress?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let repository: any PetProgressRepository
    private let claimRewards: ClaimStepRewards
    private let waitForMoodRefresh: @MainActor () async throws -> Void
    private var isActive = false
    private var activityGeneration = 0
    private var moodTask: Task<Void, Never>?

    init(repository: any PetProgressRepository, history: any StepHistoryRepository,
         waitForMoodRefresh: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(600)) }) {
        self.repository = repository
        self.waitForMoodRefresh = waitForMoodRefresh
        claimRewards = ClaimStepRewards(history: history, progress: repository)
    }

    func start() async {
        guard !isActive else { return }
        isActive = true
        activityGeneration += 1
        let generation = activityGeneration
        await perform(.visit)
        guard isActive, generation == activityGeneration else { return }
        moodTask = Task { [weak self, waitForMoodRefresh] in
            while !Task.isCancelled {
                do { try await waitForMoodRefresh() } catch { return }
                guard let self, !Task.isCancelled, self.isActive, self.activityGeneration == generation else { return }
                await self.perform(.visit)
            }
        }
    }

    func stop() {
        isActive = false
        activityGeneration += 1
        moodTask?.cancel()
        moodTask = nil
    }

    func retry() async { await perform(.visit) }

    func reload() async {
        do { progress = try await repository.load(); errorMessage = nil; message = nil }
        catch { show(error) }
    }

    func feed(_ food: FoodDefinition) async {
        let oldLevel = progress?.pet.level ?? 1
        await perform(.feed(foodID: food.id)) { change in
            let levelUp = change.progress.pet.level > oldLevel
                ? " · Lv.\(change.progress.pet.level)!" : ""
            return "\(food.name) 냠냠! 경험치 +\(food.improvement)\(levelUp)"
        }
    }

    func allocate(_ statistic: TrainableStatistic) async {
        await perform(.allocate(statistic)) { _ in "능력치가 1 올랐어요." }
    }

    @discardableResult
    func touch() async -> Bool {
        let saved = await perform(.touch) { change in
            change.progress.touchCount == 0
                ? "애정도 +1!" : "쓰다듬기 \(change.progress.touchCount)/50"
        }
        return saved != nil
    }

    func claim(for record: DailyStepRecord) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let change = try await claimRewards(for: record)
            progress = change.progress
            errorMessage = nil
            if let reward = change.reward {
                message = reward.isEmpty ? "오늘 받을 보상을 모두 받았어요."
                    : "우유 +\(reward.milk) · 사과 +\(reward.apple)"
            }
        } catch { show(error) }
    }

    @discardableResult
    private func perform(
        _ action: PetProgressAction,
        feedback: ((PetProgressChange) -> String?)? = nil
    ) async -> PetProgressChange? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let change = try await repository.perform(action)
            progress = change.progress
            errorMessage = nil
            if let feedback { message = feedback(change) }
            return change
        } catch { show(error) }
        return nil
    }

    private func show(_ error: Error) {
        message = nil
        switch error as? PetProgressError {
        case .noFood: errorMessage = "이 먹이를 모두 먹었어요."
        case .noStatPoints: errorMessage = "레벨을 올리면 포인트를 받아요."
        case .outdatedDay: errorMessage = "날짜가 바뀌었어요. 오늘 걸음 수를 확인한 뒤 다시 받아 주세요."
        default: errorMessage = "펫 기록을 불러오거나 저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}
