import SwiftUI
import PetPetCore

struct PhoneStreakSection: View {
    @ObservedObject var model: PhoneStreakViewModel
    let accountID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("스트릭", systemImage: "calendar").font(.headline)
            if accountID == nil {
                Text("로그인하고 워치 기록을 백업하면 여기서도 볼 수 있어요.").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("연속 \(model.summary.currentDays)일").font(.largeTitle.bold())
                        .accessibilityIdentifier("phone.currentStreak")
                    Spacer()
                    if model.isLoading { ProgressView() }
                    Button { Task { await model.refresh(accountID: accountID, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.isLoading).accessibilityLabel("스트릭 새로고침")
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { _, label in
                            Text(label).font(.system(size: 10)).frame(width: 12, height: 12)
                        }
                    }.padding(.vertical, 2).foregroundStyle(.secondary).accessibilityHidden(true)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 4) {
                                ForEach(Array(model.weeks.enumerated()), id: \.offset) { column, week in
                                    VStack(spacing: 4) {
                                        ForEach(week.indices, id: \.self) { row in
                                            let key = week[row]
                                            RoundedRectangle(cornerRadius: 3).fill(color(key.map { StepIntensity(steps: model.summary.counts[$0] ?? 0) }))
                                                .frame(width: 12, height: 12)
                                        }
                                        Text(monthLabel(week)).font(.system(size: 10)).foregroundStyle(.secondary)
                                            .fixedSize().frame(width: 12, alignment: .leading).padding(.top, 6)
                                    }.id(column)
                                }
                            }.padding(.vertical, 2)
                        }
                        .accessibilityLabel("최근 365일 백업 걸음 기록")
                        .onAppear { proxy.scrollTo(model.weeks.count - 1, anchor: .trailing) }
                    }
                }
                HStack(spacing: 5) {
                    Text("0걸음")
                    ForEach(0..<5) { colorIndex in RoundedRectangle(cornerRadius: 2).fill(color(StepIntensity(rawValue: colorIndex))).frame(width: 13, height: 10) }
                    Text("10,000걸음 이상")
                }.font(.caption2).foregroundStyle(.secondary)
                Text("최근 365일 · 마지막 백업 기록일 기준으로 하루 1보 이상 이어진 일수예요.").font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
    private func monthLabel(_ week: [String?]) -> String {
        guard let first = week.compactMap({ $0 }).first(where: { $0.hasSuffix("-01") }),
              let month = Int(first.dropFirst(5).prefix(2)) else { return "" }
        return "\(month)월"
    }
    private func color(_ intensity: StepIntensity?) -> Color {
        switch intensity {
        case nil: Color(red: 28/255, green: 28/255, blue: 28/255)
        case .some(.none): Color(red: 46/255, green: 46/255, blue: 46/255)
        case .light: Color(red: 108/255, green: 108/255, blue: 108/255)
        case .medium: Color(red: 187/255, green: 222/255, blue: 251/255)
        case .strong: Color(red: 100/255, green: 181/255, blue: 246/255)
        case .goal: Color(red: 33/255, green: 150/255, blue: 243/255)
        }
    }
}
