import SwiftUI
import PetPetCore

@MainActor
struct PhoneHomeView: View {
    @ObservedObject var viewModel: PhoneHomeViewModel
    @ObservedObject var accountViewModel: AccountViewModel
    @ObservedObject var streakViewModel: PhoneStreakViewModel
    var extras: PhoneExtrasModel?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .largeTitle) private var stepFont = 48

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    connection
                    stepsCard
                    quickLinks
                    petCard
                    if let snapshot = viewModel.snapshot {
                        PhoneCard {
                            PhoneSectionTitle(title: "먹이", icon: "carrot.fill")
                            let columns = Array(repeating: GridItem(.flexible(), alignment: .top), count: textSize.isAccessibilitySize ? 1 : 3)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                ForEach(FoodCatalog.all) { food in
                                    let quantity = snapshot.inventory.first { $0.foodID == food.id }?.quantity ?? 0
                                    VStack(spacing: 8) {
                                        if food.id == 1 || food.id == 2 {
                                            Image(food.id == 1 ? "stepmate_food_milk" : "stepmate_food_apple")
                                                .resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                                        } else {
                                            Image(systemName: "fork.knife").frame(width: 36, height: 36).accessibilityHidden(true)
                                        }
                                        Text(food.name).font(.subheadline).foregroundStyle(.secondary)
                                        Text("\(quantity)개").font(.title3.bold()).monospacedDigit()
                                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("phone.food.\(food.id)")
                                    }.frame(maxWidth: .infinity)
                                }
                            }
                            Text("먹이 주기와 성장은 워치에서 함께해요.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    PhoneStreakSection(model: streakViewModel, accountID: accountViewModel.session?.accountID)
                    Text(viewModel.syncNote).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .padding(16)
            }
            .background(PhoneDesign.background)
            .clipped()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refreshAll() }
        }
        .tint(PhoneDesign.accent)
        .task { await viewModel.start(); await viewModel.refreshServerPet(); await streakViewModel.refresh(accountID: accountViewModel.session?.accountID) }
        .onChange(of: accountViewModel.session?.accountID) { _, id in
            Task { await viewModel.refreshServerPet(force: true) }
            Task { await streakViewModel.refresh(accountID: id, force: true) }
        }
        .onChange(of: accountViewModel.cloudState.lastBackupAt) { _, _ in
            Task { await viewModel.refreshServerPet(force: true) }
            Task { await streakViewModel.refresh(accountID: accountViewModel.session?.accountID, force: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshDate()
                Task { await viewModel.refresh() }
                Task { await streakViewModel.refresh(accountID: accountViewModel.session?.accountID) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in viewModel.refreshDate(); streakViewModel.refreshDate() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in viewModel.refreshDate(); streakViewModel.refreshDate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("PetPet", systemImage: "pawprint.fill").font(.title.bold()).foregroundStyle(PhoneDesign.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                NavigationLink { PhoneWatchSetupView(viewModel: viewModel) } label: { Image(systemName: "applewatch") }
                    .buttonStyle(PhoneIconStyle()).accessibilityLabel("워치 연결·설치 안내")
                    .accessibilityIdentifier("phone.openWatchSetup")
            }
            Text("함께 걷고, 함께 자라는 하루").font(.subheadline).foregroundStyle(.secondary)
            if accountViewModel.configuration.isDevelopment {
                Label("Debug 테스트 모드", systemImage: "hammer.fill").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var connection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(viewModel.connectionText, systemImage: viewModel.state.connection.isReachable ? "checkmark.circle.fill" : "clock")
                    .font(.subheadline).foregroundStyle(PhoneDesign.accent).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("phone.connectionStatus")
                if let receivedAt = viewModel.state.cached?.receivedAt {
                    Text("마지막 동기화 \(receivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("phone.lastSyncedAt")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await refreshAll() } } label: {
                if viewModel.isRefreshing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
            }
            .buttonStyle(PhoneIconStyle()).disabled(viewModel.isRefreshing)
            .accessibilityLabel("지금 동기화").accessibilityIdentifier("phone.refreshWatchData")
        }
    }

    private var quickLinks: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            NavigationLink { AccountView(viewModel: accountViewModel) } label: {
                shortcut("계정·백업", icon: "icloud", detail: accountViewModel.session?.nickname ?? (accountViewModel.session == nil ? "아이폰에서 로그인" : "연결됨"))
            }.accessibilityIdentifier("phone.openAccount")
            if let extras {
                NavigationLink { PhoneExtrasView(model: extras, development: accountViewModel.configuration.isDevelopment, account: accountViewModel) } label: {
                    shortcut("게임·대화", icon: "gamecontroller.fill", detail: "랭킹 · AI 대화")
                }.accessibilityIdentifier("phone.openExtras")
            }
        }.buttonStyle(.plain)
    }

    private func shortcut(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(PhoneDesign.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                .accessibilityLabel(detail)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(14)
        .background(PhoneDesign.surface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    private func refreshAll() async {
        async let home: Void = viewModel.refresh()
        async let streak: Void = streakViewModel.refresh(accountID: accountViewModel.session?.accountID, force: true)
        _ = await (home, streak)
    }

    private var stepsCard: some View {
        PhoneCard {
            VStack(alignment: .leading, spacing: 6) {
                PhoneSectionTitle(title: "오늘의 걸음", icon: "figure.walk")
                Text(Date(), format: .dateTime.month().day()).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.stepCountText).font(.system(size: stepFont, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75).lineLimit(1).monospacedDigit()
                    .accessibilityIdentifier("phone.stepCount")
                Text("걸음").font(.headline).foregroundStyle(.secondary)
            }
            Text(viewModel.todaySteps == nil ? "워치에서 PetPet을 열면 오늘 기록을 받아요." : "Apple Watch에서 측정한 하루 걸음수")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("phone.stepStatus")
        }
    }

    private var petCard: some View {
        PhoneCard {
            PhoneSectionTitle(title: "성장", icon: "chart.bar.fill")
            if let pet = viewModel.displayedPet {
                Label(viewModel.isShowingServerPet ? "서버 백업 기록" : "워치 기록",
                      systemImage: viewModel.isShowingServerPet ? "icloud" : "applewatch")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("phone.petSource")
                if viewModel.isShowingServerPet {
                    Text("서버에 마지막으로 저장된 펫이에요. 현재 워치 상태와 다를 수 있어요.").font(.caption).foregroundStyle(.secondary)
                    if let date = viewModel.serverPet?.fetchedAt {
                        Text("마지막 서버 조회 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                let portraitLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
                portraitLayout {
                    PhonePetPortrait()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lv.\(pet.level)").font(.largeTitle.bold())
                            .accessibilityIdentifier("phone.petLevel")
                        Text(moodText(pet.mood)).font(.subheadline).foregroundStyle(PhoneDesign.accent)
                        ProgressView(value: Double(pet.experience), total: Double(pet.level * 2)).tint(.green)
                        Text("경험치 \(pet.experience) / \(pet.level * 2)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .accessibilityIdentifier("phone.petExperience")
                    }
                }
                let columns = Array(repeating: GridItem(.flexible(), alignment: .top), count: textSize.isAccessibilitySize ? 1 : 3)
                LazyVGrid(columns: columns, spacing: 16) {
                    statistic("공격력", value: pet.attack, id: "attack")
                    statistic("방어력", value: pet.defense, id: "defense")
                    statistic("체력", value: pet.health, id: "health")
                }
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Label("호감도 \(pet.affection)", systemImage: "heart.fill").foregroundStyle(.pink)
                    if !viewModel.isShowingServerPet { Text("스탯 포인트 \(pet.statPoints)").foregroundStyle(.secondary) }
                }
                .font(.caption)
                if let lastFed = pet.lastFedAt {
                    Text("마지막 식사 \(lastFed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if viewModel.isServerPetLoading { ProgressView("펫 기록을 불러오고 있어요") }
                else { Label("워치의 펫을 기다리고 있어요", systemImage: "pawprint").foregroundStyle(.secondary).padding(.vertical, 24) }
            }
            if viewModel.snapshot == nil, let error = viewModel.serverPetError {
                Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("phone.serverPetFeedback")
                Button("서버 펫 다시 불러오기") { Task { await viewModel.refreshServerPet(force: true) } }
                    .buttonStyle(PhoneActionStyle())
                    .disabled(viewModel.isServerPetLoading).accessibilityIdentifier("phone.refreshServerPet")
            }
        }
    }

    private func statistic(_ name: String, value: Int64, id: String) -> some View {
        VStack(spacing: 5) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted()).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("phone.stat.\(id)")
        }.frame(maxWidth: .infinity)
    }

    private func moodText(_ mood: PetMood) -> String {
        switch mood {
        case .happy: "행복해요"
        case .sad: "보고 싶었어요"
        case .hungry: "배고파요"
        }
    }
}
