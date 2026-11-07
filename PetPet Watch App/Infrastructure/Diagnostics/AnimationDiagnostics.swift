import Foundation

@MainActor
enum AnimationDiagnostics {
    static func record(reduceMotion: Bool, luminanceReduced: Bool, sceneActive: Bool, homeVisible: Bool) {
        #if DEBUG
        let flags = ["reduceMotion": reduceMotion, "luminanceReduced": luminanceReduced,
                     "sceneActive": sceneActive, "homeVisible": homeVisible]
        let file = URL.applicationSupportDirectory.appendingPathComponent("PetPet/Development/animation-debug.json")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: flags).write(to: file, options: .atomic)
        } catch { /* Presentation diagnostics must not affect the game. */ }
        #endif
    }
}
