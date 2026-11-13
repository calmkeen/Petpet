import SwiftUI
import PetPetCore

/// Group food and stat editing under the status page, matching Android's flow.
/// Editing lists open on the navigation stack so the Crown can scroll them.
struct PetOverviewView: View {
    @ObservedObject var viewModel: PetProgressViewModel
    @ObservedObject var stepViewModel: WatchHomeViewModel
    @ObservedObject var cloudViewModel: WatchCloudController
    @ObservedObject var customization: WatchCustomizationModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                GeometryReader { geometry in
                    Image(customization.selection.background(at: context.date, automaticPeriod: WatchAppearance.period(at: context.date)).imageName)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.ignoresSafeArea()
                WatchOverviewLayout { compact in summary(compact: compact) }
            }
        }
    }

    private func summary(compact: Bool) -> some View {
        VStack(spacing: 6) {
            if let progress = viewModel.progress {
                HStack(spacing: 6) {
                    NavigationLink { WatchCustomizationView(model: customization) } label: {
                        portrait(progress, compact: compact)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("캐릭터와 배경 꾸미기")
                        .accessibilityHint("캐릭터 선택과 배경, 동작 미리보기를 열어요")
                        .accessibilityIdentifier("watch.customizePet")
                    statistics(progress.pet)
                }
            } else { ProgressView("펫 불러오는 중") }
            careActions
        }
    }

    private func portrait(_ progress: PetProgress, compact: Bool) -> some View {
        VStack(spacing: 2) {
            Image(PetSpriteAnimation(.idle, characterID: customization.selection.character.id).posterImageName).resizable().scaledToFit()
                .frame(width: compact ? 42 : 52, height: compact ? 54 : 66)
                .accessibilityHidden(true)
            HStack(spacing: 3) {
                Text("Lv.\(WatchNumber.compact(progress.pet.level))")
                Image(systemName: "paintbrush.pointed.fill").accessibilityHidden(true)
            }.font(.caption2.bold())
            ProgressView(value: Double(progress.pet.experience), total: Double(progress.experienceRequired)).tint(.blue)
            Text("\(progress.pet.experience) / \(progress.experienceRequired)")
                .font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 1)
    }

    private func statistics(_ pet: PetProfile) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("상태: \(pet.mood.shortName)")
            Text("애정: \(WatchNumber.compact(pet.affection))")
                .accessibilityLabel("애정도 \(pet.affection)")
                .accessibilityIdentifier("watch.affection")
            Text("공격: \(WatchNumber.compact(pet.attack))")
            Text("방어: \(WatchNumber.compact(pet.defense))")
            Text("체력: \(WatchNumber.compact(pet.health))")
        }
        .font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        .padding(5).foregroundStyle(.white)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.8), lineWidth: 1) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var careActions: some View {
        HStack(spacing: 6) {
            NavigationLink("먹이") {
                FoodInventoryView(viewModel: viewModel, stepViewModel: stepViewModel, cloudViewModel: cloudViewModel)
            }.accessibilityIdentifier("watch.manageFoodInventory")
            NavigationLink("스탯") { PetStatisticsView(viewModel: viewModel) }
                .accessibilityIdentifier("watch.managePetStatistics")
        }.buttonStyle(WatchActionStyle(color: .black, backgroundOpacity: 0.75))
    }
}
