import SwiftUI
import GoogleSignInSwift
import PetPetCore

struct AccountView: View {
    @ObservedObject var viewModel: AccountViewModel

    var body: some View {
        List {
            Section("계정") {
                if let session = viewModel.session {
                    Label(session.nickname ?? session.name ?? "내 계정", systemImage: "person.crop.circle.fill")
                        .font(.headline)
                    if let email = session.email { Text(email).font(.subheadline).foregroundStyle(.secondary) }
                    Button("로그아웃", role: .destructive) { Task { await viewModel.signOut() } }
                        .disabled(viewModel.isSigningIn)
                } else {
                    GoogleSignInButton { Task { await viewModel.signIn() } }
                        .disabled(!viewModel.canSignIn || viewModel.isSigningIn)
                        .accessibilityIdentifier("phone.googleSignIn")
                    if !viewModel.canSignIn {
                        Text("계정 연결 설정이 아직 완료되지 않았어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button { Task { await viewModel.backup() } } label: {
                    Label("워치 기록 백업", systemImage: "icloud.and.arrow.up")
                }
                .disabled(viewModel.session == nil || viewModel.isBusy)
                .accessibilityIdentifier("phone.serverBackup")
                if let date = viewModel.cloudState.lastBackupAt {
                    Text("최근 백업 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("서버 백업") } footer: {
                Text("워치의 전체 걸음수 기록과 펫 능력치를 저장해요. 백업이 완료되면 워치에서 걸음수 보상을 받아요.")
            }
            Section {
                Button { Task { await viewModel.prepareRestore() } } label: {
                    Label("서버 기록 불러오기", systemImage: "icloud.and.arrow.down")
                }
                .disabled(viewModel.session == nil || viewModel.isBusy)
                .accessibilityIdentifier("phone.previewServerRestore")
            } header: { Text("서버 복원") } footer: {
                Text("저장된 기록을 먼저 확인한 뒤 복원할 수 있어요. 아이폰과 워치에서 PetPet을 열어 주세요.")
            }
            if viewModel.isBusy { ProgressView(progressText).font(.footnote) }
            if let feedback = viewModel.feedback {
                Text(feedback).font(.footnote).foregroundStyle(viewModel.cloudState.error == nil ? Color.secondary : Color.orange)
                    .accessibilityIdentifier("phone.cloudFeedback")
            }
            if let host = viewModel.configuration.baseURL?.host {
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
                    LabeledContent("서버 기록", value: "Lv.\(preview.state.pet.level)")
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
