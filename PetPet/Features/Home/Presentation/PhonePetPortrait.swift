import SwiftUI
import PetPetCore

/// A visual greeting only; pet progression remains owned by the watch.
struct PhonePetPortrait: View {
    @State private var greeting: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let period = PetDaylightPeriod(date: context.date)
            Button { if greeting == nil { greeting = Date() } } label: {
                ZStack {
                    Image(period.backgroundImageName).resizable().scaledToFill()
                    TimelineView(.animation(minimumInterval: PetSpriteAnimation.greetingFrameInterval, paused: greeting == nil || reduceMotion || scenePhase != .active)) { frame in
                        let animation = PetSpriteAnimation(greeting == nil ? .idle : .touching)
                        Image(reduceMotion ? animation.posterImageName : animation.imageName(elapsed: frame.date.timeIntervalSince(greeting ?? frame.date)))
                            .resizable().scaledToFit().padding(12)
                    }
                }
                .frame(width: 104, height: 126).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain).accessibilityLabel("펫에게 인사하기")
            .accessibilityIdentifier("phone.greetPet")
        }
        .task(id: greeting) {
            guard greeting != nil else { return }
            do { try await Task.sleep(for: .seconds(PetSpriteAnimation.greetingDuration)) } catch { return }
            greeting = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { greeting = nil } }
        .onDisappear { greeting = nil }
    }
}
