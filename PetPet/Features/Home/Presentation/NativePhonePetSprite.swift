import SwiftUI
import UIKit
import PetPetCore

/// UIKit holds decoded frames; SwiftUI only sends a new command per gesture.
struct NativePhonePetSprite: UIViewRepresentable {
    let greeting: Date?
    let suppressed: Bool
    struct Request: Equatable { let greeting: Date?; let suppressed: Bool }
    final class Coordinator {
        var request: Request?
        let frames = PetSpriteAnimation(.touching).frameNames.compactMap { name -> UIImage? in
            guard let image = UIImage(named: name) else { return nil }
            return image.preparingForDisplay() ?? image
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let image = UIImageView()
        image.contentMode = .scaleAspectFit; image.clipsToBounds = true
        image.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        image.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return image
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        let request = Request(greeting: greeting, suppressed: suppressed)
        guard context.coordinator.request != request else { return }
        context.coordinator.request = request
        view.stopAnimating(); view.animationImages = nil
        let activity: CharacterActivity = greeting == nil ? .idle : .touching
        let animation = PetSpriteAnimation(activity)
        if greeting != nil, !suppressed, context.coordinator.frames.count == PetSpriteAnimation.greetingFrameCount {
            view.image = context.coordinator.frames.last
            view.animationImages = context.coordinator.frames
            view.animationDuration = PetSpriteAnimation.greetingDuration
            view.animationRepeatCount = 1; view.startAnimating()
        } else { view.image = UIImage(named: animation.posterImageName) }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        view.stopAnimating(); view.animationImages = nil
    }
}
