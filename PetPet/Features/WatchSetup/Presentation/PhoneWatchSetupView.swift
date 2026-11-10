import SwiftUI

struct PhoneWatchSetupView: View {
    @ObservedObject var viewModel: PhoneHomeViewModel

    var body: some View {
        List {
            Section("현재 연결") {
                Label(viewModel.connectionText, systemImage: "applewatch")
                    .accessibilityIdentifier("phone.watchSetupStatus")
                Text(viewModel.syncNote).font(.footnote).foregroundStyle(.secondary)
                Button("연결 상태 다시 확인") { Task { await viewModel.refresh() } }
                    .buttonStyle(PhoneActionStyle())
                    .disabled(viewModel.isRefreshing).accessibilityIdentifier("phone.checkWatchConnection")
            }
            Section("처음 연결하기") {
                Text("아이폰에서 Watch 앱을 열고 ‘페어링 시작’으로 Apple Watch를 연결해 주세요.")
                Text("같은 Apple 계정으로 로그인하는 것과 별개로, 이 아이폰과 워치가 페어링되어 있어야 해요.")
            }
            Section("워치에 PetPet 설치") {
                Text("아이폰의 Watch 앱 → 나의 시계에서 ‘사용 가능한 앱’을 찾아 PetPet 옆의 ‘설치’를 눌러 주세요. ‘앱’ 메뉴가 보이면 먼저 들어가 주세요.")
                Text("설치가 끝나면 아이폰과 워치에서 PetPet을 모두 열어 주세요.")
                #if DEBUG
                Text("개발 중에는 Xcode에서 양쪽에 같은 Debug 빌드를 설치해 주세요.").font(.caption).foregroundStyle(.secondary)
                #endif
            }
            Section("동기화가 늦을 때") {
                Text("아이폰과 워치를 가까이 두고 Bluetooth와 Wi-Fi를 켜 주세요. 워치의 잠금을 풀고 두 앱을 열어 둔 뒤 다시 확인해 주세요.")
                Text("연결이 없을 때는 마지막으로 받은 워치 기록을 표시해요. 서버에 백업한 펫은 로그인 후 별도로 볼 수 있어요.")
            }
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                Text("PetPet \(version) (\(build))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("워치 연결과 설치")
        .navigationBarTitleDisplayMode(.inline).tint(PhoneDesign.accent)
        .toolbar(.visible, for: .navigationBar)
    }
}
