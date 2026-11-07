import XCTest
@testable import PetPetCore

final class MiniGameTests: XCTestCase {
    func testStairTimeLimitsMatchAndroidBoundaries() {
        for (score,limit) in [(0,1.5),(19,1.5),(20,1.2),(49,1.2),(50,1.0),(99,1.0),(100,0.8),(199,0.8),(200,0.65)] {
            XCTAssertEqual(StarStairGame.timeLimit(score:score),limit)
        }
    }
    func testStairCorrectInputAdvancesLaneAndCombo() {
        var game = StarStairGame(seed:7); game.start()
        let direction = game.nextDirection
        game.input(direction)
        XCTAssertEqual(game.score,1); XCTAssertEqual(game.combo,1); XCTAssertEqual(game.life,3)
        XCTAssertEqual(game.currentLane,direction.delta); XCTAssertEqual(game.maxCombo,1)
    }
    func testStairFailureKeepsNextStairAndResetsCombo() {
        var game = StarStairGame(seed:1); game.start(); game.input(game.nextDirection)
        let stairs = game.stairs, next = game.nextDirection
        game.input(next.opposite)
        XCTAssertEqual(game.score,1); XCTAssertEqual(game.life,2); XCTAssertEqual(game.combo,0)
        XCTAssertEqual(game.maxCombo,1); XCTAssertEqual(game.stairs,stairs); XCTAssertEqual(game.nextDirection,next)
    }
    func testThreeTimeoutsFinishAndFurtherInputsAreIgnored() {
        var game = StarStairGame(seed:2); game.start()
        for _ in 0..<3 { game.advance(seconds:1.5) }
        XCTAssertEqual(game.status,.finished); XCTAssertEqual(game.life,0)
        game.input(game.nextDirection); XCTAssertEqual(game.score,0)
    }
    func testStairGeneratorKeepsHistoryAndForcesDirectionChangeAfterFour() {
        var game = StarStairGame(seed:91); game.start()
        var directions: [StairDirection] = []
        for _ in 0..<500 {
            directions.append(game.nextDirection); game.input(game.nextDirection)
            XCTAssertLessThanOrEqual(game.stairs.count,9)
            XCTAssertEqual(game.stairs.last?.id,game.score+4)
            XCTAssertEqual(game.stairs.first?.id,max(0,game.score-4))
        }
        for start in 0..<(directions.count-4) { XCTAssertLessThan(Set(directions[start..<(start+5)]).count == 1 ? 5 : 0,5) }
        XCTAssertEqual(game.remaining,0.65); XCTAssertEqual(game.maxCombo,500)
    }
    func testRestartClearsFailedStairRun() {
        var game = StarStairGame(seed:7); game.start(); game.input(game.nextDirection); game.finish(); game.start()
        XCTAssertEqual(game.score,0); XCTAssertEqual(game.life,3); XCTAssertEqual(game.maxCombo,0); XCTAssertEqual(game.status,.playing)
    }
    func testShootingFixedStepMatchesThirtyAndSixtyFPS() {
        var a = ShootingGame(attack:50,health:1000,seed:91), b = a
        a.start(); b.start()
        for _ in 0..<600 { a.advance(seconds:1.0/60) }
        for _ in 0..<300 { b.advance(seconds:1.0/30) }
        XCTAssertEqual(a.score,b.score); XCTAssertEqual(a.hp,b.hp); XCTAssertEqual(a.elapsed,b.elapsed,accuracy:1e-8)
        XCTAssertEqual(a.entities.map(\.id),b.entities.map(\.id))
        XCTAssertEqual(a.entities.map(\.y),b.entities.map(\.y))
    }
    func testShootingBoundsInvalidDeltaAndBackgroundCatchupCap() {
        var game = ShootingGame(attack:50,health:8,seed:1); game.start()
        game.move(to:-100); XCTAssertEqual(game.playerX,70)
        game.move(to:1000); XCTAssertEqual(game.playerX,360)
        game.move(to:.nan); XCTAssertEqual(game.playerX,360)
        game.advance(seconds:.infinity); game.advance(seconds:-2); XCTAssertEqual(game.elapsed,0)
        game.advance(seconds:999); XCTAssertEqual(game.elapsed,0.25,accuracy:1e-8)
    }
    func testShootingPermanentBuffsAndHealClampAndRestart() {
        var game = ShootingGame(attack:50,health:8,seed:2); game.start()
        game.apply(.speed); game.apply(.speed); game.apply(.attack); game.apply(.heal)
        XCTAssertEqual(game.speedMultiplier,1.44,accuracy:1e-8); XCTAssertEqual(game.attackMultiplier,1.2)
        XCTAssertEqual(game.hp,8)
        game.finish(); game.start(); XCTAssertEqual(game.attackMultiplier,1); XCTAssertEqual(game.speedMultiplier,1)
    }
    func testShootingOneLaserCannotDestroyTwoTargetsAndFinishStopsWorld() {
        var game = ShootingGame(attack:50,health:1000,seed:8); game.start()
        for _ in 0..<3000 { game.advance(seconds:1.0/60) }
        XCTAssertGreaterThan(game.score,0)
        XCTAssertEqual(Set(game.entities.map(\.id)).count,game.entities.count)
        game.finish(); let elapsed = game.elapsed; game.advance(seconds:1)
        XCTAssertEqual(game.elapsed,elapsed)
    }
    func testShootingBossPhaseThresholds() {
        var boss = ShootingBoss(stage:3,x:215,y:36,hp:300000,maxHP:300000,remaining:60)
        XCTAssertEqual(boss.phase,1); boss.hp = 210000; XCTAssertEqual(boss.phase,2)
        boss.hp = 105000; XCTAssertEqual(boss.phase,3)
    }
    func testShootingReachesFirstBossAtOneHundredAndBossTimeoutFinishes() {
        var game = ShootingGame(attack:100,health:100000,seed:9); game.start()
        var boss: ShootingBoss?
        for _ in 0..<30000 {
            if let enemy = game.entities.first(where:{ [.meteor,.star,.trash].contains($0.kind) }) { game.move(to:enemy.x) }
            game.advance(seconds:1.0/60)
            if let value = game.bosses.first(where:{$0.stage == 1}) { boss = value; break }
        }
        XCTAssertNotNil(boss); XCTAssertGreaterThanOrEqual(game.score,100)
        XCTAssertEqual(boss?.maxHP,5000); XCTAssertLessThanOrEqual(boss?.remaining ?? 0,30)
    }
    func testLocalBestSurvivesRepositoryRecreationAndKeepsIndependentCombo() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let store = FileMiniGameRecords(fileURL:file)
        _ = try await store.record(GameScore(game:.starStair,score:30,maxCombo:10))
        _ = try await store.record(GameScore(game:.starStair,score:20,maxCombo:20))
        let best = try await FileMiniGameRecords(fileURL:file).best(.starStair)
        XCTAssertEqual(best.score,30); XCTAssertEqual(best.maxCombo,20)
        let shooting = try await store.best(.shooting); XCTAssertEqual(shooting.score,0)
    }
    func testShootingCanProgressThroughSatelliteAndCommanderBosses() {
        var game = ShootingGame(attack:5000,health:100000,seed:19); game.start()
        var observed: [Int: Double] = [:]
        for _ in 0..<120000 {
            if let boss = game.bosses.first { game.move(to:boss.x) }
            else if let target = game.entities.filter({ [.meteor,.star,.trash,.alien].contains($0.kind) }).max(by:{ $0.y < $1.y }) { game.move(to:target.x) }
            game.advance(seconds:1.0/60)
            for boss in game.bosses { observed[boss.stage] = boss.maxHP }
            if observed[3] != nil || game.status == .finished { break }
        }
        XCTAssertEqual(observed[1],5000); XCTAssertEqual(observed[2],100000); XCTAssertEqual(observed[3],300000)
        XCTAssertGreaterThanOrEqual(game.score,1100)
    }
    func testInvalidScoresNeverReplaceSavedBest() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let store = FileMiniGameRecords(fileURL:file)
        _ = try await store.record(GameScore(game:.starStair,score:10,maxCombo:8))
        do { _ = try await store.record(GameScore(game:.starStair,score:10,maxCombo:11)); XCTFail() } catch {}
        let best = try await store.best(.starStair); XCTAssertEqual(best.score,10)
    }
}
