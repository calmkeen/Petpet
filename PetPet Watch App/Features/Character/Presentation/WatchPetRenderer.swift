import Combine
import SpriteKit
import PetPetCore

struct PetSpriteBackdrop: Equatable {
    let name: String
    let canvas: CGSize
    let viewport: CGRect
}

@MainActor
final class WatchPetRenderer: ObservableObject {
    @Published private(set) var isReady = false
    let scene = WatchPetScene(size: CGSize(width: 256, height: 336))
    private var preparation: Task<Void, Never>?
    private var request: PetPlaybackRequest?

    func prepare() async {
        if let preparation { await preparation.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let names = PetSpriteAnimation(.running).frameNames + PetSpriteAnimation(.touching).frameNames
            let textures = Dictionary(uniqueKeysWithValues: names.map { ($0, SKTexture(imageNamed: $0)) })
            for texture in textures.values { texture.filteringMode = .linear }
            await withCheckedContinuation { continuation in
                SKTexture.preload(Array(textures.values)) { continuation.resume() }
            }
            guard textures.values.allSatisfy({ texture in
                let size = texture.size()
                return size.height > 0 && abs(size.width / size.height - 256.0 / 336) < 0.001
            }) else {
                AnimationDiagnostics.recordRenderer(["renderer": "SpriteKit", "texturesReady": false])
                return
            }
            self.scene.install(textures)
            self.isReady = true
            if let request = self.request { self.scene.apply(request) }
        }
        preparation = task
        await task.value
    }
    func apply(_ request: PetPlaybackRequest) {
        self.request = request
        if isReady { scene.apply(request) }
    }
    func configureBackdrop(_ backdrop: PetSpriteBackdrop) { scene.configureBackdrop(backdrop) }
    func stop() { request = nil; scene.stopPlayback() }
}

@MainActor
final class WatchPetScene: SKScene {
    private let backdrop = SKSpriteNode()
    private let pet = SKSpriteNode()
    private var backdropProjection: PetSpriteBackdrop?
    private var backdropName: String?
    private var textures: [String: SKTexture] = [:]
    private var request: PetPlaybackRequest?
    private var firstTick: TimeInterval?
    private var lastTick: TimeInterval?
    private var ticks = 0
    private var worstGap: TimeInterval = 0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill; backgroundColor = .clear
        backdrop.zPosition = -1
        addChild(backdrop); addChild(pet)
        layoutCanvas()
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }
    override func didChangeSize(_ oldSize: CGSize) { layoutCanvas() }
    func configureBackdrop(_ value: PetSpriteBackdrop) {
        guard backdropProjection != value else { return }
        backdropProjection = value
        if backdropName != value.name {
            backdropName = value.name
            backdrop.texture = SKTexture(imageNamed: value.name)
            backdrop.texture?.filteringMode = .linear
        }
        layoutCanvas()
    }
    private func layoutCanvas() {
        let petScale = min(size.width / 256, size.height / 336)
        pet.size = CGSize(width: 256 * petScale, height: 336 * petScale)
        pet.position = CGPoint(x: size.width / 2, y: size.height / 2)
        guard let projection = backdropProjection, let texture = backdrop.texture,
              projection.viewport.width > 0, projection.viewport.height > 0 else { return }
        // watchOS SpriteView has no transparency-options initializer. Paint
        // the same wallpaper projection beneath the pet to match its parent.
        let pixels = texture.size()
        let fill = max(projection.canvas.width / pixels.width, projection.canvas.height / pixels.height)
        let image = CGSize(width: pixels.width * fill, height: pixels.height * fill)
        let sx = size.width / projection.viewport.width, sy = size.height / projection.viewport.height
        backdrop.size = CGSize(width: image.width * sx, height: image.height * sy)
        let x = projection.canvas.width / 2 - projection.viewport.minX
        let y = projection.canvas.height / 2 - projection.viewport.minY
        backdrop.position = CGPoint(x: x * sx, y: size.height - y * sy)
    }
    func install(_ textures: [String: SKTexture]) {
        self.textures = textures
        pet.texture = textures[PetSpriteAnimation(.idle).posterImageName]
    }
    func apply(_ value: PetPlaybackRequest) {
        guard request != value else { return }
        stopPlayback(); request = value
        let animation = PetSpriteAnimation(value.activity)
        pet.texture = textures[value.isPlaying ? animation.frameNames[0] : animation.posterImageName]
        guard value.isPlaying else { return }
        let frames = animation.frameNames.compactMap { textures[$0] }
        guard frames.count == animation.frameNames.count else { return }
        let clip = SKAction.animate(with: frames, timePerFrame: animation.frameInterval, resize: false, restore: false)
        pet.run(value.activity == .running ? .repeatForever(clip) : clip, withKey: "pet.clip")
    }
    func stopPlayback() {
        pet.removeAction(forKey: "pet.clip"); request = nil
        firstTick = nil; lastTick = nil; ticks = 0; worstGap = 0
    }
    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        guard let request, request.isPlaying else { return }
        if let lastTick { worstGap = max(worstGap, currentTime - lastTick) }
        lastTick = currentTime; ticks += 1
        guard let firstTick else { self.firstTick = currentTime; return }
        let elapsed = currentTime - firstTick
        guard elapsed >= 0.75 else { return }
        AnimationDiagnostics.recordRenderer([
            "renderer": "SpriteKit", "texturesReady": true, "mode": String(describing: request.activity),
            "targetFPS": 30, "nativeUpdateFPS": Double(ticks - 1) / elapsed,
            "maxFrameGapMS": worstGap * 1000, "sampleSeconds": elapsed, "renderTicks": ticks,
            "textureFrameCount": 16, "sceneWidth": size.width, "sceneHeight": size.height,
            "spriteWidth": pet.size.width, "spriteHeight": pet.size.height
        ])
        self.firstTick = currentTime; ticks = 1; worstGap = 0
        #endif
    }
}
