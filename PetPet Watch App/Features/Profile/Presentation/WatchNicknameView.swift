import SwiftUI
import PetPetCore

@MainActor
struct WatchNicknameView: View {
    @StateObject private var model: NicknameEditorViewModel
    init(editor: NicknameEditor) { _model = StateObject(wrappedValue: NicknameEditorViewModel(editor: editor)) }
    var body: some View {
        List {
            Section("현재 닉네임") { Text(model.state.currentNickname).font(.caption).fixedSize(horizontal: false, vertical: true) }
            Section("새 닉네임") {
                TextField("2자 이상 입력", text: Binding(get: { model.state.input }, set: { model.setInput($0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(model.state.isSubmitting).accessibilityIdentifier("nickname.input")
                if model.state.status == .checking || model.state.isSubmitting { ProgressView() }
                Text(model.statusText).font(.caption2).foregroundStyle(.secondary)
                Button("변경하기") { Task { await model.submit() } }
                    .disabled(!model.state.canSubmit).accessibilityIdentifier("nickname.submit")
                if model.state.status == .failed { Button("다시 확인") { model.setInput(model.state.input) } }
            }
            if let message = model.state.message { Text(message).font(.caption2).accessibilityIdentifier("nickname.feedback") }
        }
        .navigationTitle("닉네임")
        .task { model.resume() }
        .onDisappear { model.stop() }
    }
}
