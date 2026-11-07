import SwiftUI
import PetPetCore

struct FoodOverviewView: View {
    @ObservedObject var viewModel: PetProgressViewModel
    @ObservedObject var stepViewModel: WatchHomeViewModel
    @ObservedObject var cloudViewModel: WatchCloudController

    var body: some View {
        VStack(spacing: 8) {
            Text("먹이").font(.headline)
            if let progress = viewModel.progress {
                HStack(spacing: 16) {
                    foodCount("우유", image: "milk_normal1", quantity: progress.quantity(of: 1))
                    foodCount("사과", image: "apple_normal1", quantity: progress.quantity(of: 2))
                }
                if progress.quantity(of: 3) > 0 {
                    Text("고기 \(progress.quantity(of: 3))개").font(.caption2)
                }
                let state = stepViewModel.state
                let pending = progress.pendingRewards(for: DailyStepRecord(date: state.date, stepCount: state.stepCount))
                Text("받을 보상: 우유 \(pending.milk) · 사과 \(pending.apple)")
                    .font(.caption2).foregroundStyle(.green)
                    .minimumScaleFactor(0.8).lineLimit(1)
            }
            NavigationLink {
                FoodInventoryView(viewModel: viewModel, stepViewModel: stepViewModel, cloudViewModel: cloudViewModel)
            } label: {
                Label("먹이·보상 관리", systemImage: "carrot.fill")
            }
            .accessibilityIdentifier("watch.manageFoodInventory")
        }
        .padding(.horizontal, 18)
        .accessibilityIdentifier("watch.foodOverview")
    }

    private func foodCount(_ name: String, image: String, quantity: Int64) -> some View {
        VStack(spacing: 4) {
            Image(image).resizable().interpolation(.none)
                .scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            Text("\(name) \(quantity)개").font(.caption2).monospacedDigit()
        }
    }
}
