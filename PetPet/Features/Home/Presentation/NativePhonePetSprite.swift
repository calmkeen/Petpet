import SwiftUI
import UIKit
import PetPetCore

/// UIKit holds decoded frames; SwiftUI only sends a new command per gesture.
struct NativePhonePetSprite: UIViewRepresentable {
    let greeting: Date?
    let suppressed: Bool
    var characterID = PetCustomization.default.characterID
    struct Request: Equatable { let greeting: Date?; let suppressed: Bool; let characterID: String }
    final class Coordinator {
        var request: Request?
        var characterID: String?
        var frames: [UIImage] = []
        func prepare(characterID: String) {
            guard self.characterID != characterID else { return }
            self.characterID = characterID
            frames = PetSpriteAnimation(.touching, characterID: characterID).frameNames.compactMap { name -> UIImage? in
                guard let image = UIImage(named: name) else { return nil }
                return image.preparingForDisplay() ?? image
            }
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
        let characterID = PetCustomizationCatalog.character(id: characterID).id
        let request = Request(greeting: greeting, suppressed: suppressed, characterID: characterID)
        guard context.coordinator.request != request else { return }
        context.coordinator.request = request
        view.stopAnimating(); view.animationImages = nil
        context.coordinator.prepare(characterID: characterID)
        let activity: CharacterActivity = greeting == nil ? .idle : .touching
        let animation = PetSpriteAnimation(activity, characterID: characterID)
        if greeting != nil, !suppressed, animation.isAnimated, context.coordinator.frames.count == animation.frameNames.count {
            view.image = context.coordinator.frames.last
            view.animationImages = context.coordinator.frames
            view.animationDuration = animation.cycleDuration
            view.animationRepeatCount = 1; view.startAnimating()
        } else { view.image = UIImage(named: animation.posterImageName) }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        view.stopAnimating(); view.animationImages = nil
    }
}
