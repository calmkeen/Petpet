import SwiftUI
import AuthenticationServices
import PetPetCore

struct WatchCloudOverview: View {
    @ObservedObject var viewModel: WatchCloudController
    var body: some View {
        WatchOverviewLayout { compact in
            VStack(spacing: compact ? 4 : 8) {
                Label("계정·백업", systemImage: "icloud").font(.headline)
                Text(viewModel.account?.displayName ?? "워치에서 로그인")
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel(viewModel.account?.displayName ?? "워치 또는 아이폰에서 로그인해 주세요")
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
                    Text(viewModel.supportsStandalone ? "아래에서 워치에 로그인하거나 아이폰 계정을 사용할 수 있어요." : "아이폰의 PetPet에서 로그인해 주세요.")
                        .font(.caption)
                }
            }
            if viewModel.supportsStandalone {
                Section("워치 단독 연결") {
                    if viewModel.usesStandalone {
                        Label(viewModel.account == nil ? "워치에서 로그인 필요" : "아이폰 없이 사용 중", systemImage: "network")
                            .font(.caption).accessibilityIdentifier("watch.connectionMode")
                    }
                    if !viewModel.usesStandalone || viewModel.account == nil {
                        #if DEBUG
                        Button("워치에서 개발용 로그인") { Task { await viewModel.signInStandaloneForDevelopment() } }
                            .disabled(viewModel.isBusy).accessibilityIdentifier("watch.standaloneLogin")
                        #else
                        SignInWithAppleButton(.signIn, onRequest: viewModel.beginStandaloneSignIn) { result in
                            Task { await viewModel.completeStandaloneSignIn(result) }
                        }.frame(minHeight: 44).disabled(viewModel.isBusy)
                        #endif
                    }
                    if viewModel.usesStandalone {
                        if viewModel.account != nil {
                            Button("워치에서 로그아웃", role: .destructive) { Task { await viewModel.signOutStandalone() } }
                                .accessibilityIdentifier("watch.standaloneLogout")
                        }
                        Button("아이폰 연동으로 전환") { Task { await viewModel.useCompanion() } }
                            .disabled(viewModel.isBusy).accessibilityIdentifier("watch.useCompanion")
                    }
                    Text(viewModel.usesStandalone ? viewModel.connectionNote : "닉네임·백업·랭킹·AI 대화를 워치에서 직접 이용해요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section {
                if viewModel.account != nil {
                    Button("백업·보상 받기") { Task { await viewModel.requestBackup() } }
                        .disabled(viewModel.isBusy).accessibilityIdentifier("watch.serverBackup")
                    if viewModel.usesStandalone {
                        Button("백업 기록 불러오기") { Task { await viewModel.prepareStandaloneRestore() } }
                            .disabled(viewModel.isBusy || viewModel.isPreparingRestore)
                            .accessibilityIdentifier("watch.standaloneRestore")
                    }
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
                Text(viewModel.usesStandalone ? (viewModel.isDevelopment ? "Debug · 백업은 워치의 모의 서버에 저장돼요." : "워치가 서버에 직접 백업하고, 확인한 기록만 복원해요.") : "아이폰을 통해 백업·복원해요.")
            }
            #if DEBUG
            Section {
                NavigationLink("캐릭터 동작 테스트") { WatchAnimationPreview() }
                    .accessibilityIdentifier("watch.previewCharacter")
            }
            #endif
        }.navigationTitle("계정")
            .task { await viewModel.start() }
            .sheet(isPresented: Binding(get: { viewModel.restorePreview != nil }, set: { if !$0 { viewModel.cancelStandaloneRestorePreview() } })) {
                if let preview = viewModel.restorePreview {
                    NavigationStack {
                        List {
                            Text("복원할 기록").font(.headline)
                            Text("Lv.\(preview.state.pet.level) · 경험치 \(preview.state.pet.experience)")
                            Text("걸음 기록 \(preview.state.steps.count)일")
                            Text("먹이·보상 내역은 현재 로컬 값을 유지해요.").font(.caption2)
                            Button("이 기록으로 복원") { Task { await viewModel.confirmStandaloneRestore() } }
                                .disabled(viewModel.isBusy).accessibilityIdentifier("watch.confirmStandaloneRestore")
                            Button("취소", role: .cancel) { viewModel.cancelStandaloneRestorePreview() }
                        }.navigationTitle("복원 확인")
                    }
                }
            }
    }
}
