import SwiftUI

struct WatchCloudView: View {
    @ObservedObject var viewModel: WatchCloudController

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label("계정과 백업", systemImage: "icloud").font(.headline)
                if viewModel.isDevelopment {
                    Text("Debug · 백업은 아이폰에 저장돼요").font(.caption2).foregroundStyle(.orange)
                }
                if let account = viewModel.account {
                    Text(account.displayName).font(.caption).lineLimit(2)
                    NavigationLink("닉네임 변경") { WatchNicknameView(editor: viewModel.makeNicknameEditor()) }
                        .accessibilityIdentifier("watch.editNickname")
                    Button(viewModel.isDevelopment ? "모의 백업·보상 받기" : "서버 백업·보상 받기") { Task { await viewModel.requestBackup() } }
                        .disabled(viewModel.isBusy)
                        .accessibilityIdentifier("watch.serverBackup")
                } else {
                    Text(viewModel.isDevelopment ? "아이폰의 PetPet에서 개발용 계정으로 로그인해 주세요." : "아이폰의 PetPet에서 Apple로 로그인해 주세요.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                if viewModel.isBusy { ProgressView() }
                if let date = viewModel.lastBackupAt {
                    Text("최근 백업 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let message = viewModel.message {
                    Text(message).font(.caption2).multilineTextAlignment(.center)
                        .accessibilityIdentifier("watch.cloudFeedback")
                }
                Text("서버 복원은 아이폰에서 기록을 확인한 뒤 진행해요.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                #if DEBUG
                NavigationLink("캐릭터 동작 테스트") { WatchAnimationPreview() }
                    .accessibilityIdentifier("watch.previewCharacter")
                #endif
            }
            .padding(.horizontal, 14).padding(.vertical, 20)
        }
    }
}
