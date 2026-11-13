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
    private var preparingCharacterID: String?
    private var preparedCharacterID: String?
    private var generation = UUID()
    private var request: PetPlaybackRequest?

    func prepare(characterID: String = PetCustomization.default.characterID) async {
        let character = PetCustomizationCatalog.character(id: characterID)
        if isReady, preparedCharacterID == character.id { return }
        if preparingCharacterID == character.id, let preparation { await preparation.value; return }
        preparation?.cancel()
        let token = UUID(); generation = token
        preparingCharacterID = character.id; isReady = false
        scene.stopPlayback()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.preparingCharacterID = nil } }
            // Preload just this character, rather than every future catalog entry.
            let names = Set(character.motions.flatMap(\.frames))
            let textures = Dictionary(uniqueKeysWithValues: names.map { ($0, SKTexture(imageNamed: $0)) })
            for texture in textures.values { texture.filteringMode = .linear }
            await withCheckedContinuation { continuation in
                SKTexture.preload(Array(textures.values)) { continuation.resume() }
            }
            guard !Task.isCancelled, self.generation == token else { return }
            guard textures.values.allSatisfy({ texture in
                let size = texture.size()
                return size.height > 0 && abs(size.width / size.height - CGFloat(character.canvasWidth / character.canvasHeight)) < 0.001
            }) else {
                AnimationDiagnostics.recordRenderer(["renderer": "SpriteKit", "texturesReady": false])
                return
            }
            self.scene.install(textures, character: character)
            self.preparedCharacterID = character.id
            self.isReady = true
            if let request = self.request, request.characterID == character.id { self.scene.apply(request) }
        }
        preparation = task
        await task.value
    }
    func apply(_ request: PetPlaybackRequest) {
        self.request = request
        if isReady, preparedCharacterID == request.characterID { scene.apply(request) }
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
    private var character = PetCustomizationCatalog.characters[0]
    private var request: PetPlaybackRequest?
    private var frameNames: [String] = []
    private let nextTexture = SKUniform(name: "u_nextFrame", texture: nil)
    private let frameMix = SKUniform(name: "u_frameMix", float: 0)
    private lazy var frameShader = SKShader(source: """
        void main() {
            vec4 current = texture2D(u_texture, v_tex_coord);
            vec4 next = texture2D(u_nextFrame, v_tex_coord);
            gl_FragColor = mix(current, next, u_frameMix) * v_color_mix.a;
        }
        """, uniforms: [nextTexture, frameMix])
    private var firstTick: TimeInterval?
    private var lastTick: TimeInterval?
    private var ticks = 0
    private var worstGap: TimeInterval = 0
    #if DEBUG
    private var observedFrames: [String] = []
    private var mixedSamples = 0
    private var displaySamples = 0
    #endif

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
        let width = CGFloat(character.canvasWidth), height = CGFloat(character.canvasHeight)
        let petScale = min(size.width / width, size.height / height)
        pet.size = CGSize(width: width * petScale, height: height * petScale)
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
    func install(_ textures: [String: SKTexture], character: PetCharacterDefinition) {
        self.textures = textures
        self.character = character
        layoutCanvas()
        pet.texture = textures[PetSpriteAnimation(.idle, characterID: character.id).posterImageName]
        nextTexture.textureValue = pet.texture
        pet.shader = frameShader
    }
    func apply(_ value: PetPlaybackRequest) {
        guard request != value else { return }
        stopPlayback(); request = value
        let animation = value.animation
        frameNames = animation.frameNames
        if value.isPlaying { selectFrame(at: Date()) }
        else {
            pet.texture = textures[animation.posterImageName]
            nextTexture.textureValue = pet.texture; frameMix.floatValue = 0
        }
    }
    private func selectFrame(at date: Date) {
        guard let request, request.isPlaying else { return }
        let sample = request.animation.blend(elapsed: date.timeIntervalSince(request.startedAt))
        guard frameNames.indices.contains(sample.fromIndex), frameNames.indices.contains(sample.toIndex) else { return }
        pet.texture = textures[frameNames[sample.fromIndex]]
        nextTexture.textureValue = textures[frameNames[sample.toIndex]]
        frameMix.floatValue = sample.amount
        #if DEBUG
        displaySamples += 1
        if sample.amount > 0.01 && sample.amount < 0.99 { mixedSamples += 1 }
        #endif
    }
    func stopPlayback() {
        #if DEBUG
        if let request, request.isPlaying {
            AnimationDiagnostics.recordPlayback([
                "driver": "interpolated-textures", "mode": String(describing: request.activity),
                "observedFrameNames": observedFrames, "distinctFrameCount": Set(observedFrames).count,
                "requestedFrameCount": request.animation.frameNames.count,
                "displaySamples": displaySamples, "interpolatedSamples": mixedSamples,
                "capturedAt": Date().timeIntervalSince1970
            ], mode: String(describing: request.activity))
        }
        observedFrames = []
        displaySamples = 0; mixedSamples = 0
        #endif
        pet.removeAction(forKey: "pet.clip"); request = nil
        firstTick = nil; lastTick = nil; ticks = 0; worstGap = 0
    }
    override func didEvaluateActions() {
        #if DEBUG
        guard request?.isPlaying == true,
              let name = textures.first(where: { $0.value === pet.texture })?.key,
              observedFrames.last != name, observedFrames.count < 128 else { return }
        observedFrames.append(name)
        #endif
    }
    override func update(_ currentTime: TimeInterval) {
        selectFrame(at: Date())
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
            "textureFrameCount": request.animation.frameNames.count, "sceneWidth": size.width, "sceneHeight": size.height,
            "spriteWidth": pet.size.width, "spriteHeight": pet.size.height
        ])
        self.firstTick = currentTime; ticks = 1; worstGap = 0
        #endif
    }
}
