import Combine
import AuthenticationServices
import Foundation
import PetPetCore

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var session: BackendSession?
    @Published private(set) var cloudState = PhoneCloudState()
    @Published private(set) var isSigningIn = false
    @Published private(set) var isPreparingRestore = false
    @Published private(set) var message: String?
    @Published private(set) var preview: WatchRestoreImport?
    @Published private(set) var profileDetails: AccountProfileDetails?
    @Published private(set) var isRefreshingProfile = false
    @Published private(set) var isUpdatingPicture = false
    @Published private(set) var pictureMessage: String?
    private var profileRevision = UUID()
    let configuration: AccountConfiguration
    private let backend: BackendClient?
    private let cloud: PhoneCloudCoordinator?
    private let profile: PhoneProfileCoordinator?
    private let apple = AppleSignInProvider()
    private var started = false

    init(backend: BackendClient? = nil, cloud: PhoneCloudCoordinator? = nil, profile: PhoneProfileCoordinator? = nil,
         configuration: AccountConfiguration = AccountConfiguration()) {
        self.backend = backend; self.cloud = cloud; self.profile = profile; self.configuration = configuration
        cloud?.onStateChange = { [weak self] in self?.cloudState = $0 }
        cloud?.onSessionChange = { [weak self] session in self?.session = session }
        profile?.onProfileChange = { [weak self] in
            guard let self else { return }
            self.session = try? await self.backend?.session()
            await self.cloud?.synchronizeAccount()
        }
    }

    var isBusy: Bool { isSigningIn || isPreparingRestore || isUpdatingPicture || cloudState.phase != .idle }
    var canSignIn: Bool { configuration.canSignIn && backend != nil }
    var feedback: String? { message ?? cloudState.error?.localizedDescription ?? cloudState.message }

    func start() async {
        guard !started else { return }
        started = true
        do {
            session = try await backend?.session()
            await checkAppleCredential()
            await cloud?.synchronizeAccount()
        } catch { started = false; message = BackendError.storage.localizedDescription }
    }

    func connectionChanged() async {
        await start()
        await cloud?.synchronizeAccount()
    }

    func refreshProfile() async {
        guard !isSigningIn, !isRefreshingProfile, !isUpdatingPicture, let backend, let id = session?.accountID else { return }
        let token = profileRevision; isRefreshingProfile = true
        defer { if token == profileRevision { isRefreshingProfile = false } }
        do {
            let details = try await backend.profileDetails(accountID: id)
            guard token == profileRevision, session?.accountID == id, !Task.isCancelled else { return }
            profileDetails = details
            session = try await backend.session()
            await cloud?.synchronizeAccount()
        } catch is CancellationError { }
        catch { if token == profileRevision { pictureMessage = (error as? BackendError ?? .network).localizedDescription } }
    }
    func updatePicture(_ data: Data) async {
        guard !isSigningIn, !isUpdatingPicture, let backend, let id = session?.accountID else { return }
        profileRevision = UUID(); let token = profileRevision
        isRefreshingProfile = false; isUpdatingPicture = true; pictureMessage = nil
        defer { if token == profileRevision { isUpdatingPicture = false } }
        let image: RepresentativeImage
        do { image = try RepresentativeImage.thumbnail(from: data) }
        catch { pictureMessage = "사진을 읽지 못했어요. 다른 사진을 선택해 주세요."; return }
        do {
            let result = try await backend.updatePicture(image, accountID: id)
            guard token == profileRevision, session?.accountID == id, !Task.isCancelled else { return }
            profileDetails = result; pictureMessage = "대표 이미지를 바꿨어요."
        } catch is CancellationError { }
        catch { if token == profileRevision { pictureMessage = (error as? BackendError ?? .network).localizedDescription } }
    }
    func acceptProfile(_ details: AccountProfileDetails, accountID: String) {
        guard session?.accountID == accountID, !isUpdatingPicture else { return }
        profileRevision = UUID(); isRefreshingProfile = false; profileDetails = details; pictureMessage = nil
    }
    func makeRankingModel(_ kind: PhoneRankingPageModel.Kind) -> PhoneRankingPageModel {
        PhoneRankingPageModel(kind: kind, backend: backend, account: self)
    }
    private func clearProfileState() {
        profileRevision = UUID(); profileDetails = nil; isRefreshingProfile = false; isUpdatingPicture = false; pictureMessage = nil
    }
    func refreshServerSession() async {
        do {
            session = try await backend?.session()
            if session == nil { preview = nil; clearProfileState() }
            await cloud?.synchronizeAccount()
        } catch { message = BackendError.storage.localizedDescription }
    }
    func makeNicknameEditor() -> NicknameEditor {
        let id = session?.accountID
        return NicknameEditor(currentNickname: session?.nickname ?? "미설정", check: { [weak self] value in
            guard let self, let id, self.session?.accountID == id, let profile = self.profile else { throw BackendError.authenticationRequired }
            return try await profile.check(value, accountID: id)
        }, update: { [weak self] value in
            guard let self, let id, self.session?.accountID == id, let profile = self.profile else { throw BackendError.authenticationRequired }
            return try await profile.update(value, accountID: id)
        })
    }

    #if DEBUG
    func signInForDevelopment() async {
        guard let backend, !isSigningIn else { return }
        isSigningIn = true; message = nil
        defer { isSigningIn = false }
        do {
            session = try await backend.signInForDevelopment()
            preview = nil; clearProfileState()
            await cloud?.synchronizeAccount()
            isSigningIn = false; await refreshProfile()
        } catch { message = error.localizedDescription }
    }
    #endif

    func beginSignIn(_ request: ASAuthorizationAppleIDRequest) {
        guard canSignIn, !isSigningIn else { return }
        isSigningIn = true; message = nil
        do { try apple.configure(request) }
        catch { isSigningIn = false; message = error.localizedDescription }
    }

    func completeSignIn(_ result: Result<ASAuthorization, Error>) async {
        defer { isSigningIn = false }
        do {
            let identity = try apple.identity(from: result)
            guard let backend, canSignIn else { throw BackendError.configurationMissing }
            session = try await backend.signIn(identity)
            apple.confirmProfile(for: identity.userIdentifier)
            preview = nil; clearProfileState()
            await cloud?.synchronizeAccount()
            isSigningIn = false; await refreshProfile()
        } catch is CancellationError { }
        catch {
            session = try? await backend?.session()
            await cloud?.synchronizeAccount()
            message = error.localizedDescription
        }
    }

    func checkAppleCredential() async {
        guard !isSigningIn, let session, session.identityProvider == .apple,
              let subject = session.providerSubject else { return }
        do {
            let authorized = try await apple.credentialIsAuthorized(for: subject)
            // A late credential check must not clear a newly signed-in account.
            guard !isSigningIn, self.session == session else { return }
            if !authorized {
                try await backend?.signOut()
                self.session = nil; preview = nil; clearProfileState()
                await cloud?.synchronizeAccount()
                message = "Apple 계정 연결이 해제되었어요. 다시 로그인해 주세요."
            }
        } catch {
            // An unsuccessful state query is not proof of revocation.
        }
    }

    func signOut() async {
        do {
            try await backend?.signOut()
            session = nil; preview = nil; message = nil; clearProfileState()
            await cloud?.synchronizeAccount()
        } catch { message = BackendError.storage.localizedDescription }
    }

    func backup() async { message = nil; await cloud?.requestBackup() }

    func prepareRestore() async {
        guard let cloud, !isBusy else { return }
        isPreparingRestore = true; message = nil
        defer { isPreparingRestore = false }
        do { preview = try await cloud.prepareRestore() }
        catch { message = (error as? BackendError ?? .network).localizedDescription }
    }

    func cancelPreview() { preview = nil }
    func applyRestore() async {
        guard let preview else { return }
        self.preview = nil
        message = nil
        await cloud?.restore(preview)
    }
}
