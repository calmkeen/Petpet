import SwiftUI
import PetPetCore

@MainActor
struct PhoneNicknameView: View {
    @StateObject private var model: NicknameEditorViewModel
    init(editor: NicknameEditor) { _model = StateObject(wrappedValue: NicknameEditorViewModel(editor: editor)) }
    @FocusState private var editing: Bool
    var body: some View {
        Form {
            Section("현재 닉네임") { Text(model.state.currentNickname).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("nickname.current") }
            Section("새 닉네임") {
                TextField("2자 이상", text: Binding(get: { model.state.input }, set: { model.setInput($0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44).focused($editing).submitLabel(.done).onSubmit { editing = false }
                    .disabled(model.state.isSubmitting).accessibilityIdentifier("nickname.input")
                if model.state.status == .checking || model.state.isSubmitting { ProgressView() }
                Text(model.statusText).font(.footnote).foregroundStyle(.secondary)
                Button("변경하기") { Task { await model.submit() } }
                    .buttonStyle(PhoneActionStyle())
                    .disabled(!model.state.canSubmit).accessibilityIdentifier("nickname.submit")
                if model.state.status == .failed { Button("다시 확인") { model.setInput(model.state.input) } }
            }
            if let message = model.state.message { Text(message).font(.footnote).accessibilityIdentifier("nickname.feedback") }
        }
        .navigationTitle("닉네임 변경")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .tint(PhoneDesign.accent).scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editing {
                    Button { editing = false } label: { Image(systemName: "checkmark") }
                        .buttonStyle(PhoneIconStyle()).accessibilityLabel("완료")
                        .accessibilityIdentifier("nickname.dismissKeyboard")
                }
            }
        }
        .task { model.resume() }
        .onDisappear { model.stop() }
    }
}
