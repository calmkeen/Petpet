import SwiftUI
import AuthenticationServices
import PetPetCore

struct AccountView: View {
    @ObservedObject var viewModel: AccountViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if viewModel.configuration.isDevelopment {
                Section {
                    Label("Debug 테스트 모드", systemImage: "hammer.fill").font(.headline)
                    Text("모의 계정과 백업은 이 아이폰 안에 저장돼요. Apple 인증과 운영 서버에는 연결하지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("계정") {
                if let session = viewModel.session {
                    Label(session.nickname ?? session.name ?? "내 계정", systemImage: "person.crop.circle.fill")
                        .font(.headline)
                    if let email = session.email { Text(email).font(.subheadline).foregroundStyle(.secondary) }
                    NavigationLink("닉네임 변경") { PhoneNicknameView(editor: viewModel.makeNicknameEditor()) }
                        .accessibilityIdentifier("phone.editNickname")
                    Button("로그아웃", role: .destructive) { Task { await viewModel.signOut() } }
                        .disabled(viewModel.isSigningIn)
                } else {
                    #if DEBUG
                    Button { Task { await viewModel.signInForDevelopment() } } label: {
                        Label("개발용 계정으로 로그인", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSignIn || viewModel.isSigningIn)
                    .accessibilityIdentifier("phone.developmentSignIn")
                    Text("로그인 없이도 걸음수·먹이·성장 기능을 사용할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #else
                    SignInWithAppleButton(.signIn, onRequest: viewModel.beginSignIn) { result in
                        Task { await viewModel.completeSignIn(result) }
                    }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .disabled(!viewModel.canSignIn || viewModel.isSigningIn)
                        .accessibilityIdentifier("phone.appleSignIn")
                    #endif
                    if !viewModel.canSignIn {
                        Text("계정 연결 설정이 아직 완료되지 않았어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button { Task { await viewModel.backup() } } label: {
                    Label(viewModel.configuration.isDevelopment ? "워치 기록 모의 백업" : "워치 기록 백업", systemImage: "icloud.and.arrow.up")
                }
                .disabled(viewModel.session == nil || viewModel.isBusy)
                .accessibilityIdentifier("phone.serverBackup")
                if let date = viewModel.cloudState.lastBackupAt {
                    Text("최근 백업 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text(viewModel.configuration.isDevelopment ? "개발용 백업" : "서버 백업") } footer: {
                Text(viewModel.configuration.isDevelopment
                     ? "워치 기록을 이 아이폰의 모의 저장소에 저장해요. 완료되면 워치에 테스트 보상을 지급해요."
                     : "워치의 전체 걸음수 기록과 펫 능력치를 저장해요. 백업이 완료되면 워치에서 걸음수 보상을 받아요.")
            }
            Section {
                Button { Task { await viewModel.prepareRestore() } } label: {
                    Label(viewModel.configuration.isDevelopment ? "모의 백업 불러오기" : "서버 기록 불러오기", systemImage: "icloud.and.arrow.down")
                }
                .disabled(viewModel.session == nil || viewModel.isBusy)
                .accessibilityIdentifier("phone.previewServerRestore")
            } header: { Text(viewModel.configuration.isDevelopment ? "개발용 복원" : "서버 복원") } footer: {
                Text("저장된 기록을 먼저 확인한 뒤 복원할 수 있어요. 아이폰과 워치에서 PetPet을 열어 주세요.")
            }
            if viewModel.isBusy { ProgressView(progressText).font(.footnote) }
            if let feedback = viewModel.feedback {
                Text(feedback).font(.footnote).foregroundStyle(viewModel.cloudState.error == nil ? Color.secondary : Color.orange)
                    .accessibilityIdentifier("phone.cloudFeedback")
            }
            if viewModel.configuration.isDevelopment {
                Text("백업 위치: 이 아이폰의 개발용 저장소").font(.caption).foregroundStyle(.secondary)
            } else if let host = viewModel.configuration.baseURL?.host {
                Text("연결 서버: \(host)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("계정과 백업")
        .toolbar(.visible, for: .navigationBar)
        .task { await viewModel.start() }
        .sheet(isPresented: Binding(get: { viewModel.preview != nil }, set: { if !$0 { viewModel.cancelPreview() } })) {
            if let preview = viewModel.preview { restorePreview(preview) }
        }
    }

    private var progressText: String {
        if viewModel.isSigningIn { return "로그인하고 있어요" }
        if viewModel.isPreparingRestore { return "서버 기록을 확인하고 있어요" }
        return viewModel.cloudState.message ?? "워치 응답을 기다리고 있어요"
    }

    private func restorePreview(_ preview: WatchRestoreImport) -> some View {
        NavigationStack {
            List {
                Section("복원할 펫") {
                    LabeledContent("현재 워치", value: "Lv.\(preview.target.pet.level)")
                    LabeledContent(viewModel.configuration.isDevelopment ? "모의 백업 기록" : "서버 기록", value: "Lv.\(preview.state.pet.level)")
                    LabeledContent("경험치", value: "\(preview.state.pet.experience)")
                    Text("공격 \(preview.state.pet.attack) · 방어 \(preview.state.pet.defense) · 체력 \(preview.state.pet.health)")
                }
                Section("걸음수 기록") { Text("\(preview.state.steps.count)일의 서버 기록") }
                Section {
                    Text("현재 펫 능력치를 서버 기록으로 바꿔요. 먹이·남은 스탯 포인트는 기기 기록을 보존하고, 같은 계정의 걸음수는 날짜별 큰 값을 유지해요.")
                    if let owner = preview.target.ownerID, owner != preview.state.accountID {
                        Text("이전 계정의 워치 기록은 따로 보관하고 현재 로그인한 계정으로 전환해요.")
                            .foregroundStyle(.orange)
                    }
                    Button("이 기록으로 복원", role: .destructive) { Task { await viewModel.applyRestore() } }
                        .accessibilityIdentifier("phone.confirmServerRestore")
                }
            }
            .navigationTitle("복원 전 확인")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { viewModel.cancelPreview() } } }
        }
    }
}
