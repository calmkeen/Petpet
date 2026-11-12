import SwiftUI
import PetPetCore

struct WatchStreakOverview: View {
    @ObservedObject var model: WatchStreakViewModel
    @ObservedObject var cloud: WatchCloudController
    var body: some View {
        WatchOverviewLayout { compact in
          VStack(spacing: 6) {
            if !compact {
                Label("스트릭", systemImage: model.summary.currentDays >= 7 ? "flame.fill" : "calendar").font(.headline)
            }
            Text("연속 \(model.summary.currentDays)일").font(compact ? .headline : .title2.bold())
                .lineLimit(1).accessibilityIdentifier("watch.currentStreak")
            NavigationLink("월별 걸음 기록") { WatchStreakView(model: model, cloud: cloud) }
                .buttonStyle(WatchActionStyle())
                .accessibilityIdentifier("watch.openStreak")
            NavigationLink {
                if cloud.account != nil { WatchNicknameView(editor: cloud.makeNicknameEditor()) }
                else { WatchCloudView(viewModel: cloud) }
            } label: {
                VStack(spacing: 0) {
                    Text(cloud.account == nil ? "로그인 · 계정" : "닉네임 변경").font(.caption2.bold())
                    if let name = cloud.account?.displayName {
                        Text(name).font(.caption2).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .buttonStyle(WatchActionStyle(color: .gray))
            .accessibilityLabel(cloud.account == nil ? "로그인과 계정" : "닉네임 변경")
            .accessibilityValue(cloud.account?.displayName ?? "아이폰에서 로그인해 주세요")
            .accessibilityIdentifier("watch.openNickname")
        }
        }
        .task { await model.appear() }
        .onDisappear { model.disappear() }
    }
}

struct WatchStreakView: View {
    @ObservedObject var model: WatchStreakViewModel
    @ObservedObject var cloud: WatchCloudController
    @State private var selectingMonth = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("\(model.summary.currentDays >= 7 ? "🔥 " : "")연속 \(model.summary.currentDays)일")
                    .font(.headline).accessibilityIdentifier("watch.streakDays")
                Button("\(String(model.month.year))년 \(model.month.month)월") { selectingMonth = true }
                    .buttonStyle(WatchActionStyle()).accessibilityIdentifier("watch.chooseMonth")
                HStack(spacing: 6) {
                    Button { model.moveMonth(-1) } label: { Label("이전", systemImage: "chevron.left") }
                        .accessibilityLabel("이전 달").accessibilityIdentifier("watch.previousMonth")
                    Button { model.moveMonth(1) } label: { Label("다음", systemImage: "chevron.right") }
                        .accessibilityLabel("다음 달").accessibilityIdentifier("watch.nextMonth")
                }.buttonStyle(WatchActionStyle(color: .gray))
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(weekdays.indices, id: \.self) { Text(weekdays[$0]).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(0..<model.month.leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 18) }
                    ForEach(1...model.month.dayCount, id: \.self) { day in
                        let count = model.summary.counts[model.month.dateKey(day: day)] ?? 0
                        RoundedRectangle(cornerRadius: 4).fill(StepIntensity(steps: count).watchColor)
                            .frame(height: 18)
                            .overlay {
                                if day == model.selectedDay { RoundedRectangle(cornerRadius: 4).stroke(.yellow, lineWidth: 2) }
                            }
                    }
                }
                .accessibilityHidden(true) // Date/count selection is available in the full-size list below.
                HStack(spacing: 4) {
                    Text("적음")
                    ForEach(0..<5) { index in RoundedRectangle(cornerRadius: 2).fill(StepIntensity(rawValue: index)!.watchColor).frame(maxWidth: .infinity).frame(height: 10) }
                    Text("많음")
                }.font(.caption2).foregroundStyle(.secondary)
                Text("진한 파랑: 10,000걸음 이상").font(.caption2).foregroundStyle(.secondary)
                NavigationLink {
                    WatchStreakNumberSelection(title: "날짜", suffix: "일", values: 1...model.month.dayCount,
                                               selected: model.selectedDay, select: model.selectDay)
                } label: {
                    LabeledContent("날짜", value: "\(model.selectedDay)일")
                }.buttonStyle(WatchActionStyle()).accessibilityIdentifier("watch.streakDate")
                Text("\(model.month.month)월 \(model.selectedDay)일\n\(model.selectedCount.formatted())걸음")
                    .font(.headline).multilineTextAlignment(.center).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("watch.selectedDaySteps")
                Text("오늘부터 매일 1보 이상 기록하면 이어져요.").font(.caption2).foregroundStyle(.secondary)
                if let error = model.error {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                    Button("다시 불러오기") { Task { await model.refresh() } }
                }
                Divider()
                Button("백업·보상 받기") { Task { await cloud.requestBackup() } }
                    .buttonStyle(WatchActionStyle()).disabled(cloud.account == nil || cloud.isBusy)
                if let date = cloud.lastBackupAt { Text("최근 백업 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                if let message = cloud.message { Text(message).font(.caption2) }
                Text("현재 닉네임\n\(cloud.account?.displayName ?? "미설정")").font(.caption).multilineTextAlignment(.center).lineLimit(2).truncationMode(.middle)
                    .accessibilityLabel("현재 닉네임 \(cloud.account?.displayName ?? "미설정")")
                NavigationLink("닉네임 변경") { WatchNicknameView(editor: cloud.makeNicknameEditor()) }
                    .buttonStyle(WatchActionStyle()).disabled(cloud.account == nil).accessibilityIdentifier("watch.streakNickname")
                if cloud.account == nil { Text("닉네임 변경·백업은 아이폰에서 로그인한 뒤 사용할 수 있어요.").font(.caption2).foregroundStyle(.secondary) }
                NavigationLink("계정·백업") { WatchCloudView(viewModel: cloud) }
                    .buttonStyle(WatchActionStyle()).accessibilityIdentifier("watch.openAccount")
                Text("버전 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("watch.appVersion")
            }.padding(.horizontal, 10).padding(.bottom, 18)
        }
        .navigationTitle("스트릭")
        .task { await model.appear() }
        .onDisappear { model.disappear() }
        .sheet(isPresented: $selectingMonth) {
            NavigationStack {
                List {
                    NavigationLink {
                        WatchStreakNumberSelection(title: "연도", suffix: "년", values: model.years, selected: model.month.year) { year in
                            if let value = StepMonth(year: year, month: model.month.month) { model.select(value) }
                        }
                    } label: { LabeledContent("연도", value: String(model.month.year)) }
                        .accessibilityIdentifier("watch.streakYearPicker")
                    NavigationLink {
                        WatchStreakNumberSelection(title: "월", suffix: "월", values: 1...12, selected: model.month.month) { month in
                            if let value = StepMonth(year: model.month.year, month: month) { model.select(value) }
                        }
                    } label: { LabeledContent("월", value: "\(model.month.month)월") }
                        .accessibilityIdentifier("watch.streakMonthPicker")
                    Button("선택 완료") { selectingMonth = false }
                }.navigationTitle("월 선택")
            }
        }
    }
}

/// Use explicit navigation and dismiss on selection across supported watchOS versions.
private struct WatchStreakNumberSelection: View {
    let title: String
    let suffix: String
    let values: ClosedRange<Int>
    let selected: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            ForEach(values, id: \.self) { value in
                Button {
                    select(value)
                    dismiss()
                } label: {
                    HStack {
                        Text("\(String(value))\(suffix)")
                        Spacer()
                        if value == selected { Image(systemName: "checkmark").foregroundStyle(.green).accessibilityHidden(true) }
                    }
                }.accessibilityIdentifier("watch.streakValue.\(value)")
            }
        }.navigationTitle(title)
    }
}

private extension StepIntensity {
    var watchColor: Color {
        switch self {
        case .none: Color(red: 46/255, green: 46/255, blue: 46/255)
        case .light: Color(red: 108/255, green: 108/255, blue: 108/255)
        case .medium: Color(red: 187/255, green: 222/255, blue: 251/255)
        case .strong: Color(red: 100/255, green: 181/255, blue: 246/255)
        case .goal: Color(red: 33/255, green: 150/255, blue: 243/255)
        }
    }
}
