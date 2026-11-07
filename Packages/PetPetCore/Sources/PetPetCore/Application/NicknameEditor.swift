import Foundation

public enum NicknameStatus: Equatable, Sendable {
    case idle, tooShort, tooLong, checking, available, unavailable, unchanged, failed
}

public struct NicknameEditorState: Equatable, Sendable {
    public var input = ""
    public var currentNickname: String
    public var status: NicknameStatus = .idle
    public var isSubmitting = false
    public var message: String?
    public var canSubmit: Bool { status == .available && !isSubmitting }
}

@MainActor
public final class NicknameEditor {
    public private(set) var state: NicknameEditorState
    public var onStateChange: ((NicknameEditorState) -> Void)?
    private let check: (String) async throws -> Bool
    private let update: (String) async throws -> String
    private let debounce: Duration
    private var generation = 0
    private var task: Task<Void, Never>?
    private var checkedValue: String?

    public init(currentNickname: String, debounce: Duration = .milliseconds(350),
                check: @escaping (String) async throws -> Bool, update: @escaping (String) async throws -> String) {
        state = NicknameEditorState(currentNickname: currentNickname)
        self.check = check; self.update = update; self.debounce = debounce
    }

    public func setInput(_ value: String) {
        guard !state.isSubmitting else { return }
        task?.cancel(); generation += 1; checkedValue = nil
        state.input = value; state.message = nil
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.status = .idle; emit(); return }
        do { try NicknameRules.validate(value) }
        catch { state.status = error as? BackendError == .nicknameTooLong ? .tooLong : .tooShort; emit(); return }
        if value.utf8.elementsEqual(state.currentNickname.utf8) { state.status = .unchanged; emit(); return }
        state.status = .checking; emit()
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.debounce)
                let available = try await self.check(value)
                guard token == self.generation, !Task.isCancelled else { return }
                self.checkedValue = value
                self.state.status = available ? .available : .unavailable
            } catch is CancellationError { return }
            catch {
                guard token == self.generation, !Task.isCancelled else { return }
                self.state.status = .failed; self.state.message = error.localizedDescription
            }
            self.emit()
        }
    }

    public func submit() async {
        guard state.canSubmit, let checkedValue, checkedValue.utf8.elementsEqual(state.input.utf8) else { return }
        state.isSubmitting = true; state.message = nil; emit()
        do {
            let changed = try await update(checkedValue)
            state.currentNickname = changed; state.input = changed; state.status = .unchanged
            state.message = "닉네임을 바꿨어요."
        } catch {
            state.status = error as? BackendError == .nicknameUnavailable ? .unavailable : .failed
            state.message = error.localizedDescription
        }
        state.isSubmitting = false; emit()
    }
    public func retry() { setInput(state.input) }
    public func cancelCheck() {
        task?.cancel(); generation += 1; checkedValue = nil
        if state.status == .checking || state.status == .available { state.status = .idle; emit() }
    }
    public func finishCheck() async { await task?.value }
    private func emit() { onStateChange?(state) }
}
