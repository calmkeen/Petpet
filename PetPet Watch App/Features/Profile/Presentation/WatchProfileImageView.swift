import SwiftUI
import PhotosUI
import UIKit
import PetPetCore

struct WatchProfileImageView: View {
    @StateObject private var model: WatchProfileImageModel
    @State private var selection: PhotosPickerItem?
    @State private var photoError: String?
    let development: Bool
    init(client: WatchFeatureClient, cloud: WatchCloudController) {
        _model = StateObject(wrappedValue: WatchProfileImageModel(client: client, cloud: cloud)); development = cloud.isDevelopment
    }
    var body: some View {
        List {
            Section("현재 대표 이미지") {
                Group {
                    if let bytes = model.profile?.preview?.data, let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        #if DEBUG
                        Image(systemName: "person.crop.circle").resizable().scaledToFit()
                        #else
                        AsyncImage(url: model.profile?.pictureURL) { image in image.resizable().scaledToFit() }
                            placeholder: { Image(systemName: "person.crop.circle").resizable().scaledToFit() }
                        #endif
                    }
                }.frame(maxWidth: .infinity).frame(height: 88).accessibilityLabel(model.profile?.pictureURL == nil ? "대표 이미지 미설정" : "저장된 대표 이미지")
                    .accessibilityIdentifier("profile.picture")
                Text(model.profile?.pictureURL == nil ? "이미지를 선택해 주세요." : "대표 이미지가 저장되어 있어요.")
                    .font(.caption).accessibilityIdentifier("profile.pictureState")
            }
            Section("이미지 변경") {
                PhotosPicker(selection: $selection, matching: .images) { Text("사진 선택") }
                    .disabled(!model.canEdit).accessibilityIdentifier("profile.choosePhoto")
                Button("펫 이미지로 설정") {
                    photoError = nil
                    guard let bytes = UIImage(named: "stepmate_fox_idle")?.pngData() else { photoError = "펫 이미지를 읽지 못했어요."; return }
                    Task { await model.upload(bytes) }
                }.disabled(!model.canEdit).accessibilityIdentifier("profile.usePetImage")
                Button("다시 불러오기") { photoError = nil; Task { await model.load() } }.disabled(!model.canEdit).accessibilityIdentifier("profile.refresh")
            }
            if model.busy { ProgressView("이미지 처리 중") }
            if let message = photoError ?? model.message { Text(message).font(.caption).accessibilityIdentifier("profile.feedback") }
            if development { Text("Debug · 개발 모의 서버에 저장해요.").font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("대표 이미지").task { await model.load() }
            .task(id: selection) {
                guard let selection else { return }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw BackendError.invalidResponse }
                    try Task.checkCancellation(); photoError = nil; await model.upload(data)
                } catch is CancellationError { }
                catch { photoError = "사진을 읽지 못했어요. 다시 선택해 주세요." }
            }
    }
}
