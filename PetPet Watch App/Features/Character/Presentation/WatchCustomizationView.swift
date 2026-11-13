import SwiftUI
import PetPetCore

@MainActor
struct WatchCustomizationView: View {
    @ObservedObject var model: WatchCustomizationModel
    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let background = model.selection.background(at: context.date)
                    ZStack {
                        Image(background.imageName).resizable().scaledToFill()
                        Image(PetSpriteAnimation(.idle, characterID: model.selection.character.id).posterImageName)
                            .resizable().scaledToFit().padding(8)
                    }.frame(height: 112).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("\(model.selection.character.name) 꾸미기 미리보기")
                }
            }
            Section("캐릭터") {
                ForEach(PetCustomizationCatalog.characters) { character in
                    Button { Task { await model.selectCharacter(character.id) } } label: {
                        choice(character.name, detail: character.detail, selected: model.selection.character.id == character.id)
                    }.accessibilityIdentifier("customization.character.\(character.id)")
                }
            }.disabled(!model.hasLoaded || model.busy)
            Section("홈 배경") {
                ForEach(PetCustomizationCatalog.backgrounds) { background in
                    Button { Task { await model.selectBackground(background.id) } } label: {
                        HStack {
                            Image(systemName: background.symbol).frame(width: 20).accessibilityHidden(true)
                            choice(background.name, selected: PetCustomizationCatalog.background(id: model.selection.backgroundID).id == background.id)
                        }
                    }.accessibilityIdentifier("customization.background.\(background.id)")
                }
            }.disabled(!model.hasLoaded || model.busy)
            Section {
                NavigationLink("동작 미리보기") { WatchMotionPreviewView(model: model) }
                    .frame(minHeight: 44).accessibilityIdentifier("customization.openMotions")
                Text("캐릭터를 바꿔도 레벨과 먹이, 걸음 기록은 유지돼요.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("선택한 모습은 다음 동기화 때 아이폰에도 반영돼요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.busy { ProgressView("저장 중") }
            if let message = model.message {
                Text(message).font(.caption2).accessibilityIdentifier("customization.feedback")
            }
            if let error = model.error {
                Text(error).font(.caption2).foregroundStyle(.orange).accessibilityIdentifier("customization.error")
                if !model.hasLoaded {
                    Button("다시 불러오기") { Task { await model.load() } }.frame(minHeight: 44)
                }
            }
        }.navigationTitle("꾸미기").task { await model.load() }
    }
    private func choice(_ name: String, detail: String? = nil, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true) }
        }.frame(minHeight: 44).contentShape(Rectangle())
            .accessibilityElement(children: .combine).accessibilityValue(selected ? "선택됨" : "")
    }
}

@MainActor
private struct WatchMotionPreviewView: View {
    @ObservedObject var model: WatchCustomizationModel
    @State private var motionID = "greeting"
    @State private var replay = UUID()
    @State private var state = PetAnimationState()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var clip: PetMotionClip { model.selection.character.motion(id: motionID) }
    private var playbackKey: String { "\(model.selection.character.id):\(clip.id):\(replay):\(phase == .active)" }

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let background = model.selection.background(at: context.date)
                    WatchPetSpriteView(state: state, backgroundImageName: background.imageName,
                                       characterID: model.selection.character.id, motionID: clip.id)
                        .frame(height: 116).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(clip.name).font(.headline)
                if reduceMotion { Text("동작 줄이기가 켜져 있어 정지 자세로 보여요.").font(.caption2) }
                Button("다시 보기") { replay = UUID() }.frame(minHeight: 44)
                    .accessibilityIdentifier("customization.replayMotion")
            }
            Section("동작 선택") {
                ForEach(model.selection.character.motions) { motion in
                    Button { motionID = motion.id; replay = UUID() } label: {
                        HStack {
                            Text(motion.name).frame(maxWidth: .infinity, alignment: .leading)
                            if clip.id == motion.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.frame(minHeight: 44)
                    }.accessibilityValue(clip.id == motion.id ? "선택됨" : "")
                        .accessibilityIdentifier("customization.motion.\(motion.id)")
                }
            }
            Text("미리보기는 걸음수나 애정도를 바꾸지 않아요.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("동작 보기")
            .task(id: playbackKey) {
                state.setActive(false, at: Date())
                guard phase == .active else { return }
                state = .preview(.running)
                do { try await Task.sleep(for: .seconds(clip.loops ? 3 : clip.duration)) } catch { return }
                state.setActive(false, at: Date())
            }
            .onDisappear { state.setActive(false, at: Date()) }
    }
}
