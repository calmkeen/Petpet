import SwiftUI
import PetPetCore

struct PetOverviewView: View {
    @ObservedObject var viewModel: PetProgressViewModel

    var body: some View {
        WatchOverviewLayout { compact in
          VStack(spacing: 4) {
            Text("성장").font(.headline)
            if let progress = viewModel.progress {
                Text("Lv.\(WatchNumber.compact(progress.pet.level))").accessibilityLabel("레벨 \(progress.pet.level)").font(.title2.bold()).lineLimit(1)
                ProgressView(value: Double(progress.pet.experience), total: Double(progress.experienceRequired))
                    .tint(.green)
                if !compact { Text("XP \(WatchNumber.compact(progress.pet.experience)) / \(WatchNumber.compact(progress.experienceRequired))")
                    .accessibilityLabel("경험치 \(progress.pet.experience) / \(progress.experienceRequired)")
                    .font(.caption2).monospacedDigit() }
                if !compact { Text("공격 \(progress.pet.attack) · 방어 \(progress.pet.defense) · 체력 \(progress.pet.health)")
                    .font(.caption2).lineLimit(2) }
                Text("스탯 포인트 \(WatchNumber.compact(progress.pet.statPoints))")
                        .accessibilityLabel("스탯 포인트 \(progress.pet.statPoints)")
                    .font(.caption).foregroundStyle(.yellow)
            }
            NavigationLink {
                PetStatisticsView(viewModel: viewModel)
            } label: {
                Label("스탯 관리", systemImage: "chart.bar.fill")
            }
            .buttonStyle(WatchActionStyle())
            .accessibilityIdentifier("watch.managePetStatistics")
        }
        }
    }
}
