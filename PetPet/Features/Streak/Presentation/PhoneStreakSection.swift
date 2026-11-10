import SwiftUI
import PetPetCore

struct PhoneStreakSection: View {
    @ObservedObject var model: PhoneStreakViewModel
    let accountID: String?
    @ScaledMetric(relativeTo: .caption2) private var cellSize = 16
    var body: some View {
        PhoneCard {
            PhoneSectionTitle(title: "스트릭", icon: "calendar")
            if accountID == nil {
                Text("로그인하고 워치 기록을 백업하면 여기서도 볼 수 있어요.").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("연속 \(model.summary.currentDays)일").font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("phone.currentStreak")
                    Spacer()
                    Button { Task { await model.refresh(accountID: accountID, force: true) } } label: {
                        if model.isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }.buttonStyle(PhoneIconStyle()).accessibilityIdentifier("phone.refreshStreak")
                        .disabled(model.isLoading).accessibilityLabel("스트릭 새로고침")
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { _, label in
                            Text(label).font(.caption2).frame(width: cellSize, height: cellSize)
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
                                                .frame(width: cellSize, height: cellSize)
                                        }
                                        Text(monthLabel(week)).font(.caption2).foregroundStyle(.secondary)
                                            .fixedSize().frame(width: cellSize, alignment: .leading).padding(.top, 6)
                                    }.id(column)
                                }
                            }.padding(.vertical, 2)
                        }
                        .accessibilityLabel("최근 365일 백업 걸음 기록")
                        .onAppear { proxy.scrollTo(model.weeks.count - 1, anchor: .trailing) }
                    }
                }
                VStack(spacing: 6) {
                    HStack { Text("적음"); Spacer(); Text("많음") }.font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(0..<5) { index in
                            RoundedRectangle(cornerRadius: 3).fill(color(StepIntensity(rawValue: index)))
                                .frame(maxWidth: .infinity).frame(height: 10)
                        }
                    }.accessibilityHidden(true)
                    Text("진한 파랑: 10,000걸음 이상").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("최근 365일 · 마지막 백업 기록일 기준으로 하루 1보 이상 이어진 일수예요.").font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }

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
