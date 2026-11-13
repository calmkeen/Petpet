import SwiftUI
import PhotosUI
import UIKit
import PetPetCore

struct PhoneAccountAvatar: View {
    let details: AccountProfileDetails?
    var body: some View {
        Group {
            if let bytes = details?.preview?.data, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                #if DEBUG
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(PhoneDesign.accent)
                #else
                AsyncImage(url: details?.pictureURL) { image in image.resizable().scaledToFit() }
                    placeholder: { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(PhoneDesign.accent) }
                #endif
            }
        }.accessibilityLabel(details?.pictureURL == nil ? "대표 이미지 미설정" : "저장된 대표 이미지")
    }
}
struct PhoneProfilePictureView: View {
    @ObservedObject var account: AccountViewModel
    @State private var selection: PhotosPickerItem?
    @State private var photoError: String?
    var body: some View {
        List {
            if account.session == nil {
                Text("계정에서 로그인한 뒤 대표 이미지를 변경해 주세요.").accessibilityIdentifier("phone.pictureLoginNotice")
            }
            Section("현재 대표 이미지") {
                PhoneAccountAvatar(details: account.profileDetails).frame(maxWidth: .infinity).frame(height: 160)
                    .accessibilityIdentifier("phone.profilePicture")
                Text(account.profileDetails?.pictureURL == nil ? "이미지를 선택해 주세요." : "대표 이미지가 저장되어 있어요.")
                    .font(.callout).accessibilityIdentifier("phone.profilePictureState")
            }
            Section("이미지 변경") {
                PhotosPicker(selection: $selection, matching: .images) { Label("사진 선택", systemImage: "photo") }
                    .frame(minHeight: 44).disabled(account.isUpdatingPicture || account.session == nil).accessibilityIdentifier("phone.choosePicture")
                Button("펫 이미지로 설정") {
                    photoError = nil
                    guard let data = UIImage(named: "stepmate_fox_idle")?.pngData() else { photoError = "펫 이미지를 읽지 못했어요."; return }
                    Task { await account.updatePicture(data) }
                }.buttonStyle(PhoneActionStyle()).disabled(account.isUpdatingPicture || account.session == nil).accessibilityIdentifier("phone.usePetPicture")
                Button("다시 불러오기") { Task { await account.refreshProfile() } }
                    .frame(minHeight: 44).disabled(account.isUpdatingPicture || account.isRefreshingProfile || account.session == nil).accessibilityIdentifier("phone.refreshPicture")
            }
            if account.isUpdatingPicture || account.isRefreshingProfile { ProgressView("이미지 처리 중") }
            if let message = photoError ?? account.pictureMessage { Text(message).font(.callout).accessibilityIdentifier("phone.pictureFeedback") }
            if account.configuration.isDevelopment { Text("Debug · 이 아이폰의 모의 서버에 저장해요.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("대표 이미지").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .tint(PhoneDesign.accent).task { await account.refreshProfile() }
            .task(id: selection) {
                guard let selection else { return }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw BackendError.invalidResponse }
                    try Task.checkCancellation(); photoError = nil; await account.updatePicture(data)
                } catch is CancellationError { }
                catch { photoError = "사진을 읽지 못했어요. 다른 사진을 선택해 주세요." }
            }
    }
}
