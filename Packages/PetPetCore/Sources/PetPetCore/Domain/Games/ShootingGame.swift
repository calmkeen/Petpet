import Foundation

public enum ShootingEntityKind: String, Sendable {
    case meteor, star, trash, alien, laser, enemyLaser, bossLaser, speed, heal, attack, wipe
}
public struct ShootingEntity: Sendable, Identifiable {
    public let id: Int
    public let kind: ShootingEntityKind
    public var x: Double
    public var y: Double
    public var hp: Double
    public var vx: Double = 0
    public var vy: Double = 0
    public var lastFire: Double = 0
}
public struct ShootingBoss: Sendable {
    public let stage: Int
    public var x: Double
    public var y: Double
    public var hp: Double
    public let maxHP: Double
    public var remaining: Double
    public var age: Double = 0
    public var burst: Double = 0
    public var summon: Double = 0
    public var direction: Double = 1
    public var phase: Int { hp / maxHP <= 0.35 ? 3 : (hp / maxHP <= 0.7 ? 2 : 1) }
}

/// Android's 450×500 logical playfield, advanced at a fixed 60Hz regardless of display refresh rate.
/// Defense is intentionally unused by Android's damage rules; gameplay never consumes pet health.
public struct ShootingGame: Sendable {
    public private(set) var status: MiniGameStatus = .ready
    public private(set) var playerX = 215.0
    public private(set) var hp: Int64
    public let initialHP: Int64
    public let attack: Int64
    public var baseAttack: Double { Double(attack) }
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var entities: [ShootingEntity] = []
    public private(set) var bosses: [ShootingBoss] = []
    public private(set) var speedMultiplier = 1.0
    public private(set) var attackMultiplier = 1.0
    public private(set) var elapsed = 0.0
    private var spawned: Set<Int> = []
    private var defeated: Set<Int> = []
    private var accumulator = 0.0
    private var lastFire = -1.0
    private var nextID = 0
    private var random: GameRandom

    public init(attack: Int64, health: Int64, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.attack = max(0, attack); initialHP = max(1, health); hp = initialHP
        random = GameRandom(seed: seed)
    }
    public mutating func start() {
        status = .playing; hp = initialHP; score = 0; combo = 0; maxCombo = 0
        playerX = 215; entities = []; bosses = []; spawned = []; defeated = []
        elapsed = 0; accumulator = 0; lastFire = -1; speedMultiplier = 1; attackMultiplier = 1
    }
    public mutating func move(to x: Double) { if x.isFinite { playerX = min(360, max(70, x)) } }
    public mutating func finish() { status = .finished }
    public mutating func advance(seconds: Double) {
        guard status == .playing, seconds.isFinite, seconds > 0 else { return }
        accumulator += min(seconds, 0.25)
        while accumulator + 1e-10 >= 1.0 / 60, status == .playing {
            accumulator -= 1.0 / 60; tick()
        }
    }
    public mutating func apply(_ kind: ShootingEntityKind) {
        switch kind {
        case .speed: speedMultiplier = min(100, speedMultiplier * 1.2)
        case .attack: attackMultiplier = min(1e9, attackMultiplier * 1.2)
        case .heal: hp = initialHP-hp <= 20 ? initialHP : hp+20
        case .wipe:
            score += entities.filter { $0.kind == .meteor }.count
            entities.removeAll { [.meteor, .star, .trash, .alien, .enemyLaser, .bossLaser].contains($0.kind) }
        default: break
        }
    }
    private mutating func add(_ kind: ShootingEntityKind, x: Double? = nil, y: Double = -100, hp: Double = 1, vx: Double = 0, vy: Double = 0) {
        nextID += 1
        let position = x ?? (70 + random.unit() * 290)
        entities.append(ShootingEntity(id: nextID, kind: kind, x: position, y: y, hp: hp, vx: vx, vy: vy, lastFire: elapsed))
    }
    private mutating func award(_ points: Int, combos: Int = 1, speedBonus: Bool = true) {
        score += points; combo += combos; maxCombo = max(maxCombo, combo)
        if speedBonus, combo > 0, combo % 100 == 0 { speedMultiplier = min(100, speedMultiplier * 1.2) }
    }
    private mutating func damage(_ amount: Int64) { hp -= min(hp,max(0,amount)); combo = 0 }
    private mutating func tick() {
        elapsed += 1.0 / 60
        if random.unit() < 0.02 { add(.meteor, y: 0, hp: 50) }
        if random.unit() < 0.01 { add(.star) }
        if score > 250, random.unit() < 0.01 { add(.trash, hp: 220) }
        if defeated.contains(2), entities.filter({ $0.kind == .alien }).count < 5, random.unit() < 0.02 { add(.alien, y: -80, hp: 500) }
        if random.unit() < 0.005 {
            let kinds: [ShootingEntityKind] = [.speed, .heal, .attack, .wipe]
            add(kinds[min(3, Int(random.unit() * 4))])
        }
        if elapsed - lastFire >= max(1.0 / 60, 0.4 / speedMultiplier) {
            add(.laser, x: playerX, y: 350); lastFire = elapsed
        }
        let snapshot = entities.map(\.id)
        for id in snapshot {
            guard let i = entities.firstIndex(where: { $0.id == id }) else { continue }
            switch entities[i].kind {
            case .laser: entities[i].y -= 8
            case .meteor: entities[i].y += 2.5
            case .star: entities[i].y += 5
            case .trash: entities[i].y += 4
            case .alien:
                entities[i].y = min(45, entities[i].y + 2.6)
                if elapsed - entities[i].lastFire >= 1.4 {
                    let e = entities[i]; entities[i].lastFire = elapsed
                    aim(x: e.x, y: e.y + 18, speed: 6, boss: false)
                }
            case .enemyLaser, .bossLaser:
                entities[i].x += entities[i].vx; entities[i].y += entities[i].vy
            default: entities[i].y += 3
            }
            guard let index = entities.firstIndex(where: { $0.id == id }) else { continue }
            let e = entities[index]
            if [.meteor, .star, .trash, .alien].contains(e.kind) {
                if let laser = entities.firstIndex(where: { $0.kind == .laser && abs($0.x-e.x) < (e.kind == .meteor ? 30 : 25) && (e.kind == .alien ? ($0.y >= e.y && $0.y <= e.y+36) : abs($0.y-e.y) < 30) }) {
                    let laserID = entities[laser].id
                    let attack = floor(baseAttack * attackMultiplier)
                    entities[index].hp -= e.kind == .alien ? max(1, attack - 50) : attack
                    let dead = entities[index].hp <= 0
                    entities.removeAll { $0.id == laserID || (dead && $0.id == id) }
                    if dead { award(e.kind == .meteor ? 1 : (e.kind == .star ? 2 : (e.kind == .trash ? 3 : 10)), speedBonus: e.kind != .alien) }
                } else if e.y > (e.kind == .meteor ? 400 : 500) {
                    damage(e.kind == .meteor ? 1 : (e.kind == .star ? 2 : 3)); entities.removeAll { $0.id == id }
                }
            } else if [.enemyLaser, .bossLaser].contains(e.kind), abs(e.x-playerX) < 20, (330...390).contains(e.y) {
                damage(e.kind == .bossLaser ? 3 : 2); entities.removeAll { $0.id == id }
            } else if [.speed, .attack, .heal, .wipe].contains(e.kind), abs(e.x-playerX) < 40, e.y > 350 {
                apply(e.kind); entities.removeAll { $0.id == id }
            }
        }
        entities.removeAll { $0.y < -200 || $0.y > 500 || $0.x < 0 || $0.x > 450 }
        for (stage, threshold, health, y, limit) in [(1,100,5000.0,-100.0,30.0),(2,450,100000.0,-150.0,30.0),(3,1100,300000.0,-120.0,60.0)] {
            if score >= threshold, !spawned.contains(stage) {
                spawned.insert(stage)
                bosses.append(ShootingBoss(stage: stage, x: 215, y: y, hp: health, maxHP: health, remaining: limit))
            }
        }
        updateBosses()
        if hp <= 0 { finish() }
    }
    private mutating func aim(x: Double, y: Double, speed: Double, boss: Bool) {
        let dx = playerX - x, dy = 350-y, distance = max(0.001, hypot(dx, dy))
        add(boss ? .bossLaser : .enemyLaser, x: x, y: y, vx: dx / distance * speed, vy: dy / distance * speed)
    }
    private mutating func updateBosses() {
        for stage in bosses.map(\.stage) {
            guard let i = bosses.firstIndex(where: { $0.stage == stage }) else { continue }
            bosses[i].age += 1.0 / 60
            let targetY = stage == 1 ? 50.0 : (stage == 2 ? 40 : 36)
            if stage != 2 || bosses[i].y >= targetY { bosses[i].remaining -= 1.0 / 60 }
            if bosses[i].remaining <= 0 { hp = 0; return }
            if bosses[i].y < targetY { bosses[i].y = min(targetY, bosses[i].y + (stage == 1 ? 1.5 : (stage == 2 ? 0.8 : 2.2))) }
            else if stage == 2 { bosses[i].x = 215 + sin(bosses[i].age * 1.5) * 150.5 }
            else if stage == 3 {
                bosses[i].x += bosses[i].direction * 2.5
                if bosses[i].x <= 70 || bosses[i].x >= 360 { bosses[i].direction *= -1; bosses[i].x = min(360,max(70,bosses[i].x)) }
            }
            let b = bosses[i]
            let hits = entities.filter { $0.kind == .laser && (stage == 1 || abs($0.x-b.x) < (stage == 2 ? 67.5 : 36)) && $0.y >= b.y && $0.y <= b.y + (stage == 3 ? 54 : 80) }
            let defense = stage == 3 ? (b.phase == 1 ? 24.0 : (b.phase == 2 ? 12 : 0)) : 0
            bosses[i].hp -= Double(hits.count) * max(stage == 3 ? 1 : 0, floor(baseAttack * attackMultiplier) - defense)
            let hitIDs = Set(hits.map(\.id)); entities.removeAll { hitIDs.contains($0.id) }
            if bosses[i].hp <= 0 {
                bosses.remove(at: i); defeated.insert(stage)
                if stage == 3 { award(250, combos: 10, speedBonus: false) } else { score += stage == 1 ? 100 : 200 }
                continue
            }
            if stage == 3 {
                bosses[i].burst += 1.0 / 60; bosses[i].summon += 1.0 / 60
                let phase = bosses[i].phase
                if bosses[i].burst >= (phase == 1 ? 2 : (phase == 2 ? 1.6 : 1.2)) {
                    bosses[i].burst = 0
                    let count = phase == 1 ? 6 : (phase == 2 ? 9 : 12)
                    for shot in 0..<count {
                        let angle = Double(shot) * .pi * 2 / Double(count) + sin(elapsed / 0.3) * 0.25
                        add(.bossLaser, x: b.x, y: b.y+28, vx: cos(angle)*6, vy: sin(angle)*6)
                    }
                    aim(x: b.x, y: b.y+28, speed: 7.8, boss: true)
                }
                if bosses[i].summon >= (phase == 1 ? 3 : (phase == 2 ? 2.4 : 1.8)) {
                    bosses[i].summon = 0
                    for _ in 0..<(phase == 1 ? 1 : 2) where entities.filter({ $0.kind == .alien }).count < 5 { add(.alien, y: -80, hp: 500) }
                }
            }
        }
    }
}
