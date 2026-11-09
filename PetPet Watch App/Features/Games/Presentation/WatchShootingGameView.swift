import SwiftUI
import SpriteKit
import PetPetCore

@MainActor final class ShootingScene: SKScene, ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var combo = 0
    @Published private(set) var health: Int64 = 0
    @Published private(set) var bossText = ""
    @Published private(set) var finished = false
    var game: ShootingGame
    var onFinish: ((GameScore) -> Void)?
    private let world = SKNode()
    private let backdrop = SKSpriteNode(imageNamed:"stepmate_game_shootinggame_background")
    private let player = SKSpriteNode(imageNamed: "stepmate_game_snowfox_baby_run_back1")
    private var nodes: [Int: SKSpriteNode] = [:]
    private var bossNodes: [Int: SKSpriteNode] = [:]
    private var lastUpdate: TimeInterval?
    private var lastHUD = 0.0
    private var textures: [ShootingEntityKind: SKTexture] = [:]
    private var animatedTextures: [ShootingEntityKind: [SKTexture]] = [:]
    init(pet: PetProfile?) {
        game = ShootingGame(attack: pet?.attack ?? 50, health: pet?.health ?? 8)
        super.init(size: CGSize(width: 450,height: 500))
        scaleMode = .resizeFill; backgroundColor = .black
        backdrop.zPosition = -10; addChild(backdrop)
        addChild(world)
        player.size = CGSize(width:50,height:60); player.zPosition = 5; world.addChild(player)
        player.run(.repeatForever(.animate(with:(1...6).map { SKTexture(imageNamed:"stepmate_game_snowfox_baby_run_back\($0)") },timePerFrame:0.15)))
        let names: [ShootingEntityKind: String] = [.meteor:"meteorite_1",.star:"shootingstar_1",.trash:"space_trash_1",.alien:"shootinggame_stage3_alien",.speed:"shooting_item_speed",.heal:"shooting_item_hp",.attack:"shooting_item_attack",.wipe:"shooting_item_boom"]
        for (kind,name) in names { textures[kind] = SKTexture(imageNamed:"stepmate_game_"+name) }
        for (kind,name) in [(ShootingEntityKind.meteor,"meteorite"),(.star,"shootingstar"),(.trash,"space_trash")] {
            animatedTextures[kind] = (1...3).map { SKTexture(imageNamed:"stepmate_game_\(name)_\($0)") }
        }
        layoutWorld()
        isPaused = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didChangeSize(_ oldSize: CGSize) { layoutWorld() }
    private func layoutWorld() {
        backdrop.size = size; backdrop.position = CGPoint(x:size.width/2,y:size.height/2)
        world.xScale = size.width/450; world.yScale = size.height/500
    }
    func start() {
        nodes.values.forEach { $0.removeFromParent() }; nodes.removeAll()
        bossNodes.values.forEach { $0.removeFromParent() }; bossNodes.removeAll()
        game.start(); finished = false; score = 0; combo = 0; health = game.hp; lastUpdate = nil; lastHUD = 0; bossText = ""
        isPaused = false; render()
        if game.status == .finished { finishRun() }
    }
    func pause(_ value: Bool) { isPaused = value; lastUpdate = nil }
    func finishRun() {
        guard !finished else { return }
        game.finish(); score = game.score; combo = game.combo; health = game.hp; finished = true; isPaused = true
        onFinish?(GameScore(game:.shooting,score:game.score,maxCombo:game.maxCombo))
    }
    func move(_ normalized: Double) { game.move(to: 70 + min(1,max(0,normalized))*290); renderPlayer() }
    override func update(_ currentTime: TimeInterval) {
        guard !isPaused, !finished else { lastUpdate = nil; return }
        defer { lastUpdate = currentTime }
        guard let lastUpdate else { return }
        game.advance(seconds: currentTime-lastUpdate); render()
        if currentTime-lastHUD >= 0.1 || game.status == .finished {
            score = game.score; combo = game.combo; health = game.hp
            bossText = game.bosses.map { "보스 \($0.stage) · \(Int(ceil($0.remaining)))초 · \(Int(max(0,$0.hp)/$0.maxHP*100))%" }.joined(separator:" / ")
            lastHUD = currentTime
        }
        if game.status == .finished {
            finishRun()
        }
    }
    private func renderPlayer() { player.position = CGPoint(x:game.playerX,y:130) }
    private func render() {
        renderPlayer()
        let ids = Set(game.entities.map(\.id))
        for id in Array(nodes.keys) where !ids.contains(id) { nodes.removeValue(forKey:id)?.removeFromParent() }
        for entity in game.entities {
            let node: SKSpriteNode
            if let existing = nodes[entity.id] { node = existing }
            else {
                node = SKSpriteNode(texture:textures[entity.kind])
                if entity.kind == .laser { node.color = .cyan; node.size = CGSize(width:4,height:15) }
                else if entity.kind == .enemyLaser || entity.kind == .bossLaser { node.color = entity.kind == .bossLaser ? .red : .green; node.size = CGSize(width:9,height:9) }
                else { node.size = CGSize(width:entity.kind == .trash ? 50 : 40,height:entity.kind == .meteor ? 60 : 40) }
                if let frames = animatedTextures[entity.kind] { node.run(.repeatForever(.animate(with:frames,timePerFrame:0.1))) }
                world.addChild(node); nodes[entity.id] = node
            }
            node.position = CGPoint(x:entity.x,y:500-entity.y)
        }
        let stages = Set(game.bosses.map(\.stage))
        for stage in Array(bossNodes.keys) where !stages.contains(stage) { bossNodes.removeValue(forKey:stage)?.removeFromParent() }
        for boss in game.bosses {
            let node: SKSpriteNode
            if let existing = bossNodes[boss.stage] { node = existing }
            else {
                let image = boss.stage == 1 ? "meteorite_boss_round1" : (boss.stage == 2 ? "shootinggame_satelite_1" : "shootinggame_stage3_boss_1")
                node = SKSpriteNode(imageNamed:"stepmate_game_"+image)
                let names = boss.stage == 1 ? ["meteorite_boss_round1","meteorite_boss_round1_2"] : (1...3).map { (boss.stage == 2 ? "shootinggame_satelite_" : "shootinggame_stage3_boss_") + String($0) }
                node.run(.repeatForever(.animate(with:names.map { SKTexture(imageNamed:"stepmate_game_"+$0) },timePerFrame:0.15)))
                node.size = CGSize(width:boss.stage == 1 ? 450 : (boss.stage == 2 ? 135 : 72),height:boss.stage == 3 ? 54 : 80)
                node.anchorPoint = CGPoint(x:0.5,y:1); world.addChild(node); bossNodes[boss.stage] = node
            }
            node.position = CGPoint(x:boss.stage == 1 ? 225 : boss.x,y:500-boss.y)
        }
    }
}

struct WatchShootingGameView: View {
    @StateObject private var scene: ShootingScene
    @StateObject private var result: WatchGameResultModel
    @State private var started = false
    @State private var paused = false
    @State private var crown = 0.5
    @State private var ending = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var dimmed
    init(pet: PetProfile?, services: WatchGameServices) {
        _scene = StateObject(wrappedValue:ShootingScene(pet:pet))
        _result = StateObject(wrappedValue:WatchGameResultModel(services:services))
    }
    var body: some View {
        Group {
            if scene.finished { WatchGameResultView(model:result,replay:{ result.clear(); scene.start(); paused = false; crown = 0.5 }) }
            else if !started {
                ScrollView {
                    VStack(spacing:6) {
                        Text("지구를 지켜라").font(.headline)
                        Text("크라운·드래그로 좌우 이동\n자동 발사 · 펫 능력치 적용").font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        Text("공격 \(scene.game.attack) · 체력 \(scene.game.initialHP)").font(.caption2).fixedSize(horizontal: false, vertical: true)
                        if let best = result.best { Text("최고 기록 \(best.score)점").font(.caption2).foregroundStyle(.secondary) }
                        Button("시작") { paused = false; started = true; scene.start() }.buttonStyle(WatchActionStyle()).accessibilityIdentifier("game.start")
                    }
                    .frame(maxWidth: .infinity).padding(.horizontal, 6).padding(.bottom, 8)
                }.scrollBounceBehavior(.basedOnSize)
            } else {
                ZStack(alignment:.top) {
                    arena
                    VStack(spacing:4) {
                        HStack { Text("\(scene.score)점"); Spacer(); Text("♥ \(WatchNumber.compact(scene.health))").foregroundStyle(.pink).accessibilityLabel("체력 \(scene.health)") }.font(.caption2).monospacedDigit().lineLimit(1)
                        Text("\(scene.combo) COMBO!").font(.caption2).foregroundStyle(.cyan).monospacedDigit()
                            .accessibilityIdentifier("game.combo")
                        Spacer()
                        Text(scene.bossText.isEmpty ? "크라운 · 좌우 이동" : scene.bossText).font(.caption2).lineLimit(2)
                    }.padding(6).allowsHitTesting(false)
                }
                .overlay { if paused { Button("계속하기") { paused = false; scene.pause(false) }.buttonStyle(.borderedProminent).accessibilityIdentifier("game.resume") } }
                .focusable().digitalCrownRotation($crown,from:0,through:1,sensitivity:.low,isContinuous:false,isHapticFeedbackEnabled:false)
                .onChange(of:crown) { _,value in if !paused { scene.move(value) } }
            }
        }
        .navigationTitle(scene.finished ? "결과" : "슈팅")
        .navigationBarBackButtonHidden(started && !scene.finished)
        .task { await result.loadBest(.shooting) }
        .toolbar {
            if started && !scene.finished {
                ToolbarItem(placement:.topBarLeading) {
                    Button { paused = true; scene.pause(true); ending = true } label: { Image(systemName:"xmark") }
                        .accessibilityLabel("기록을 남기고 마치기").accessibilityIdentifier("game.finish")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { paused.toggle(); scene.pause(paused) } label: { Image(systemName:paused ? "play.fill" : "pause.fill") }
                        .accessibilityLabel(paused ? "계속하기" : "일시정지")
                        .accessibilityIdentifier("game.pause")
                }
            }
        }
        .alert("현재 기록으로 마칠까요?",isPresented:$ending) {
            Button("기록 남기고 마치기") { scene.finishRun() }
            Button("계속하기",role:.cancel) { paused = false; scene.pause(false) }
        }
        .onAppear { scene.onFinish = { result.finish($0) } }
        .onChange(of:phase) { _,value in if value != .active { paused = true; scene.pause(true) } }
        .onChange(of:dimmed) { _,value in if value { paused = true; scene.pause(true) } }
        .onDisappear { scene.pause(true); scene.onFinish = nil; result.stop() }
    }
    private var arena: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene:scene,isPaused:paused || phase != .active || dimmed,preferredFramesPerSecond:30)
                    .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { event in
                    guard !paused else { return }
                    let normalized = Double(event.location.x / max(CGFloat(1),geometry.size.width))
                    crown = min(1.0,max(0.0,normalized)); scene.move(crown)
                })
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("슈팅 게임 영역")
                .accessibilityValue("좌우 위치 \(Int(crown * 100))%")
                .accessibilityIdentifier("game.shootingArena")
                .accessibilityAdjustableAction(adjust)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard !paused else { return }
        switch direction {
        case .increment: crown = min(1.0,crown + 0.1)
        case .decrement: crown = max(0.0,crown - 0.1)
        @unknown default: return
        }
        scene.move(crown)
    }
}
