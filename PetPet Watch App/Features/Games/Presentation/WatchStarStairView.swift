import SwiftUI
import WatchKit
import PetPetCore

struct WatchStarStairView: View {
    @State private var game = StarStairGame()
    @State private var paused = false
    @State private var lastTick: TimeInterval?
    @State private var crown = 0.0
    @State private var ending = false
    @StateObject private var result: WatchGameResultModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var dimmed
    init(services: WatchGameServices) { _result = StateObject(wrappedValue: WatchGameResultModel(services: services)) }
    var body: some View {
        Group {
            if game.status == .finished {
                WatchGameResultView(model: result, replay: { result.clear(); game.start(); paused = false; lastTick = nil })
            } else if game.status == .ready {
                ScrollView {
                    VStack(spacing: 6) {
                        Text("별계단 훈련").font(.headline)
                        Text("다음 계단 방향을 눌러요.\n목숨 3개, 올라갈수록 빨라져요.").font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        if let best = result.best { Text("최고 \(best.score)계단 · 콤보 \(best.maxCombo)").font(.caption2).foregroundStyle(.secondary) }
                        Button("시작") { paused = false; game.start(); lastTick = nil }.buttonStyle(WatchActionStyle()).accessibilityIdentifier("game.start")
                    }
                    .frame(maxWidth: .infinity).padding(.horizontal, 6).padding(.bottom, 8)
                }.scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(spacing: 4) {
                    HStack { Text("\(game.score)계단 · \(game.combo)콤보"); Spacer(); Text(String(repeating: "♥", count: game.life)).foregroundStyle(.pink) }.font(.caption2).monospacedDigit()
                    ProgressView(value: game.remaining, total: game.timeLimit).tint(game.remaining < 0.4 ? .red : .cyan)
                    stairCanvas.frame(maxHeight: .infinity)
                    HStack {
                        Button { input(.left) } label: { Image(systemName: "arrow.up.left").frame(maxWidth:.infinity,minHeight:44).background(.gray.opacity(0.35),in:Capsule()) }.accessibilityLabel("왼쪽 계단").accessibilityIdentifier("game.stairsLeft")
                        Button { input(.right) } label: { Image(systemName: "arrow.up.right").frame(maxWidth:.infinity,minHeight:44).background(.gray.opacity(0.35),in:Capsule()) }.accessibilityLabel("오른쪽 계단").accessibilityIdentifier("game.stairsRight")
                    }.buttonStyle(.plain).disabled(paused)
                }.padding(.horizontal, 8)
                    .overlay { if paused { Button("계속하기") { paused = false; lastTick = nil }.buttonStyle(.borderedProminent).accessibilityIdentifier("game.resume") } }
                    .focusable().digitalCrownRotation($crown, from: -10000, through: 10000, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onChange(of: crown) { old, new in if !paused { input(new > old ? .right : .left) } }
            }
        }
        .navigationTitle(game.status == .finished ? "결과" : "별계단")
        .navigationBarBackButtonHidden(game.status == .playing)
        .task { await result.loadBest(.starStair) }
        .toolbar {
            if game.status == .playing {
                ToolbarItem(placement:.topBarLeading) {
                    Button { paused = true; lastTick = nil; ending = true } label: { Image(systemName:"xmark") }
                        .accessibilityLabel("기록을 남기고 마치기").accessibilityIdentifier("game.finish")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { paused.toggle(); lastTick = nil } label: { Image(systemName:paused ? "play.fill" : "pause.fill") }
                        .accessibilityLabel(paused ? "계속하기" : "일시정지")
                        .accessibilityIdentifier("game.pause")
                }
            }
        }
        .alert("현재 기록으로 마칠까요?",isPresented:$ending) {
            Button("기록 남기고 마치기") { game.finish(); finishIfNeeded() }
            Button("계속하기",role:.cancel) { paused = false; lastTick = nil }
        }
        .task(id:isTiming) {
            guard isTiming else { lastTick = nil; return }
            lastTick = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for:.milliseconds(33)) } catch { return }
                guard isTiming else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if let lastTick { game.advance(seconds:now-lastTick) }; lastTick = now
                finishIfNeeded()
            }
        }
        .onChange(of: phase) { _, value in if value != .active { paused = true; lastTick = nil } }
        .onChange(of: dimmed) { _, value in if value { paused = true; lastTick = nil } }
        .onDisappear { paused = true; result.stop() }
    }
    private var isTiming: Bool { game.status == .playing && !paused && phase == .active && !dimmed }
    private var stairCanvas: some View {
        GeometryReader { proxy in
            let stepHeight = max(1,min(21,(proxy.size.height-12)/4))
            let petHeight = min(30,proxy.size.height*0.5)
            ZStack {
                Image("stepmate_game_starstairgame_background1").resizable().scaledToFill().frame(width: proxy.size.width,height: proxy.size.height).clipped()
                ForEach(game.stairs.filter { $0.id >= game.score }) { stair in
                    Image("stepmate_game_startstair_purple").resizable().scaledToFit().frame(width: 30,height: 12)
                        .position(x: proxy.size.width / 2 + CGFloat(stair.lane-game.currentLane) * 21, y: proxy.size.height - 8 - CGFloat(stair.id-game.score)*stepHeight)
                }
                Image("stepmate_fox_idle").resizable().scaledToFit().frame(width:petHeight*0.8,height:petHeight).position(x:proxy.size.width/2,y:proxy.size.height-8-petHeight/2)
                Image(systemName: game.nextDirection == .left ? "arrow.up.left" : "arrow.up.right").font(.caption.bold()).foregroundStyle(.yellow).position(x:proxy.size.width/2,y:12)
                if game.feedback == "SPEED UP!" { Text(game.feedback).font(.caption2.bold()).foregroundStyle(.yellow).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing) }
            }.clipped()
        }.accessibilityElement(children: .ignore).accessibilityLabel("다음 계단 \(game.nextDirection == .left ? "왼쪽" : "오른쪽")")
    }
    private func input(_ direction: StairDirection) {
        guard game.status == .playing, !paused, phase == .active, !dimmed else { return }
        // Charge elapsed time before accepting input so an expired round cannot be rescued between ticks.
        let now = ProcessInfo.processInfo.systemUptime
        let previousLife = game.life
        if let lastTick { game.advance(seconds: now-lastTick) }; lastTick = now
        guard game.status == .playing else { finishIfNeeded(); return }
        guard game.life == previousLife else { WKInterfaceDevice.current().play(.failure); return }
        let life = game.life; game.input(direction)
        if game.life < life { WKInterfaceDevice.current().play(.failure) }
        finishIfNeeded()
    }
    private func finishIfNeeded() {
        if game.status == .finished, result.score == nil { result.finish(GameScore(game: .starStair, score: game.score, maxCombo: game.maxCombo)) }
    }
}
