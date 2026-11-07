import SwiftUI
import PetPetCore

struct WatchPetSpriteView: View {
    let state: PetAnimationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animation = PetSpriteAnimation(state.activity)
        let paused = !state.isActive || !animation.isAnimated || reduceMotion || luminanceReduced || scenePhase != .active
        TimelineView(.animation(minimumInterval: animation.frameInterval, paused: paused)) { context in
            Image(paused ? animation.posterImageName : animation.imageName(elapsed: context.date.timeIntervalSince(state.startedAt)))
                .resizable().scaledToFit()
        }
        .accessibilityHidden(true)
    }
}
