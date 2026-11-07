import SwiftUI

struct WatchCloudView: View {
    @ObservedObject var viewModel: WatchCloudController

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label("계정과 백업", systemImage: "icloud").font(.headline)
                if let account = viewModel.account {
                    Text(account.displayName).font(.caption).lineLimit(2)
                    Button("서버 백업·보상 받기") { Task { await viewModel.requestBackup() } }
                        .disabled(viewModel.isBusy)
                        .accessibilityIdentifier("watch.serverBackup")
                } else {
                    Text("아이폰의 PetPet에서 Google로 로그인해 주세요.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                if viewModel.isBusy { ProgressView() }
                if let date = viewModel.lastBackupAt {
                    Text("최근 백업 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let message = viewModel.message {
                    Text(message).font(.caption2).multilineTextAlignment(.center)
                }
                Text("서버 복원은 아이폰에서 기록을 확인한 뒤 진행해요.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 14).padding(.vertical, 20)
        }
        .accessibilityIdentifier("watch.cloudAccount")
    }
}
