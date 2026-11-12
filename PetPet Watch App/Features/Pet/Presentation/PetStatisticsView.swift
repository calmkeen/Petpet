import SwiftUI
import PetPetCore

struct PetStatisticsView: View {
    @ObservedObject var viewModel: PetProgressViewModel

    var body: some View {
        List {
            if let progress = viewModel.progress {
                Section {
                    Text("Lv.\(progress.pet.level)").font(.title2.bold()).accessibilityIdentifier("watch.petLevel")
                    Text(progress.pet.mood.displayName).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.pet.experience), total: Double(progress.experienceRequired)).tint(.green)
                    Text("경험치 \(progress.pet.experience) / \(progress.experienceRequired)").font(.caption2).monospacedDigit()
                    Label("호감도 \(progress.pet.affection)", systemImage: "heart.fill").foregroundStyle(.pink).font(.caption)
                    Text("쓰다듬기 \(progress.touchCount)/50 · 50회마다 애정도 +1")
                        .font(.caption2)
                        .accessibilityIdentifier("watch.touchCount")
                }
                Section {
                    Text("스탯 포인트 \(progress.pet.statPoints)").foregroundStyle(.yellow)
                        .accessibilityIdentifier("watch.statPoints")
                    statistic("공격력", value: progress.pet.attack, type: .attack)
                    statistic("방어력", value: progress.pet.defense, type: .defense)
                    statistic("체력", value: progress.pet.health, type: .health)
                } footer: {
                    Text("포인트 1개로 능력치 1 증가\n홈의 펫을 50번 쓰다듬으면 호감도 +1")
                }
            }
            PetProgressFeedback(viewModel: viewModel)
        }.navigationTitle("성장")
    }

    private func statistic(_ name: String, value: Int64, type: TrainableStatistic) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption2).foregroundStyle(.secondary)
                Text(value.formatted()).font(.body).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("watch.stat.\(type.rawValue)")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await viewModel.allocate(type) } } label: { Image(systemName: "plus") }
                .buttonStyle(WatchStatisticButtonStyle())
                .disabled(viewModel.isBusy || (viewModel.progress?.pet.statPoints ?? 0) == 0)
                .accessibilityLabel("\(name) 1 올리기")
                .accessibilityIdentifier("watch.allocate.\(type.rawValue)")
        }

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
    var shortName: String {
        switch self {
        case .happy: "행복"
        case .sad: "그리움"
        case .hungry: "배고픔"
        }
    }

    var displayName: String {
        switch self {
        case .happy: "행복해요"
        case .sad: "보고 싶었어요"
        case .hungry: "배고파요"
        }
    }
}
