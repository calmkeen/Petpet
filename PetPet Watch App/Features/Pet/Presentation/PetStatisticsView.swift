import SwiftUI
import PetPetCore

struct PetStatisticsView: View {
    @ObservedObject var viewModel: PetProgressViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("나의 펫").font(.headline)
                if let progress = viewModel.progress {
                    Text("Lv.\(progress.pet.level)").font(.title2.bold()).accessibilityIdentifier("watch.petLevel")
                    Text(progress.pet.mood.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.pet.experience), total: Double(progress.experienceRequired))
                        .tint(.green)
                    Text("경험치 \(progress.pet.experience) / \(progress.experienceRequired)")
                        .font(.caption2).monospacedDigit()
                    Label("호감도 \(progress.pet.affection)", systemImage: "heart.fill")
                        .foregroundStyle(.pink).font(.caption)
                    Text("스탯 포인트 \(progress.pet.statPoints)")
                        .font(.caption).foregroundStyle(.yellow)
                        .accessibilityIdentifier("watch.statPoints")
                    statistic("공격력", value: progress.pet.attack, type: .attack)
                    statistic("방어력", value: progress.pet.defense, type: .defense)
                    statistic("체력", value: progress.pet.health, type: .health)
                    Text("홈의 펫을 50번 쓰다듬으면 호감도 +1")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                PetProgressFeedback(viewModel: viewModel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
        }
    }

    private func statistic(_ name: String, value: Int64, type: TrainableStatistic) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value.formatted()).monospacedDigit().accessibilityIdentifier("watch.stat.\(type.rawValue)")
            Button {
                Task { await viewModel.allocate(type) }
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 30)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(viewModel.isBusy || (viewModel.progress?.pet.statPoints ?? 0) == 0)
            .accessibilityLabel("\(name) 1 올리기")
            .accessibilityIdentifier("watch.allocate.\(type.rawValue)")
        }
        .font(.caption)
    }
}

struct PetProgressFeedback: View {
    @ObservedObject var viewModel: PetProgressViewModel

    var body: some View {
        if viewModel.isBusy && viewModel.progress == nil { ProgressView() }
        if let error = viewModel.errorMessage {
            Text(error).font(.caption2).foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Button("다시 불러오기") { Task { await viewModel.retry() } }
                .disabled(viewModel.isBusy)
        } else if let message = viewModel.message {
            Text(message).font(.caption2).foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("watch.petFeedback")
        }
    }
}

extension PetMood {
    var displayName: String {
        switch self {
        case .happy: "행복해요"
        case .sad: "보고 싶었어요"
        case .hungry: "배고파요"
        }
    }
}
