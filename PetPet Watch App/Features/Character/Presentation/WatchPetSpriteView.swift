import SwiftUI
import SpriteKit
import PetPetCore

struct WatchPetSpriteView: View {
    let state: PetAnimationState
    var backgroundImageName = "stepmate_background_night"
    var backgroundCanvas: CGSize?
    var backgroundCoordinateSpace: String?
    @StateObject private var renderer = WatchPetRenderer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animation = PetSpriteAnimation(state.activity)
        let paused = !state.isActive || !animation.isAnimated || reduceMotion || luminanceReduced || scenePhase != .active
        let request = PetPlaybackRequest(state: state, suppressed: paused)
        GeometryReader { geometry in
            let viewport = backgroundCoordinateSpace.map { geometry.frame(in: .named($0)) } ?? CGRect(origin: .zero, size: geometry.size)
            let backdrop = PetSpriteBackdrop(name: backgroundImageName, canvas: backgroundCanvas ?? geometry.size, viewport: viewport)
            ZStack {
                SpriteView(scene: renderer.scene, isPaused: paused || !renderer.isReady,
                           preferredFramesPerSecond: 30)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(paused || !renderer.isReady ? 0 : 1)
                    .allowsHitTesting(false)
                if paused || !renderer.isReady {
                    Image(animation.posterImageName).resizable().scaledToFit()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: backdrop, initial: true) { _, value in renderer.configureBackdrop(value) }
        }
        .task { await renderer.prepare() }
        .onChange(of: request, initial: true) { _, value in renderer.apply(value) }
        .onChange(of: [reduceMotion, luminanceReduced, scenePhase == .active, state.isActive], initial: true) { _, flags in
            AnimationDiagnostics.record(reduceMotion: flags[0], luminanceReduced: flags[1], sceneActive: flags[2], homeVisible: flags[3])
        }
        .onAppear { renderer.apply(request) }
        .onDisappear { renderer.stop() }
        .accessibilityHidden(true)
    }
}
