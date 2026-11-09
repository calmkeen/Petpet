import SwiftUI

struct WatchCloudOverview: View {
    @ObservedObject var viewModel: WatchCloudController
    var body: some View {
        WatchOverviewLayout { compact in
            VStack(spacing: compact ? 4 : 8) {
                Label("계정·백업", systemImage: "icloud").font(.headline)
                Text(viewModel.account?.displayName ?? "아이폰에서 로그인")
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel(viewModel.account?.displayName ?? "아이폰에서 로그인해 주세요")
                    .accessibilityIdentifier("watch.accountName")
                NavigationLink("백업 관리") { WatchCloudView(viewModel: viewModel) }
                    .buttonStyle(WatchActionStyle())
            }
        }
    }
}

struct WatchCloudView: View {
    @ObservedObject var viewModel: WatchCloudController

    var body: some View {
        List {
            Section("계정") {
                if let account = viewModel.account {
                    Text(account.displayName).font(.body).fixedSize(horizontal: false, vertical: true)
                    NavigationLink("닉네임 변경") { WatchNicknameView(editor: viewModel.makeNicknameEditor()) }
                        .accessibilityIdentifier("watch.editNickname")
                } else {
                    Text(viewModel.isDevelopment ? "아이폰의 PetPet에서 개발용 계정으로 로그인해 주세요." : "아이폰의 PetPet에서 Apple로 로그인해 주세요.")
                        .font(.caption)
                }
            }
            Section {
                if viewModel.account != nil {
                    Button("백업·보상 받기") { Task { await viewModel.requestBackup() } }
                        .disabled(viewModel.isBusy).accessibilityIdentifier("watch.serverBackup")
                }
                if viewModel.isBusy { ProgressView("백업 중") }
                if let message = viewModel.message {
                    Text(message).font(.caption).accessibilityIdentifier("watch.cloudFeedback")
                }
                if let date = viewModel.lastBackupAt {
                    Text("최근 백업\n\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } header: { Text("백업") } footer: {
                Text(viewModel.isDevelopment ? "Debug · 백업은 아이폰에 저장돼요. 복원은 아이폰에서 진행해요." : "서버 복원은 아이폰에서 기록을 확인한 뒤 진행해요.")
            }
            #if DEBUG
            Section {
                NavigationLink("캐릭터 동작 테스트") { WatchAnimationPreview() }
                    .accessibilityIdentifier("watch.previewCharacter")
            }
            #endif
        }.navigationTitle("계정")
    }
}
