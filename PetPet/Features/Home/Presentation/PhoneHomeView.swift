import SwiftUI
import PetPetCore

@MainActor
struct PhoneHomeView: View {
    @ObservedObject var viewModel: PhoneHomeViewModel
    @ObservedObject var accountViewModel: AccountViewModel
    @ObservedObject var streakViewModel: PhoneStreakViewModel
    var extras: PhoneExtrasModel?
    @Environment(\.scenePhase) private var scenePhase
    private let green = Color(red: 0.12, green: 0.42, blue: 0.32)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("PetPet", systemImage: "pawprint.fill")
                            .font(.largeTitle.bold()).foregroundStyle(green)
                        Spacer()
                        NavigationLink {
                            PhoneWatchSetupView(viewModel: viewModel)
                        } label: {
                            Image(systemName: "applewatch").font(.title2).frame(width: 44, height: 44)
                        }
                        .foregroundStyle(green).accessibilityLabel("워치 연결·설치 안내")
                        .accessibilityIdentifier("phone.openWatchSetup")
                    }
                    Text("함께 걷고, 함께 자라는 하루")
                        .foregroundStyle(.secondary)
                    if accountViewModel.configuration.isDevelopment {
                        Label("Debug 테스트 모드", systemImage: "hammer.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Label(viewModel.connectionText,
                          systemImage: viewModel.state.connection.isReachable ? "checkmark.circle.fill" : "clock")
                        .font(.footnote).foregroundStyle(green)
                    NavigationLink {
                        AccountView(viewModel: accountViewModel)
                    } label: {
                        HStack {
                            Label("계정 · 서버 백업", systemImage: "icloud")
                            Spacer()
                            Text(accountViewModel.session?.nickname ?? (accountViewModel.session == nil ? "로그인" : "연결됨"))
                                .font(.caption).lineLimit(1).truncationMode(.tail).frame(maxWidth: 120, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .foregroundStyle(green).padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("phone.openAccount")
                    if let extras {
                        NavigationLink { PhoneExtrasView(model:extras,development:accountViewModel.configuration.isDevelopment) } label: {
                            Label("게임 랭킹 · AI 대화",systemImage:"gamecontroller.fill").frame(maxWidth:.infinity,alignment:.leading).padding(16)
                                .background(.background,in:RoundedRectangle(cornerRadius:18))
                        }.buttonStyle(.plain).accessibilityIdentifier("phone.openExtras")
                    }
                    stepsCard
                    PhoneStreakSection(model: streakViewModel, accountID: accountViewModel.session?.accountID)
                    petCard
                    if let snapshot = viewModel.snapshot {
                        card {
                            Text("보유 먹이").font(.headline)
                            HStack {
                                ForEach(FoodCatalog.all) { food in
                                    let quantity = snapshot.inventory.first { $0.foodID == food.id }?.quantity ?? 0
                                    VStack(spacing: 8) {
                                        if food.id == 1 || food.id == 2 {
                                            Image(food.id == 1 ? "stepmate_food_milk" : "stepmate_food_apple")
                                                .resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                                        } else {
                                            Image(systemName: "fork.knife").frame(width: 36, height: 36).accessibilityHidden(true)
                                        }
                                        Text(food.name).foregroundStyle(.secondary)
                                        Text("\(quantity)개").font(.title3.bold()).monospacedDigit().accessibilityIdentifier("phone.food.\(food.id)")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if let receivedAt = viewModel.state.cached?.receivedAt {
                            Text("마지막 동기화 \(receivedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("phone.lastSyncedAt")
                        }
                        Text(viewModel.syncNote).font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { await refreshAll() }
                        } label: {
                            HStack {
                                if viewModel.isRefreshing { ProgressView().tint(.white) }
                                Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(green)
                        .disabled(viewModel.isRefreshing)
                        .accessibilityIdentifier("phone.refreshWatchData")
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .clipped()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refreshAll() }
        }
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

    private func refreshAll() async {
        async let home: Void = viewModel.refresh()
        async let streak: Void = streakViewModel.refresh(accountID: accountViewModel.session?.accountID, force: true)
        _ = await (home, streak)
    }

    private var stepsCard: some View {
        card {
            HStack {
                Label("오늘의 걸음", systemImage: "figure.walk")
                    .font(.headline).foregroundStyle(green)
                Spacer()
                Text(Date(), format: .dateTime.month().day()).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.stepCountText).font(.system(size: 48, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                    .accessibilityIdentifier("phone.stepCount")
                Text("걸음").font(.headline).foregroundStyle(.secondary)
            }
            Text("Apple Watch에서 측정한 하루 걸음수")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var petCard: some View {
        card {
            Text("나의 펫").font(.headline)
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
                HStack(spacing: 20) {
                    PhonePetPortrait()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lv.\(pet.level)").font(.largeTitle.bold())
                            .accessibilityIdentifier("phone.petLevel")
                        Text(moodText(pet.mood)).font(.subheadline).foregroundStyle(green)
                        ProgressView(value: Double(pet.experience), total: Double(pet.level * 2)).tint(green)
                        Text("경험치 \(pet.experience) / \(pet.level * 2)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .accessibilityIdentifier("phone.petExperience")
                    }
                }
                HStack {
                    statistic("공격력", value: pet.attack)
                    statistic("방어력", value: pet.defense)
                    statistic("체력", value: pet.health)
                }
                Divider().padding(.vertical, 4)
                HStack {
                    Label("호감도 \(pet.affection)", systemImage: "heart.fill").foregroundStyle(.pink)
                    Spacer()
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
                    .disabled(viewModel.isServerPetLoading).accessibilityIdentifier("phone.refreshServerPet")
            }
        }
    }

    private func statistic(_ name: String, value: Int64) -> some View {
        VStack(spacing: 5) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted()).font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func moodText(_ mood: PetMood) -> String {
        switch mood {
        case .happy: "행복해요"
        case .sad: "보고 싶었어요"
        case .hungry: "배고파요"
        }
    }
}
