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
    let configuration: AccountConfiguration
    private let backend: BackendClient?
    private let cloud: PhoneCloudCoordinator?
    private let apple = AppleSignInProvider()
    private var started = false

    init(backend: BackendClient? = nil, cloud: PhoneCloudCoordinator? = nil,
         configuration: AccountConfiguration = AccountConfiguration()) {
        self.backend = backend; self.cloud = cloud; self.configuration = configuration
        cloud?.onStateChange = { [weak self] in self?.cloudState = $0 }
        cloud?.onSessionChange = { [weak self] session in self?.session = session }
    }

    var isBusy: Bool { isSigningIn || isPreparingRestore || cloudState.phase != .idle }
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
            preview = nil
            await cloud?.synchronizeAccount()
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
                self.session = nil; preview = nil
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
            session = nil; preview = nil; message = nil
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
