import Combine
import Foundation
import PetPetCore

@MainActor
final class NicknameEditorViewModel: ObservableObject {
    @Published private(set) var state: NicknameEditorState
    private let editor: NicknameEditor
    init(editor: NicknameEditor) {
        self.editor = editor
        state = editor.state
        editor.onStateChange = { [weak self] in self?.state = $0 }
    }
    func setInput(_ value: String) { editor.setInput(value) }
    func submit() async { await editor.submit() }
    func resume() { if !state.input.isEmpty { editor.retry() } }
    func stop() { editor.cancelCheck() }
    var statusText: String {
        switch state.status {
        case .idle: "2자 이상 입력해 주세요."
        case .tooShort: "닉네임은 2자 이상이어야 해요."
        case .tooLong: "255자 이내로 입력해 주세요."
        case .checking: "사용할 수 있는지 확인 중이에요."
        case .available: "사용 가능한 닉네임이에요."
        case .unavailable: "이미 사용 중인 닉네임이에요."
        case .unchanged: "현재 사용 중인 닉네임이에요."
        case .failed: state.message ?? "다시 확인해 주세요."
        }
    }
}
