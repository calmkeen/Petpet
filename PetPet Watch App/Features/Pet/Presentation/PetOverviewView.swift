import SwiftUI
import PetPetCore

struct PetOverviewView: View {
    @ObservedObject var viewModel: PetProgressViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text("성장").font(.headline)
            if let progress = viewModel.progress {
                Text("Lv.\(progress.pet.level)").font(.title2.bold())
                ProgressView(value: Double(progress.pet.experience), total: Double(progress.experienceRequired))
                    .tint(.green)
                Text("경험치 \(progress.pet.experience) / \(progress.experienceRequired)")
                    .font(.caption2).monospacedDigit()
                Text("공격 \(progress.pet.attack) · 방어 \(progress.pet.defense) · 체력 \(progress.pet.health)")
                    .font(.caption2).minimumScaleFactor(0.8).lineLimit(1)
                Text("스탯 포인트 \(progress.pet.statPoints)")
                    .font(.caption).foregroundStyle(.yellow)
            }
            NavigationLink {
                PetStatisticsView(viewModel: viewModel)
            } label: {
                Label("스탯 관리", systemImage: "chart.bar.fill")
            }
            .accessibilityIdentifier("watch.managePetStatistics")
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("watch.petOverview")
    }
}
