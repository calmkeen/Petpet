import SwiftUI
import PetPetCore

struct FoodOverviewView: View {
    @ObservedObject var viewModel: PetProgressViewModel
    @ObservedObject var stepViewModel: WatchHomeViewModel
    @ObservedObject var cloudViewModel: WatchCloudController

    var body: some View {
        WatchOverviewLayout { compact in
          VStack(spacing: 4) {
            Text("먹이").font(.headline)
            if let progress = viewModel.progress {
                HStack(spacing: 16) {
                    foodCount("우유", image: "milk_normal1", quantity: progress.quantity(of: 1), compact: compact)
                    foodCount("사과", image: "apple_normal1", quantity: progress.quantity(of: 2), compact: compact)
                }
                if progress.quantity(of: 3) > 0 {
                    Text("고기 \(WatchNumber.compact(progress.quantity(of: 3)))개").font(.caption2)
                }
                let state = stepViewModel.state
                let pending = progress.pendingRewards(for: DailyStepRecord(date: state.date, stepCount: state.stepCount))
                if !compact { Text("보상: 우유 \(WatchNumber.compact(pending.milk)) · 사과 \(WatchNumber.compact(pending.apple))")
                    .font(.caption2).foregroundStyle(.green)
                    .lineLimit(2) }
            }
            NavigationLink {
                FoodInventoryView(viewModel: viewModel, stepViewModel: stepViewModel, cloudViewModel: cloudViewModel)
            } label: {
                Label("먹이 관리", systemImage: "carrot.fill")
            }
            .buttonStyle(WatchActionStyle())
            .accessibilityIdentifier("watch.manageFoodInventory")
        }
        }
    }

    private func foodCount(_ name: String, image: String, quantity: Int64, compact: Bool) -> some View {
        VStack(spacing: 4) {
            if !compact { Image(image).resizable().interpolation(.none)
                .scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true) }
            Text("\(name) \(WatchNumber.compact(quantity))").font(.caption2).monospacedDigit()
                .accessibilityLabel("\(name) \(quantity)개")
        }
    }
}
