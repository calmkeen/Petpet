#if DEBUG
import SwiftUI
import PetPetCore

struct WatchAnimationPreview: View {
    @State private var state = PetAnimationState.preview(.running)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(state.activity == .running ? "달리기" : state.activity == .touching ? "인사" : "쉬기").font(.headline)
                WatchPetSpriteView(state: state).frame(height: 116)
                    .background { Image("stepmate_background_night").resizable().scaledToFill() }
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                Text("기록을 바꾸지 않는\n자동 동작 미리보기").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if reduceMotion { Text("동작 줄이기가 켜져 있어 정지 자세로 표시해요.").font(.caption2).foregroundStyle(.orange) }
            }.padding(.horizontal, 14).padding(.bottom, 16)
        }
        .navigationTitle("동작 테스트")
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { state = .preview(.idle); return }
            do {
                while !Task.isCancelled {
                    state = .preview(.running)
                    try await Task.sleep(for: .seconds(3))
                    state = .preview(.touching)
                    try await Task.sleep(for: .seconds(PetSpriteAnimation.greetingDuration))
                    state = .preview(.idle)
                    try await Task.sleep(for: .milliseconds(500))
                }
            } catch { }
        }
    }
}
#endif
