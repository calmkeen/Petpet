import SwiftUI
import PetPetCore

struct FoodInventoryView: View {
    @ObservedObject var viewModel: PetProgressViewModel
    @ObservedObject var stepViewModel: WatchHomeViewModel
    @ObservedObject var cloudViewModel: WatchCloudController

    private var steps: DailyStepState { stepViewModel.state }

    private var record: DailyStepRecord {
        DailyStepRecord(date: steps.date, stepCount: steps.stepCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("먹이 주기").font(.headline)
                PetProgressFeedback(viewModel: viewModel)
                if let progress = viewModel.progress {
                    if progress.inventory.isEmpty {
                        Text("먹이가 없어요.\n아래에서 걸음수 보상을 받아요.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    ForEach(progress.inventory) { item in
                        if let food = FoodCatalog.food(id: item.foodID) {
                            foodRow(food, quantity: item.quantity)
                        }
                    }
                    Divider()
                    Text("오늘의 보상").font(.headline)
                    Text("오늘 \(steps.stepCount.formatted())걸음")
                        .font(.caption).monospacedDigit()
                    Text("1,000걸음마다 우유 1개\n하루 한 번 사과 1개")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    let pending = progress.pendingRewards(for: record)
                    Text("우유 \(pending.milk)개 · 사과 \(pending.apple)개")
                        .font(.caption).foregroundStyle(.green)
                    Button(cloudViewModel.isDevelopment ? "모의 백업·보상 받기" : "서버 백업·보상 받기") {
                        Task { await cloudViewModel.requestBackup() }
                    }
                    .disabled(viewModel.isBusy || cloudViewModel.isBusy || steps.isLoading || cloudViewModel.account == nil)
                    .accessibilityIdentifier("watch.claimStepRewards")
                    if cloudViewModel.account == nil {
                        Text(cloudViewModel.isDevelopment ? "아이폰의 개발용 계정으로 로그인하면 모의 백업을 테스트할 수 있어요." : "아이폰에서 로그인하면 서버 백업 후 보상을 받아요.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let message = cloudViewModel.message {
                        Text(message).font(.caption2).multilineTextAlignment(.center)
                            .accessibilityIdentifier("watch.cloudFeedback")
                    }
                    if pending.isEmpty {
                        Text("다음 1,000걸음 보상을 향해 걸어요.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        }
    }

    private func foodRow(_ food: FoodDefinition, quantity: Int64) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                if food.id == 3 {
                    // Android's meat drawable is absent; preserve a visible fallback.
                    Image(systemName: "fork.knife").frame(width: 40, height: 40)
                } else {
                    Image(food.imageName).resizable().interpolation(.none)
                        .scaledToFit().frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading) {
                    Text("\(food.name) \(quantity)개").font(.headline).accessibilityIdentifier("watch.foodQuantity.\(food.id)")
                    Text(food.description).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button("\(food.name) 먹이기") { Task { await viewModel.feed(food) } }
                .disabled(viewModel.isBusy || quantity == 0)
                .accessibilityIdentifier("watch.feedFood.\(food.id)")
        }
    }
}
