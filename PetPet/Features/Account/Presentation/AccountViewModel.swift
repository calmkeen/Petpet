import Combine
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
    private let google: GoogleSignInProvider
    private var started = false

    init(backend: BackendClient? = nil, cloud: PhoneCloudCoordinator? = nil,
         configuration: AccountConfiguration = AccountConfiguration()) {
        self.backend = backend; self.cloud = cloud; self.configuration = configuration
        google = GoogleSignInProvider(configuration: configuration)
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
            await cloud?.synchronizeAccount()
        } catch { started = false; message = BackendError.storage.localizedDescription }
    }

    func connectionChanged() async {
        await start()
        await cloud?.synchronizeAccount()
    }

    func signIn() async {
        guard let backend, canSignIn, !isSigningIn else { message = BackendError.configurationMissing.localizedDescription; return }
        isSigningIn = true; message = nil
        defer { isSigningIn = false }
        do {
            let identity = try await google.signIn()
            session = try await backend.signIn(identity)
            preview = nil
            await cloud?.synchronizeAccount()
        } catch is CancellationError { }
        catch { message = (error as? BackendError ?? .network).localizedDescription }
    }

    func signOut() async {
        do {
            try await backend?.signOut()
            google.signOut()
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
